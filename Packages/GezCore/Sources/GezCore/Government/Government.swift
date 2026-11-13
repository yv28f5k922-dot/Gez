/// Government, laws, estates and reforms (Phase 5). The rules come from
/// `Resources/government1453.json` (built by `tools/government/govgen.py`
/// from `data/government/`).

/// Every number a law, privilege, reform or estate mood can change.
public enum Modifier: Int, CaseIterable, Sendable {
    case tax, trade, buildCost, interest, learning, reformProgress, stabilityCost
    case vassalKeep, vassalOpinion, crownPower
    case moodNobles, moodClergy, moodBurghers, moodPeasants, moodOtherFaith
    case taxNobles, taxClergy, taxBurghers, taxPeasants
    case inflationDecay, noDebase, manpower, levySize, armyQuality, fortDefence

    /// Key used in the data files.
    public var key: String {
        switch self {
        case .tax: return "tax"
        case .trade: return "trade"
        case .buildCost: return "build_cost"
        case .interest: return "interest"
        case .learning: return "learning"
        case .reformProgress: return "reform_progress"
        case .stabilityCost: return "stability_cost"
        case .vassalKeep: return "vassal_keep"
        case .vassalOpinion: return "vassal_opinion"
        case .crownPower: return "crown_power"
        case .moodNobles: return "mood_nobles"
        case .moodClergy: return "mood_clergy"
        case .moodBurghers: return "mood_burghers"
        case .moodPeasants: return "mood_peasants"
        case .moodOtherFaith: return "mood_other_faith"
        case .taxNobles: return "tax_nobles"
        case .taxClergy: return "tax_clergy"
        case .taxBurghers: return "tax_burghers"
        case .taxPeasants: return "tax_peasants"
        case .inflationDecay: return "inflation_decay"
        case .noDebase: return "no_debase"
        case .manpower: return "manpower"
        case .levySize: return "levy_size"
        case .armyQuality: return "army_quality"
        case .fortDefence: return "fort_defence"
        }
    }

    public init?(key: String) {
        guard let m = Modifier.allCases.first(where: { $0.key == key }) else { return nil }
        self = m
    }

    /// Plain-language label for the interface.
    public var displayName: String {
        switch self {
        case .tax: return "Tax income"
        case .trade: return "Merchant profit"
        case .buildCost: return "Building cost"
        case .interest: return "Loan interest"
        case .learning: return "Learning"
        case .reformProgress: return "Reform progress / month"
        case .stabilityCost: return "Cost to raise stability"
        case .vassalKeep: return "Tax kept by vassals"
        case .vassalOpinion: return "Vassal opinion"
        case .crownPower: return "Crown power"
        case .moodNobles: return "Nobles' contentment"
        case .moodClergy: return "Clergy's contentment"
        case .moodBurghers: return "Burghers' contentment"
        case .moodPeasants: return "Peasants' contentment"
        case .moodOtherFaith: return "Other faiths' contentment"
        case .taxNobles: return "Tax on nobles"
        case .taxClergy: return "Tax on clergy"
        case .taxBurghers: return "Tax on burghers"
        case .taxPeasants: return "Tax on peasants"
        case .inflationDecay: return "Inflation falls / month"
        case .noDebase: return "Debasement forbidden"
        case .manpower: return "Manpower (Phase 6)"
        case .levySize: return "Levy size (Phase 6)"
        case .armyQuality: return "Army quality (Phase 6)"
        case .fortDefence: return "Fort defence (Phase 6)"
        }
    }

    /// Shown as plain points rather than percentages.
    public var isPoints: Bool { self == .vassalOpinion || self == .reformProgress || self == .noDebase }

    /// Contentment changes on the 0–1 scale are shown as points out of 100.
    public var isMood: Bool { [.moodNobles, .moodClergy, .moodBurghers, .moodPeasants, .moodOtherFaith].contains(self) }

    /// True when a higher number is bad for the realm.
    public var lowerIsBetter: Bool { [.buildCost, .interest, .stabilityCost, .vassalKeep].contains(self) }
}

public struct EstateID: Hashable, Sendable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

/// A bundle of changes: modifiers plus estate loyalty and power.
public struct Effects: Sendable, Equatable {
    public var values: [Double]
    public var loyalty: [Double]
    public var power: [Double]

    public init(estates: Int) {
        values = Array(repeating: 0, count: Modifier.allCases.count)
        loyalty = Array(repeating: 0, count: estates)
        power = Array(repeating: 0, count: estates)
    }

    public subscript(_ m: Modifier) -> Double {
        get { values[m.rawValue] }
        set { values[m.rawValue] = newValue }
    }

    public mutating func add(_ o: Effects, times k: Double = 1) {
        for i in values.indices { values[i] += o.values[i] * k }
        for i in loyalty.indices { loyalty[i] += o.loyalty[i] * k }
        for i in power.indices { power[i] += o.power[i] * k }
    }

