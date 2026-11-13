import Foundation

/// Tuning for laws, estates, stability and reforms.
public enum GovernmentModel {
    public static let minStability = -3
    public static let maxStability = 3
    /// Per point of stability: tax income, contentment, reform progress.
    public static let stabilityTax = 0.03
    public static let stabilityMood = 0.02
    public static let stabilityReform = 0.15
    /// Raising stability costs this many months of income (at least 25 ducats),
    /// more the higher it already is.
    public static let stabilityCostMonths = 2.0
    /// Reform progress every month before stability and laws.
    public static let baseReformProgress = 0.4
    /// A law change costs one month of income and takes six months.
    public static let lawChangeMonths = 6
    public static let lawChangeCostMonths = 1.0
    /// Loyal at 60 or more, disloyal below 30.
    public static let loyalAt = 60.0
    public static let disloyalBelow = 30.0
    public static let loyaltySpeed = 0.1
    /// Crown's own raw power as a share of the estates' total, by government.
    public static func crownBase(_ g: GovernmentType) -> Double {
        switch g {
        case .monarchy: return 0.45
        case .theocracy: return 0.4
        case .republic: return 0.3
        case .steppeHorde: return 0.35
        case .tribal: return 0.2
        }
    }
    /// A disloyal estate with this much power may seize a privilege.
    public static let seizePower = 0.35
    public static let seizeLoyalty = 20.0
    public static let seizeChance = 0.05
    /// Revoking a privilege: grudge = this × its loyalty, fading 3% a month.
    public static let revokeGrudge = 2.0
    public static let grudgeFade = 0.97
}

/// Laws, estates, privileges, stability and reforms.
public enum GovernmentSystem {

    // MARK: Power and loyalty

    /// Which estate a pop belongs to in this country (nil = none, e.g. slaves).
    public static func estate(of pop: Int, in c: CountryID, _ world: World) -> EstateID? {
        let rules = world.government.rules
        let pops = world.pops
        let cls = pops.socialClass[pop]
        if cls == .slaves { return nil }
        let present = world.government.estates[c.index]
        for e in present {
            switch rules.estates[e.index].source {
            case .dhimmi:
                if world.countries.religion[c.index].family == .muslim && pops.religion[pop].family != .muslim { return e }
            case .rajput:
                if cls == .nobles && pops.religion[pop] == .hindu && rules.rajputCultures.contains(pops.culture[pop]) { return e }
            case .tribes:
                if (cls == .nobles || cls == .peasants) && rules.tribalCultures.contains(pops.culture[pop]) { return e }
            case .socialClass, .fixed:
                continue
            }
        }
        for e in present {
            if case .socialClass(let k) = rules.estates[e.index].source, k == cls { return e }
        }
        return nil
    }

    /// Recomputes every estate's power share and contentment from its pops.
    public static func refreshPower(_ world: inout World, _ c: CountryID, owned: [ProvinceID]? = nil) {
        let rules = world.government.rules
        let n = rules.estates.count
        var raw = Array(repeating: 0.0, count: n)
        var size = Array(repeating: 0.0, count: n)
        var happy = Array(repeating: 0.0, count: n)
        for p in owned ?? world.provinces(ownedBy: c) {
            for i in world.pops.range(for: p) {
                guard let e = estate(of: i, in: c, world) else { continue }
                let s = world.pops.size[i] / 1000
                raw[e.index] += s * rules.estates[e.index].weight * (0.5 + world.pops.satisfaction[i])
                size[e.index] += s
                happy[e.index] += s * world.pops.satisfaction[i]
            }
        }
        let popTotal = raw.reduce(0, +)
        let fx = world.government.effects[c.index]
        for e in world.government.estates[c.index] {
            if case .fixed(let share) = rules.estates[e.index].source { raw[e.index] = share * popTotal }
            raw[e.index] *= max(0.1, 1 + fx.power[e.index])
        }
        let crown = max(0, GovernmentModel.crownBase(world.countries.government[c.index]) * popTotal * (1 + fx[.crownPower]))
        let total = raw.reduce(0, +) + crown
        for e in 0..<n {
            world.government.power[c.index][e] = total > 0 ? raw[e] / total : 0
            world.government.contentment[c.index][e] = size[e] > 0 ? happy[e] / size[e] : 0.5
        }
        world.government.crownPower[c.index] = total > 0 ? crown / total : 1
    }

    /// Where an estate's loyalty is heading.
    public static func loyaltyTarget(_ world: World, _ c: CountryID, _ e: EstateID) -> Double {
        let g = world.government
        let def = g.rules.estates[e.index]
        var t = 50.0 + g.effects[c.index].loyalty[e.index] - g.grudge[c.index][e.index]
        if case .fixed = def.source {} else {
            t += (g.contentment[c.index][e.index] - 0.5) * 40
        }
        t += Double(g.stability[c.index]) * 3
        // The stronger an estate, the more it expects.
        t -= g.power[c.index][e.index] * 25
        if case .socialClass(let cls) = def.source, let tc = TaxClass(cls) {
            t -= (world.countries.taxLevel[c.index][tc.rawValue] - 1) * 20
        }
        return max(0, min(100, t))
    }

