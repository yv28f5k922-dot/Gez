/// Taxes by class, banks and loans, debasement and inflation, bankruptcy.

public struct BankID: Hashable, Sendable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

/// Banking houses. Each has limited money; loans take from it, repayments
/// (with interest) give it back, so banks that lend well grow.
public struct BankTable: Sendable {
    public private(set) var name: [String] = []
    public private(set) var home: [ProvinceID] = []
    /// Ducats available to lend right now.
    public var capital: [Double] = []
    /// Yearly interest for a borrower with no debt.
    public private(set) var baseRate: [Double] = []
    /// Regions the bank lends in; empty = everywhere.
    public private(set) var regions: [[RegionID]] = []

    public init() {}

    public var count: Int { name.count }
    public var ids: [BankID] { (0..<count).map(BankID.init) }

    @discardableResult
    public mutating func add(name: String, home: ProvinceID, capital: Double, baseRate: Double, regions: [RegionID]) -> BankID {
        let id = BankID(count)
        self.name.append(name)
        self.home.append(home)
        self.capital.append(capital)
        self.baseRate.append(baseRate)
        self.regions.append(regions)
        return id
    }
}

public struct Loan: Sendable, Equatable {
    public var country: CountryID
    public var bank: BankID
    public var principal: Double
    /// Yearly interest rate, fixed when the loan is taken.
    public var rate: Double
    public var monthsLeft: Int

    public var monthlyInterest: Double { principal * rate / 12 }
}

/// Tax level per class: 1 is normal, 0 untaxed, up to `TaxLevel.max`.
public enum TaxClass: Int, CaseIterable, Sendable {
    case peasants, burghers, nobles, clergy

    public var socialClass: SocialClass {
        switch self {
        case .peasants: return .peasants
        case .burghers: return .burghers
        case .nobles: return .nobles
        case .clergy: return .clergy
        }
    }

    public init?(_ c: SocialClass) {
        switch c {
        case .peasants: self = .peasants
        case .burghers: self = .burghers
        case .nobles: self = .nobles
        case .clergy: self = .clergy
        case .slaves: return nil
        }
    }

    /// Share of farm and mine value each class's tax is drawn from
    /// (burghers are taxed on workshop profits instead).
    public var shareOfLand: Double {
        switch self {
        case .peasants: return 0.6
        case .nobles: return 0.3
        case .clergy: return 0.1
        case .burghers: return 0
        }
    }

    /// Tax rate at level 1. Land taxes add up to 2.5% of farm and mine value.
    public var normalRate: Double {
        switch self {
        case .peasants: return 0.03
        case .nobles: return 0.015
        case .clergy: return 0.025
        case .burghers: return 0.03
        }
    }
}

public struct Finance: Sendable {
    public var banks = BankTable()
    public var loans: [Loan] = []

    public init() {}

    public static let loanSizes: [Double] = [50, 100, 250, 500]
    public static let loanMonths = 60
    /// Banks won't lend past this many years of income in debt.
    public static let maxDebtYears = 3.0
    public static let maxRate = 0.4
    public static let maxTaxLevel = 2.0
    /// Months of no lending and lower income after a default.
    public static let bankruptcyMonths = 60
    public static let bankruptcyIncome = 0.75
    public static let bankruptcyMood = 0.15
    /// One-off debasement: months of income gained, inflation added.
    public static let debaseOnceMonths = 3.0
    public static let debaseOnceInflation = 0.05
    /// Ongoing debasement: extra income share, inflation per month.
    public static let debaseOngoingIncome = 0.2
    public static let debaseOngoingInflation = 0.004
    /// Inflation falls by this much a month when not debasing.
    public static let inflationDecay = 0.0015

    public func debt(of c: CountryID) -> Double {
        loans.filter { $0.country == c }.reduce(0) { $0 + $1.principal }
    }

    public func interest(of c: CountryID) -> Double {
        loans.filter { $0.country == c }.reduce(0) { $0 + $1.monthlyInterest }
    }
}

extension World {
    /// Satisfaction change from taxing a class above or below normal.
    public func taxMood(_ country: CountryID, _ cls: SocialClass) -> Double {
        guard let tc = TaxClass(cls) else { return 0 }
        let level = countries.taxLevel[country.index][tc.rawValue]
        return level > 1 ? -0.12 * (level - 1) : 0.05 * (1 - level)
    }

    /// Satisfaction change from inflation (burghers hate it most) and bankruptcy.
    public func financeMood(_ country: CountryID, _ cls: SocialClass) -> Double {
        let inflation = countries.inflation[country.index]
        var mood = -inflation * (cls == .burghers ? 0.8 : (cls == .nobles ? 0.4 : 0.2))
        if countries.bankruptMonthsLeft[country.index] > 0 { mood -= Finance.bankruptcyMood }
        return mood
    }

    /// Yearly rate this bank would charge this country now, or nil if it
    /// won't lend (out of reach, bankrupt borrower).
    public func loanRate(_ bank: BankID, for country: CountryID) -> Double? {
        let c = country.index
        guard countries.bankruptMonthsLeft[c] == 0 else { return nil }
        let reach = finance.banks.regions[bank.index]
        if !reach.isEmpty {
            guard let capital = countries.capital[c] else { return nil }
            let region = states.region[provinces.state[capital.index].index]
            guard reach.contains(region) else { return nil }
        }
        let yearlyIncome = max(1, countries.lastMonthlyIncome[c] * 12)
        let ratio = finance.debt(of: country) / yearlyIncome
        guard ratio < Finance.maxDebtYears else { return nil }
        let lawFactor = max(0.5, 1 + government.modifier(country, .interest))
        return min(Finance.maxRate, finance.banks.baseRate[bank.index] * (1 + ratio) * lawFactor)
    }
}