    public var isEmpty: Bool {
        values.allSatisfy { $0 == 0 } && loyalty.allSatisfy { $0 == 0 } && power.allSatisfy { $0 == 0 }
    }
}

/// Where an estate's power comes from.
public enum EstateSource: Equatable, Sendable {
    /// Pops of this class (after regional estates took theirs).
    case socialClass(SocialClass)
    /// Non-Muslim pops of a Muslim realm.
    case dhimmi
    /// Hindu nobles of Rajput cultures.
    case rajput
    /// Nobles and peasants of tribal cultures.
    case tribes
    /// No pops: this share of the realm's total estate power.
    case fixed(Double)
}

public struct EstateDef: Sendable {
    public let key: String
    public let name: String
    public let source: EstateSource
    /// Raw power per thousand people (times their wealth).
    public let weight: Double
    public let loyal: Effects
    public let disloyal: Effects
}

public struct PrivilegeDef: Sendable {
    public let estate: EstateID
    public let key: String
    public let name: String
    public let loyalty: Double
    public let power: Double
    public let effects: Effects
    /// One-off ducats on granting, in months of income (negative = it costs).
    public let gold: Double
}

public struct LawOption: Sendable {
    public let key: String
    public let name: String
    public let effects: Effects
    /// Empty = allowed for every government.
    public let governments: [GovernmentType]

    public func allowed(for g: GovernmentType) -> Bool { governments.isEmpty || governments.contains(g) }
}

public struct LawArea: Sendable {
    public let key: String
    public let name: String
    public let options: [LawOption]
}

public struct ReformOption: Sendable {
    public let key: String
    public let name: String
    public let effects: Effects
    /// Switches the government type when adopted.
    public let becomes: GovernmentType?
}

public struct ReformTier: Sendable {
    public let cost: Double
    public let options: [ReformOption]
}

/// The fixed rules (same for every country).
public struct GovernmentRules: Sendable {
    public var estates: [EstateDef] = []
    public var privileges: [PrivilegeDef] = []
    public var lawAreas: [LawArea] = []
    public var reforms: [GovernmentType: [ReformTier]] = [:]
    public var tribalCultures: Set<CultureID> = []
    public var rajputCultures: Set<CultureID> = []

    public init() {}

    public func estate(forKey key: String) -> EstateID? {
        estates.firstIndex { $0.key == key }.map(EstateID.init)
    }

    public func lawArea(forKey key: String) -> Int? {
        lawAreas.firstIndex { $0.key == key }
    }

    public var successionArea: Int? { lawArea(forKey: "succession") }

    public func privileges(of e: EstateID) -> [Int] {
        privileges.indices.filter { privileges[$0].estate == e }
    }
}

/// A law being changed: it takes effect when `monthsLeft` reaches 0.
public struct PendingLaw: Equatable, Sendable {
    public let area: Int
    public let option: Int
    public var monthsLeft: Int
}

/// Per-country government state, struct of arrays by `CountryID.index`.
public struct Government: Sendable {
    public var rules = GovernmentRules()
    /// −3…+3.
    public var stability: [Int] = []
    /// Chosen option per law area.
    public var laws: [[Int]] = []
    public var pending: [[PendingLaw]] = []
    /// Chosen option per reform tier taken so far.
    public var reforms: [[Int]] = []
    public var reformProgress: [Double] = []
    /// Estates present in each country.
    public var estates: [[EstateID]] = []
    /// 0…100 per estate (all estates; unused ones stay 0).
    public var loyalty: [[Double]] = []
    /// Share of power 0…1 per estate.
    public var power: [[Double]] = []
    public var crownPower: [Double] = []
    /// Average contentment (0…1) of each estate's pops.
    public var contentment: [[Double]] = []
    /// Granted privileges (indices into `rules.privileges`).
    public var privileges: [Set<Int>] = []
    /// Lasting anger from revoked privileges per estate (fades).
    public var grudge: [[Double]] = []
    /// Sum of all effects, refreshed each month and after every change.
    public var effects: [Effects] = []

    public init() {}

    public var count: Int { stability.count }

    /// Makes room for every country (all with empty state).
    public mutating func resize(countries n: Int) {
        let e = rules.estates.count
        while stability.count < n {
            stability.append(0)
            laws.append(Array(repeating: 0, count: rules.lawAreas.count))
            pending.append([])
            reforms.append([])
            reformProgress.append(0)
            estates.append([])
            loyalty.append(Array(repeating: 50, count: e))
            power.append(Array(repeating: 0, count: e))
            crownPower.append(0)
            contentment.append(Array(repeating: 0.5, count: e))
            privileges.append([])
            grudge.append(Array(repeating: 0, count: e))
            effects.append(Effects(estates: e))
        }
    }

    public func modifier(_ c: CountryID, _ m: Modifier) -> Double {
        guard c.index < effects.count else { return 0 }
        return effects[c.index][m]
    }

    public func has(_ c: CountryID, estate e: EstateID) -> Bool {
        c.index < estates.count && estates[c.index].contains(e)
    }
}
