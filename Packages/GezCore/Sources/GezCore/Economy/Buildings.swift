/// Buildings: levels 1–5 in a province, built over months for ducats plus
/// goods bought from the market. Data in `data/economy/buildings.txt`.

public struct BuildingTypeID: Hashable, Sendable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

public enum BuildingCategory: String, CaseIterable, Sendable {
    case production, trade, religion, military

    public var displayName: String {
        switch self {
        case .production: return "Production"
        case .trade: return "Trade and towns"
        case .religion: return "Religion and learning"
        case .military: return "Military"
        }
    }
}

public enum BuildingEffect: Sendable, Equatable {
    /// Staple food output +x per level.
    case staple(Double)
    /// Trade-good output +x per level.
    case trade(Double)
    /// Fish output +x per level.
    case fish(Double)
    /// Burgher jobs making the recipe's good (index into `Economy.recipes`).
    case workshop(recipe: Int)
    /// All workshop output +x per level.
    case crafts(Double)
    /// Tax from the province +x per level.
    case tax(Double)
    /// Satisfaction of everyone in the province +x per level.
    case mood(Double)
    /// Learning points per level per year.
    case learning(Double)
    /// Fort level +1 per level.
    case fort
    /// Thousand soldiers per level (armies, Phase 6).
    case manpower(Double)
    /// Ships buildable at once per level (navies, Phase 10).
    case ships(Double)
    /// Trade capacity of land links through this market town +x per level.
    case routes(Double)
}

public struct BuildingType: Sendable {
    public var key: String
    public var name: String
    public var category: BuildingCategory
    /// Ducats for level 1; each later level costs 50% more.
    public var cost: Double
    /// Months for level 1; each later level takes 25% longer.
    public var months: Int
    /// Goods bought from the market for each level.
    public var materials: [(GoodID, Double)]
    public var effect: BuildingEffect
    public var requiresCoast: Bool
    /// The province's trade good must be one of these.
    public var requiresGoods: [GoodID]
    public var requiresTerrain: [Terrain]
    public var requiresFamily: ReligionFamily?

    public init(key: String, name: String, category: BuildingCategory, cost: Double, months: Int,
                materials: [(GoodID, Double)], effect: BuildingEffect, requiresCoast: Bool = false,
                requiresGoods: [GoodID] = [], requiresTerrain: [Terrain] = [], requiresFamily: ReligionFamily? = nil) {
        self.key = key
        self.name = name
        self.category = category
        self.cost = cost
        self.months = months
        self.materials = materials
        self.effect = effect
        self.requiresCoast = requiresCoast
        self.requiresGoods = requiresGoods
        self.requiresTerrain = requiresTerrain
        self.requiresFamily = requiresFamily
    }

    public static let maxLevel = 5

    /// Ducats (without materials) to build the given level.
    public func ducats(forLevel level: Int) -> Double {
        cost * (1 + 0.5 * Double(max(level, 1) - 1))
    }

    public func months(forLevel level: Int) -> Int {
        Int((Double(months) * (1 + 0.25 * Double(max(level, 1) - 1))).rounded())
    }
}

/// Something being built.
public struct Construction: Sendable, Equatable {
    public var province: ProvinceID
    public var type: BuildingTypeID
    /// The level it will have when finished.
    public var level: Int
    public var monthsLeft: Int
    public var totalMonths: Int

    public var progress: Double {
        totalMonths > 0 ? 1 - Double(monthsLeft) / Double(totalMonths) : 1
    }
}

/// Building levels for every province, stored flat: `[province * typeCount + type]`.
public struct BuildingTable: Sendable {
    public private(set) var typeCount = 0
    public var level: [Int] = []
    public var constructions: [Construction] = []

    public init() {}

    public mutating func setup(provinces: Int, types: Int) {
        typeCount = types
        level = Array(repeating: 0, count: provinces * types)
        constructions = []
    }

    @inline(__always)
    public func level(_ p: ProvinceID, _ t: BuildingTypeID) -> Int {
        level[p.index * typeCount + t.index]
    }

    public mutating func setLevel(_ p: ProvinceID, _ t: BuildingTypeID, _ value: Int) {
        level[p.index * typeCount + t.index] = value
    }

    /// Slots used: every level counts, including levels being built.
    public func slotsUsed(_ p: ProvinceID) -> Int {
        var used = 0
        for t in 0..<typeCount { used += level[p.index * typeCount + t] }
        used += constructions.filter { $0.province == p }.count
        return used
    }

    public func construction(_ p: ProvinceID, _ t: BuildingTypeID) -> Construction? {
        constructions.first { $0.province == p && $0.type == t }
    }
}

/// Per-province totals of building effects, worked out once a month.
public struct BuildingBonuses: Sendable {
    public var staple: [Double]
    public var trade: [Double]
    public var fish: [Double]
    public var crafts: [Double]
    public var tax: [Double]
    public var mood: [Double]
    public var learning: [Double]

    public init(_ eco: Economy, provinces: Int) {
        staple = Array(repeating: 0, count: provinces)
        trade = staple; fish = staple; crafts = staple; tax = staple; mood = staple; learning = staple
        let T = eco.buildings.typeCount
        for p in 0..<provinces {
            for t in 0..<T {
                let l = Double(eco.buildings.level[p * T + t])
                guard l > 0 else { continue }
                switch eco.buildingTypes[t].effect {
                case .staple(let x): staple[p] += x * l
                case .trade(let x): trade[p] += x * l
                case .fish(let x): fish[p] += x * l
                case .crafts(let x): crafts[p] += x * l
                case .tax(let x): tax[p] += x * l
                case .mood(let x): mood[p] += x * l
                case .learning(let x): learning[p] += x * l
                case .workshop, .fort, .manpower, .ships, .routes: break
                }
            }
        }
    }
}

extension BuildingEffect {
    /// The recipe a workshop building works, if it is one.
    public var workshopRecipe: Int? {
        if case .workshop(let r) = self { return r }
        return nil
    }
}
