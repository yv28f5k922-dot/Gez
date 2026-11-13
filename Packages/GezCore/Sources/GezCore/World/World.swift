/// Province data stored as a struct of arrays: one array per field, indexed
/// by `ProvinceID.index`. Systems that loop over thousands of provinces each
/// tick only touch the arrays they need, which keeps memory access fast.
public struct ProvinceTable: Sendable {
    public private(set) var name: [String] = []
    public private(set) var location: [GeoPoint] = []
    public var owner: [CountryID?] = []
    /// Number of people.
    public var population: [Double] = []
    /// Yearly tax value in ducats.
    public var baseTax: [Double] = []
    /// Yearly production value in ducats.
    public var production: [Double] = []
    public var terrain: [Terrain] = []
    public var religion: [Religion] = []
    /// 0 = no fort. Higher levels take longer to siege.
    public var fortLevel: [Int] = []

    public init() {}

    public var count: Int { name.count }
    public var ids: [ProvinceID] { (0..<count).map(ProvinceID.init) }

    @discardableResult
    public mutating func add(
        name: String,
        location: GeoPoint,
        owner: CountryID?,
        population: Double,
        baseTax: Double,
        production: Double,
        terrain: Terrain,
        religion: Religion,
        fortLevel: Int
    ) -> ProvinceID {
        let id = ProvinceID(count)
        self.name.append(name)
        self.location.append(location)
        self.owner.append(owner)
        self.population.append(population)
        self.baseTax.append(baseTax)
        self.production.append(production)
        self.terrain.append(terrain)
        self.religion.append(religion)
        self.fortLevel.append(fortLevel)
        return id
    }
}

public struct CountryTable: Sendable {
    public private(set) var tag: [String] = []
    public private(set) var name: [String] = []
    public var color: [RGB] = []
    public var government: [GovernmentType] = []
    public var religion: [Religion] = []
    public var capital: [ProvinceID?] = []
    /// Ducats.
    public var treasury: [Double] = []
    /// Income from the most recent monthly update.
    public var lastMonthlyIncome: [Double] = []

    private var indexByTag: [String: CountryID] = [:]

    public init() {}

    public var count: Int { tag.count }
    public var ids: [CountryID] { (0..<count).map(CountryID.init) }

    public func id(forTag tag: String) -> CountryID? {
        indexByTag[tag]
    }

    @discardableResult
    public mutating func add(
        tag: String,
        name: String,
        color: RGB,
        government: GovernmentType,
        religion: Religion,
        treasury: Double
    ) -> CountryID {
        precondition(indexByTag[tag] == nil, "duplicate country tag \(tag)")
        let id = CountryID(count)
        self.tag.append(tag)
        self.name.append(name)
        self.color.append(color)
        self.government.append(government)
        self.religion.append(religion)
        self.capital.append(nil)
        self.treasury.append(treasury)
        self.lastMonthlyIncome.append(0)
        indexByTag[tag] = id
        return id
    }
}

public struct World: Sendable {
    public var provinces = ProvinceTable()
    public var countries = CountryTable()

    public init() {}

    public func provinces(ownedBy country: CountryID) -> [ProvinceID] {
        provinces.ids.filter { provinces.owner[$0.index] == country }
    }
}