    /// Brings power, loyalty and effects to their settled values (game start).
    public static func settle(_ world: inout World) {
        guard world.government.count == world.countries.count else { return }
        for c in world.countries.ids {
            for _ in 0..<3 {
                refreshEffects(&world, c)
                refreshPower(&world, c)
                for e in world.government.estates[c.index] {
                    world.government.loyalty[c.index][e.index] = loyaltyTarget(world, c, e)
                }
            }
            refreshEffects(&world, c)
        }
    }

    // MARK: Effects

    /// Sums laws, reforms, privileges and estate moods into `effects`.
    public static func refreshEffects(_ world: inout World, _ c: CountryID) {
        let g = world.government
        let rules = g.rules
        let i = c.index
        var fx = Effects(estates: rules.estates.count)
        for (a, o) in g.laws[i].enumerated() where a < rules.lawAreas.count && o < rules.lawAreas[a].options.count {
            fx.add(rules.lawAreas[a].options[o].effects)
        }
        if let tree = rules.reforms[world.countries.government[i]] {
            for (t, o) in g.reforms[i].enumerated() where t < tree.count && o < tree[t].options.count {
                fx.add(tree[t].options[o].effects)
            }
        }
        for p in g.privileges[i] {
            let def = rules.privileges[p]
            fx.add(def.effects)
            fx.loyalty[def.estate.index] += def.loyalty
            fx.power[def.estate.index] += def.power
        }
        for e in g.estates[i] {
            let loyalty = g.loyalty[i][e.index]
            let def = rules.estates[e.index]
            if loyalty >= GovernmentModel.loyalAt {
                fx.add(def.loyal)
            } else if loyalty < GovernmentModel.disloyalBelow {
                fx.add(def.disloyal, times: min(1, g.power[i][e.index] * 2))
            }
        }
        world.government.effects[i] = fx
    }

    // MARK: Queries for other systems

    /// Extra tax income share (stability and modifiers).
    public static func taxModifier(_ world: World, _ c: CountryID) -> Double {
        guard c.index < world.government.count else { return 0 }
        return world.government.modifier(c, .tax) + Double(world.government.stability[c.index]) * GovernmentModel.stabilityTax
    }

    public static func classTaxModifier(_ world: World, _ c: CountryID, _ tc: TaxClass) -> Double {
        switch tc {
        case .nobles: return world.government.modifier(c, .taxNobles)
        case .clergy: return world.government.modifier(c, .taxClergy)
        case .burghers: return world.government.modifier(c, .taxBurghers)
        case .peasants: return world.government.modifier(c, .taxPeasants)
        }
    }

    public static func canDebase(_ world: World, _ c: CountryID) -> Bool {
        world.government.modifier(c, .noDebase) <= 0
    }

    public static func stabilityCost(_ world: World, _ c: CountryID) -> Double {
        let s = world.government.stability[c.index]
        let base = max(25, world.countries.lastMonthlyIncome[c.index] * GovernmentModel.stabilityCostMonths)
        return base * (1 + 0.5 * Double(max(0, s))) * max(0.3, 1 + world.government.modifier(c, .stabilityCost))
    }

    public static func lawChangeCost(_ world: World, _ c: CountryID) -> Double {
        max(10, world.countries.lastMonthlyIncome[c.index] * GovernmentModel.lawChangeCostMonths)
    }

    public static func monthlyReformProgress(_ world: World, _ c: CountryID) -> Double {
        max(0, GovernmentModel.baseReformProgress
            + Double(world.government.stability[c.index]) * GovernmentModel.stabilityReform
            + world.government.modifier(c, .reformProgress))
    }

    /// The next reform tier this country can take, if any.
    public static func nextTier(_ world: World, _ c: CountryID) -> (index: Int, tier: ReformTier)? {
        guard let tree = world.government.rules.reforms[world.countries.government[c.index]] else { return nil }
        let t = world.government.reforms[c.index].count
        return t < tree.count ? (t, tree[t]) : nil
    }

    // MARK: Actions

    public static func changeStability(_ world: inout World, _ c: CountryID, by delta: Int) {
        let s = world.government.stability[c.index] + delta
        world.government.stability[c.index] = max(GovernmentModel.minStability, min(GovernmentModel.maxStability, s))
    }