public enum FinanceSystem {
    @discardableResult
    public static func borrow(_ world: inout World, _ country: CountryID, from bank: BankID, amount: Double) -> Bool {
        guard let rate = world.loanRate(bank, for: country),
              world.finance.banks.capital[bank.index] >= amount, amount > 0 else { return false }
        world.finance.banks.capital[bank.index] -= amount
        world.countries.treasury[country.index] += amount
        world.finance.loans.append(Loan(country: country, bank: bank, principal: amount, rate: rate,
                                        monthsLeft: Finance.loanMonths))
        return true
    }

    /// Pays back a loan early. Index into `world.finance.loans`.
    @discardableResult
    public static func repay(_ world: inout World, loan index: Int) -> Bool {
        guard world.finance.loans.indices.contains(index) else { return false }
        let loan = world.finance.loans[index]
        guard world.countries.treasury[loan.country.index] >= loan.principal else { return false }
        world.countries.treasury[loan.country.index] -= loan.principal
        world.finance.banks.capital[loan.bank.index] += loan.principal
        world.finance.loans.remove(at: index)
        return true
    }

    /// Debase once: quick cash, more inflation.
    public static func debaseOnce(_ world: inout World, _ country: CountryID) -> Double {
        guard GovernmentSystem.canDebase(world, country) else { return 0 }
        let gain = max(10, world.countries.lastMonthlyIncome[country.index] * Finance.debaseOnceMonths)
        world.countries.treasury[country.index] += gain
        world.countries.inflation[country.index] += Finance.debaseOnceInflation
        return gain
    }

    /// The cheapest bank that would lend this much, if any.
    public static func cheapestBank(_ world: World, _ country: CountryID, amount: Double) -> BankID? {
        world.finance.banks.ids
            .filter { world.finance.banks.capital[$0.index] >= amount }
            .compactMap { b in world.loanRate(b, for: country).map { (b, $0) } }
            .min { $0.1 < $1.1 }?.0
    }

    /// Monthly, after income and upkeep: interest, ongoing debasement,
    /// inflation, loans falling due, and bankruptcy when out of options.
    public static func runMonthly(_ world: inout World) {
        let C = world.countries.count
        var interest = Array(repeating: 0.0, count: C)
        for loan in world.finance.loans {
            interest[loan.country.index] += loan.monthlyInterest
            world.finance.banks.capital[loan.bank.index] += loan.monthlyInterest
        }
        for c in 0..<C {
            world.countries.treasury[c] -= interest[c]
            world.countries.lastInterest[c] = interest[c]
            world.countries.lastMonthlyExpenses[c] += interest[c]
            if world.countries.debasing[c] && !GovernmentSystem.canDebase(world, CountryID(c)) {
                world.countries.debasing[c] = false
            }
            if world.countries.debasing[c] {
                world.countries.treasury[c] += world.countries.lastMonthlyIncome[c] * Finance.debaseOngoingIncome
                world.countries.inflation[c] += Finance.debaseOngoingInflation
            } else {
                let decay = Finance.inflationDecay + world.government.modifier(CountryID(c), .inflationDecay)
                world.countries.inflation[c] = max(0, world.countries.inflation[c] - decay)
            }
            if world.countries.bankruptMonthsLeft[c] > 0 { world.countries.bankruptMonthsLeft[c] -= 1 }
        }

        // Loans falling due: repay if there is money, otherwise roll over at
        // today's rate (or default if no bank will).
        var kept: [Loan] = []
        var defaulting = Set<CountryID>()
        for var loan in world.finance.loans {
            loan.monthsLeft -= 1
            if loan.monthsLeft > 0 { kept.append(loan); continue }
            let c = loan.country.index
            if world.countries.treasury[c] >= loan.principal {
                world.countries.treasury[c] -= loan.principal
                world.finance.banks.capital[loan.bank.index] += loan.principal
            } else if let rate = world.loanRate(loan.bank, for: loan.country) {
                loan.rate = rate
                loan.monthsLeft = Finance.loanMonths
                kept.append(loan)
            } else {
                kept.append(loan)
                defaulting.insert(loan.country)
            }
        }
        world.finance.loans = kept
        for c in defaulting.sorted(by: { $0.index < $1.index }) { bankrupt(&world, c) }

        // Out of money: borrow the shortfall, or go bankrupt.
        for c in world.countries.ids where world.countries.treasury[c.index] < 0 {
            let need = (-world.countries.treasury[c.index] / 50).rounded(.up) * 50
            if let bank = cheapestBank(world, c, amount: need) {
                borrow(&world, c, from: bank, amount: need)
            } else {
                bankrupt(&world, c)
            }
        }
    }

    /// Debts are cancelled (the banks lose the money); no loans, lower income
    /// and angry people for five years.
    public static func bankrupt(_ world: inout World, _ country: CountryID) {
        world.finance.loans.removeAll { $0.country == country }
        world.countries.treasury[country.index] = 0
        world.countries.bankruptMonthsLeft[country.index] = Finance.bankruptcyMonths
        world.countries.debasing[country.index] = false
        if country.index < world.government.count {
            GovernmentSystem.changeStability(&world, country, by: -2)
        }
    }

    /// Computer countries pay off loans when they have plenty, and stop
    /// debasing (they never start; that's a player's gamble).
    public static func runAI(_ world: inout World) {
        for c in world.countries.ids where !world.humanCountries.contains(c) {
            world.countries.debasing[c.index] = false
            let reserve = max(50, world.countries.lastMonthlyIncome[c.index] * 6)
            while let i = world.finance.loans.firstIndex(where: { $0.country == c }),
                  world.countries.treasury[c.index] - world.finance.loans[i].principal > reserve {
                repay(&world, loan: i)
            }
        }
    }
}
