/// Goods, workshop recipes, what each class needs, and who produces what.
/// Data comes from `Resources/economy1453.json` (built by
/// `tools/economy/econgen.py` from `data/economy/`).

public struct GoodID: Hashable, Sendable, Codable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

public enum GoodCategory: String, CaseIterable, Sendable {
    case food, luxury, material, animal, manufactured

    public var displayName: String {
        switch self {
        case .food: return "Food"
        case .luxury: return "Luxuries"
        case .material: return "Materials"
        case .animal: return "Animals"
        case .manufactured: return "Manufactured"
        }
    }
}

public struct GoodTable: Sendable {
    public private(set) var key: [String] = []
    public private(set) var name: [String] = []
    public private(set) var category: [GoodCategory] = []
    /// Normal price in ducats per unit.
    public private(set) var basePrice: [Double] = []
    public private(set) var color: [RGB] = []
    /// Units per 1,000 workers per year, for trade goods dug, grown or herded.
    public private(set) var yield: [Double] = []
    /// Extra goods produced alongside this one (units per unit).
    public private(set) var byproducts: [[(GoodID, Double)]] = []
    private var indexByKey: [String: GoodID] = [:]

    public init() {}

    public var count: Int { key.count }
    public var ids: [GoodID] { (0..<count).map(GoodID.init) }

    public func id(forKey key: String) -> GoodID? { indexByKey[key] }

    @discardableResult
    public mutating func add(key: String, name: String, category: GoodCategory, basePrice: Double,
                             color: RGB, yield: Double, byproducts: [(GoodID, Double)] = []) -> GoodID {
        let id = GoodID(count)
        self.key.append(key)
        self.name.append(name)
        self.category.append(category)
        self.basePrice.append(basePrice)
        self.color.append(color)
        self.yield.append(yield)
        self.byproducts.append(byproducts)
        indexByKey[key] = id
        return id
    }
}

/// A workshop turns inputs into one good. The first input is essential;
/// the others only slow the workshop down when they are short.
public struct Recipe: Sendable {
    public var output: GoodID
    /// Units made per 1,000 workers per year.
    public var perThousand: Double
    /// Units of each input per unit of output.
    public var inputs: [(GoodID, Double)]

    public init(output: GoodID, perThousand: Double, inputs: [(GoodID, Double)]) {
        self.output = output
        self.perThousand = perThousand
        self.inputs = inputs
    }
}

/// Something a class buys every year, satisfied by any of several goods.
public struct NeedGroup: Sendable {
    public var socialClass: SocialClass
    public var name: String
    /// Units per 1,000 people per year.
    public var amount: Double
    public var goods: [GoodID]
    /// Only people of this religion family have the need.
    public var onlyFamily: ReligionFamily?
    /// People of this religion family don't have the need.
    public var notFamily: ReligionFamily?

    public init(socialClass: SocialClass, name: String, amount: Double, goods: [GoodID],
                onlyFamily: ReligionFamily? = nil, notFamily: ReligionFamily? = nil) {
        self.socialClass = socialClass
        self.name = name
        self.amount = amount
        self.goods = goods
        self.onlyFamily = onlyFamily
        self.notFamily = notFamily
    }

    public func applies(to family: ReligionFamily) -> Bool {
        if let only = onlyFamily, only != family { return false }
        if let not = notFamily, not == family { return false }
        return true
    }
}

public enum ProducerKind: String, Sendable {
    /// Farms, mines, herds, fisheries: worked by peasants and slaves.
    case raw
    /// Workshops: worked by burghers, use inputs from the market.
    case craft
}

/// Everything that produces goods, grouped by province (like pops).
/// A later phase turns workshops into buildings with levels and costs.
public struct ProducerTable: Sendable {
    public private(set) var province: [ProvinceID] = []
    public private(set) var good: [GoodID] = []
    public private(set) var kind: [ProducerKind] = []
    /// Index into `Economy.recipes` for workshops, -1 otherwise.
    public private(set) var recipe: [Int] = []
    /// Share of the province's workers of the right class.
    public var share: [Double] = []
    /// The province's staple food (yield depends on terrain).
    public private(set) var isStaple: [Bool] = []
    /// Units made last month.
    public var output: [Double] = []
    /// Ducats earned last month (after paying for inputs).
    public var value: [Double] = []
    private var ranges: [Range<Int>] = []

    public init() {}

    public var count: Int { good.count }

    public func range(for p: ProvinceID) -> Range<Int> {
        p.index < ranges.count ? ranges[p.index] : 0..<0
    }

    public mutating func beginProvince(_ p: ProvinceID) {
        precondition(p.index == ranges.count, "producers must be added in province order")
        ranges.append(count..<count)
    }

    public mutating func add(good: GoodID, kind: ProducerKind, recipe: Int, share: Double, isStaple: Bool) {
        precondition(!ranges.isEmpty, "call beginProvince first")
        province.append(ProvinceID(ranges.count - 1))
        self.good.append(good)
        self.kind.append(kind)
        self.recipe.append(recipe)
        self.share.append(share)
        self.isStaple.append(isStaple)
        output.append(0)
        value.append(0)
        let r = ranges[ranges.count - 1]
        ranges[ranges.count - 1] = r.lowerBound..<(r.upperBound + 1)
    }
}