    @discardableResult
    public static func raiseStability(_ world: inout World, _ c: CountryID) -> Bool {
        let cost = stabilityCost(world, c)
        guard world.government.stability[c.index] < GovernmentModel.maxStability,
              world.countries.treasury[c.index] >= cost else { return false }
        world.countries.treasury[c.index] -= cost
        changeStability(&world, c, by: 1)
        refreshEffects(&world, c)
        return true
    }

    public enum LawRefusal: Equatable, Sendable {
        case notAllowed, alreadyInForce, alreadyChanging, cannotAfford

        public var reason: String {
            switch self {
            case .notAllowed: return "Not possible under this government"
            case .alreadyInForce: return "Already the law"
            case .alreadyChanging: return "This law is already being changed"
            case .cannotAfford: return "Not enough money"
            }
        }
    }

    public static func lawRefusal(_ world: World, _ c: CountryID, area: Int, option: Int) -> LawRefusal? {
        let g = world.government
        let opt = g.rules.lawAreas[area].options[option]
        if !opt.allowed(for: world.countries.government[c.index]) { return .notAllowed }
        if g.laws[c.index][area] == option { return .alreadyInForce }
        if g.pending[c.index].contains(where: { $0.area == area }) { return .alreadyChanging }
        if world.countries.treasury[c.index] < lawChangeCost(world, c) { return .cannotAfford }
        return nil
    }

    /// Starts changing a law; it takes effect after six months.
    @discardableResult
    public static func changeLaw(_ world: inout World, _ c: CountryID, area: Int, option: Int, date: GameDate) -> LawRefusal? {
        if let r = lawRefusal(world, c, area: area, option: option) { return r }
        world.countries.treasury[c.index] -= lawChangeCost(world, c)
        world.government.pending[c.index].append(PendingLaw(area: area, option: option, monthsLeft: GovernmentModel.lawChangeMonths))
        let rules = world.government.rules
        world.people.record(date, c, "Work begins on a new law: \(rules.lawAreas[area].options[option].name).")
        return nil
    }

    static func enact(_ world: inout World, _ c: CountryID, _ law: PendingLaw, date: GameDate) {
        let rules = world.government.rules
        guard rules.lawAreas[law.area].options[law.option].allowed(for: world.countries.government[c.index]) else { return }
        world.government.laws[c.index][law.area] = law.option
        if law.area == rules.successionArea,
           let s = SuccessionLaw(rawValue: rules.lawAreas[law.area].options[law.option].key) {
            world.countries.succession[c.index] = s
            world.countries.heir[c.index] = CharacterSystem.heir(world, c, date: date)
            changeStability(&world, c, by: -1)
        }
        world.people.record(date, c, "New law in force: \(rules.lawAreas[law.area].options[law.option].name).")
    }

    @discardableResult
    public static func grantPrivilege(_ world: inout World, _ c: CountryID, _ p: Int, date: GameDate) -> Bool {
        let def = world.government.rules.privileges[p]
        guard world.government.has(c, estate: def.estate), !world.government.privileges[c.index].contains(p) else { return false }
        let gold = world.countries.lastMonthlyIncome[c.index] * def.gold
        guard world.countries.treasury[c.index] + gold >= 0 else { return false }
        world.countries.treasury[c.index] += gold
        world.government.privileges[c.index].insert(p)
        world.people.record(date, c, "\(world.government.rules.estates[def.estate.index].name) granted: \(def.name).")
        refreshEffects(&world, c)
        return true
    }

    @discardableResult
    public static func revokePrivilege(_ world: inout World, _ c: CountryID, _ p: Int, date: GameDate) -> Bool {
        guard world.government.privileges[c.index].contains(p) else { return false }
        let def = world.government.rules.privileges[p]
        world.government.privileges[c.index].remove(p)
        world.government.grudge[c.index][def.estate.index] += def.loyalty * GovernmentModel.revokeGrudge
        changeStability(&world, c, by: -1)
        world.people.record(date, c, "\(world.government.rules.estates[def.estate.index].name) lose: \(def.name).")
        refreshEffects(&world, c)
        return true
    }

    /// Takes the next reform tier with this option (progress permitting).
    @discardableResult
    public static func adoptReform(_ world: inout World, _ c: CountryID, option: Int, date: GameDate) -> Bool {
        guard let next = nextTier(world, c), option < next.tier.options.count,
              world.government.reformProgress[c.index] >= next.tier.cost else { return false }
        let tier = next.tier
        world.government.reformProgress[c.index] -= tier.cost
        let reform = tier.options[option]
        world.government.reforms[c.index].append(option)
        world.people.record(date, c, "Government reform: \(reform.name).")
        if let g = reform.becomes, g != world.countries.government[c.index] {
            world.countries.government[c.index] = g
            world.government.reforms[c.index] = [0]
            // Laws the new government does not allow fall back to their first allowed option.
            let rules = world.government.rules
            for (a, area) in rules.lawAreas.enumerated() where !area.options[world.government.laws[c.index][a]].allowed(for: g) {
                if a == rules.successionArea {
                    let law = CharacterSystem.defaultLaw(g)
                    world.countries.succession[c.index] = law
                    world.government.laws[c.index][a] = area.options.firstIndex { $0.key == law.rawValue } ?? 0
                } else {
                    world.government.laws[c.index][a] = area.options.firstIndex { $0.allowed(for: g) } ?? 0
                }
            }
            world.government.pending[c.index].removeAll { !rules.lawAreas[$0.area].options[$0.option].allowed(for: g) }
            world.people.record(date, c, "\(world.countries.name[c.index]) becomes a \(g.displayName.lowercased()).")
        }
        refreshEffects(&world, c)
        return true
    }

    // MARK: Monthly

    public static func runMonthly(_ world: inout World, date: GameDate, random: inout GameRandom) {
        guard world.government.count == world.countries.count else { return }
        var owned = Array(repeating: [ProvinceID](), count: world.countries.count)
        for p in world.provinces.ids {
            if let o = world.provinces.owner[p.index] { owned[o.index].append(p) }
        }
        for c in world.countries.ids where !owned[c.index].isEmpty {
            let i = c.index
            // Laws being enacted.
            var still: [PendingLaw] = []
            for var law in world.government.pending[i] {
                law.monthsLeft -= 1
                if law.monthsLeft <= 0 { enact(&world, c, law, date: date) } else { still.append(law) }
            }
            world.government.pending[i] = still

            refreshPower(&world, c, owned: owned[i])
            for e in world.government.estates[i] {
                let target = loyaltyTarget(world, c, e)
                world.government.loyalty[i][e.index] += GovernmentModel.loyaltySpeed * (target - world.government.loyalty[i][e.index])
            }
            for e in world.government.grudge[i].indices {
                world.government.grudge[i][e] *= GovernmentModel.grudgeFade
            }
            world.government.reformProgress[i] += monthlyReformProgress(world, c)

            // A strong, disloyal estate takes what it wants.
            for e in world.government.estates[i]
            where world.government.power[i][e.index] >= GovernmentModel.seizePower
                && world.government.loyalty[i][e.index] < GovernmentModel.seizeLoyalty {
                guard random.unit() < GovernmentModel.seizeChance else { continue }
                let options = world.government.rules.privileges(of: e).filter { !world.government.privileges[i].contains($0) }
                if let p = options.max(by: { world.government.rules.privileges[$0].power < world.government.rules.privileges[$1].power }) {
                    world.government.privileges[i].insert(p)
                    changeStability(&world, c, by: -1)
                    let def = world.government.rules.privileges[p]
                    world.people.record(date, c, "\(world.government.rules.estates[e.index].name) seize power and take: \(def.name).")
                }
            }
            refreshEffects(&world, c)
            if !world.humanCountries.contains(c) {
                runAI(&world, c, date: date)
            }
        }
    }

    /// Computer countries: take reforms, keep stability up, soothe angry estates.
    static func runAI(_ world: inout World, _ c: CountryID, date: GameDate) {
        let i = c.index
        if let next = nextTier(world, c), world.government.reformProgress[i] >= next.tier.cost {
            let t = next.index, tier = next.tier
            // Keep the government type unless tribal (they settle down).
            let keep = world.countries.government[i] == .tribal ? tier.options.indices.map { $0 }
                : tier.options.indices.filter { tier.options[$0].becomes == nil }
            if !keep.isEmpty {
                adoptReform(&world, c, option: keep[(i + t) % keep.count], date: date)
            }
        }
        if world.government.stability[i] < 1 && stabilityCost(world, c) < world.countries.treasury[i] * 0.3 {
            raiseStability(&world, c)
        }
        if date.month == 1 {
            for e in world.government.estates[i]
            where world.government.loyalty[i][e.index] < 35 && world.government.power[i][e.index] > 0.2 {
                let options = world.government.rules.privileges(of: e).filter { !world.government.privileges[i].contains($0) }
                if let p = options.first, grantPrivilege(&world, c, p, date: date) { break }
            }
        }
    }
}

extension World {
    /// Contentment change from government: laws, privileges, stability, tolerance.
    public func governmentMood(_ country: CountryID, _ cls: SocialClass, _ religion: Religion) -> Double {
        guard country.index < government.count else { return 0 }
        var m = Double(government.stability[country.index]) * GovernmentModel.stabilityMood
        switch cls {
        case .nobles: m += government.modifier(country, .moodNobles)
        case .clergy: m += government.modifier(country, .moodClergy)
        case .burghers: m += government.modifier(country, .moodBurghers)
        case .peasants: m += government.modifier(country, .moodPeasants)
        case .slaves: break
        }
        if religion != countries.religion[country.index] { m += government.modifier(country, .moodOtherFaith) }
        return m
    }
}
