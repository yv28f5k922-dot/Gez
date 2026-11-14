/// Province data stored as a struct of arrays: one array per field, indexed
/// by `ProvinceID.index`. Systems that loop over thousands of provinces each
/// tick only touch the arrays they need, which keeps memory access fast.
public struct ProvinceTable: Sendable {
    // Fixed geography (never changes during a game).
    public private(set) var name: [String] = []
    public private(set) var location: [GeoPoint] = []
    public private(set) var state: [StateID] = []
    public private(set) var terrain: [Terrain] = []
    public private(set) var isCoastal: [Bool] = []
    public private(set) var areaKm2: [Double] = []
    /// Best spot on the map image to draw the province name.
    public private(set) var labelPoint: [MapPoint] = []
    /// Provinces an army can walk to directly (land borders plus straits).
    public private(set) var neighbors: [[ProvinceID]] = []

    // Changing state.
    public var owner: [CountryID?] = []
    /// 1 (empty) to 10 (great city).
    public var development: [Int] = []
    /// Number of people.
    public var population: [Double] = []
    /// Yearly tax value in ducats.
    public var baseTax: [Double] = []
    /// Yearly production value in ducats.
    public var production: [Double] = []
    /// Majority religion of the people (kept up to date from the pops).
    public var religion: [Religion] = []
    /// Majority culture of the people (kept up to date from the pops).
    public var majorityCulture: [CultureID] = []
    /// Sufi brotherhoods active in the province.
    public var sufiOrders: [[SufiPresence]] = []
    /// 0 = no fort. Higher levels take longer to siege.
    public var fortLevel: [Int] = []
    /// The great vassal who holds this province for its owner (nil = the crown's own land).
    public var holder: [CharacterID?] = []

    public init() {}

    public var count: Int { name.count }
    public var ids: [ProvinceID] { (0..<count).map(ProvinceID.init) }

    @discardableResult
    public mutating func add(
        name: String,
        location: GeoPoint,
        state: StateID,
        terrain: Terrain,
        isCoastal: Bool = false,
        areaKm2: Double = 0,
        labelPoint: MapPoint = MapPoint(x: 0, y: 0),
        owner: CountryID?,
        development: Int,
        population: Double,
        baseTax: Double,
        production: Double,
        religion: Religion,
        fortLevel: Int
    ) -> ProvinceID {
        let id = ProvinceID(count)
        self.name.append(name)
        self.location.append(location)
        self.state.append(state)
        self.terrain.append(terrain)
        self.isCoastal.append(isCoastal)
        self.areaKm2.append(areaKm2)
        self.labelPoint.append(labelPoint)
        self.neighbors.append([])
        self.owner.append(owner)
        self.development.append(development)
        self.population.append(population)
        self.baseTax.append(baseTax)
        self.production.append(production)
        self.religion.append(religion)
        self.majorityCulture.append(CultureID(0))
        self.sufiOrders.append([])
        self.fortLevel.append(fortLevel)
        self.holder.append(nil)
        return id
    }

    /// Neighbours are set once all provinces exist. Links are made two-way.
    public mutating func connect(_ a: ProvinceID, _ b: ProvinceID) {
        guard a != b else { return }
        if !neighbors[a.index].contains(b) { neighbors[a.index].append(b) }
        if !neighbors[b.index].contains(a) { neighbors[b.index].append(a) }
    }

    public func id(named name: String) -> ProvinceID? {
        self.name.firstIndex(of: name).map(ProvinceID.init)
    }
}

/// A state is a named group of neighbouring provinces (e.g. "Thrace").
/// A region groups states (e.g. "Balkans").
public struct StateTable: Sendable {
    public private(set) var name: [String] = []
    public private(set) var region: [RegionID] = []
    public private(set) var provinces: [[ProvinceID]] = []

    public init() {}

    public var count: Int { name.count }

    @discardableResult
    public mutating func add(name: String, region: RegionID) -> StateID {
        let id = StateID(count)
        self.name.append(name)
        self.region.append(region)
        self.provinces.append([])
        return id
    }

    mutating func attach(_ province: ProvinceID, to state: StateID) {
        provinces[state.index].append(province)
    }
}

/// Named areas of sea (Aegean, Malabar Coast...). Fleets, trade and plague
/// travel through them.
public struct SeaZoneTable: Sendable {
    public private(set) var name: [String] = []
    /// Sea zones you can sail to directly.
    public var neighbors: [[SeaZoneID]] = []
    /// Land provinces touching this sea.
    public var coast: [[ProvinceID]] = []

    public init() {}

    public var count: Int { name.count }

    @discardableResult
    public mutating func add(name: String) -> SeaZoneID {
        let id = SeaZoneID(count)
        self.name.append(name)
        neighbors.append([])
        coast.append([])
        return id
    }

    public func id(named name: String) -> SeaZoneID? {
        self.name.firstIndex(of: name).map(SeaZoneID.init)
    }
}

public struct CountryTable: Sendable {
    public private(set) var tag: [String] = []
    public private(set) var name: [String] = []
    public var color: [RGB] = []
    public var government: [GovernmentType] = []
    public var religion: [Religion] = []
    public var capital: [ProvinceID?] = []
    /// Share of the population that is enslaved (0 to 1).
    public var slavery: [Double] = []
    /// The country this one is subject to, if any.
    public var overlord: [CountryID?] = []
    public var subjectType: [SubjectType?] = []
    /// Ducats.
    public var treasury: [Double] = []
    /// Income from the most recent monthly update.
    public var lastMonthlyIncome: [Double] = []
    /// Spending (building upkeep, later armies and loans) in the most recent month.
    public var lastMonthlyExpenses: [Double] = []
    /// Learning points gathered so far (spent on technology later).
    public var learning: [Double] = []
    /// Tax level per class (`TaxClass` order): 1 normal, 0 none, up to 2.
    public var taxLevel: [[Double]] = []
    /// Tax collected last month per class (`TaxClass` order).
    public var lastTax: [[Double]] = []
    public var lastUpkeep: [Double] = []
    public var lastInterest: [Double] = []
    /// 0 = none; 0.1 = everything the state buys costs 10% more.
    public var inflation: [Double] = []
    /// Debasing the coinage every month.
    public var debasing: [Bool] = []
    /// Months of bankruptcy penalties left.
    public var bankruptMonthsLeft: [Int] = []
    /// Countries whose merchants may not trade in or pass through this one's markets.
    public var embargoes: [Set<CountryID>] = []
    public var tollPolicy: [TollPolicy] = []
    public var ruler: [CharacterID?] = []
    public var heir: [CharacterID?] = []
    /// Council seats (`CouncilSeat` order).
    public var council: [[CharacterID?]] = []
    public var succession: [SuccessionLaw] = []
    /// Merchants' profit and tolls collected last month.
    public var lastTrade: [Double] = []
    public var lastTolls: [Double] = []
    /// Tax kept (or withheld) by vassals last month.
    public var lastVassalTax: [Double] = []

    private var indexByTag: [String: CountryID] = [:]

    public init() {}

    public var count: Int { tag.count }
    public var ids: [CountryID] { (0..<count).map(CountryID.init) }

    public func id(forTag tag: String) -> CountryID? {
        indexByTag[tag]
    }

    /// Countries directly subject to this one.
    public func subjects(of country: CountryID) -> [CountryID] {
        ids.filter { overlord[$0.index] == country }
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
        self.slavery.append(0)
        self.overlord.append(nil)
        self.subjectType.append(nil)
        self.treasury.append(treasury)
        self.lastMonthlyIncome.append(0)
        self.lastMonthlyExpenses.append(0)
        self.learning.append(0)
        self.taxLevel.append(Array(repeating: 1, count: TaxClass.allCases.count))
        self.lastTax.append(Array(repeating: 0, count: TaxClass.allCases.count))
        self.lastUpkeep.append(0)
        self.lastInterest.append(0)
        self.inflation.append(0)
        self.debasing.append(false)
        self.bankruptMonthsLeft.append(0)
        self.embargoes.append([])
        self.ruler.append(nil)
        self.heir.append(nil)
        self.council.append(Array(repeating: nil, count: CouncilSeat.allCases.count))
        self.succession.append(.primogeniture)
        self.tollPolicy.append(.open)
        self.lastTrade.append(0)
        self.lastTolls.append(0)
        self.lastVassalTax.append(0)
        indexByTag[tag] = id
        return id
    }
}

public struct World: Sendable {
    public var map: MapInfo
    public var regions: [String] = []
    public var states = StateTable()
    public var provinces = ProvinceTable()
    public var countries = CountryTable()
    public var cultures = CultureTable()
    public var seaZones = SeaZoneTable()
    /// Sea zones touching each province (empty for inland provinces).
    public var provinceSeas: [[SeaZoneID]] = []
    /// Every group of people, split by culture, religion, sect and class.
    public var pops = PopTable()
    /// Major rivers, for drawing.
    public var rivers: [MapPolyline] = []
    /// Neighbouring provinces whose shared border is mostly a river.
    /// Crossing these is slower and gives the defender an edge in battle.
    public var riverBorders: Set<ProvincePair> = []
    /// Goods, markets, producers and prices.
    public var economy = Economy()
    /// Banks and loans.
    public var finance = Finance()
    /// Rulers, families and courts.
    public var people = People()
    /// Countries played by people; the AI leaves them alone.
    public var humanCountries: Set<CountryID> = []
    /// Laws, estates, stability and reforms (Phase 5).
    public var government = Government()
    /// Armies, regiments, unit types and national manpower (Phase 6).
    public var military = Military()
    /// Diplomatic relations, treaties, opinions, and wars (Phase 7).
    public var diplomacy = Diplomacy()

    public init(map: MapInfo = MapInfo(width: 1, height: 1, pixelsPerDegree: 1, longitudeMin: 0, latitudeMax: 0)) {
        self.map = map
    }

    public func provinces(ownedBy country: CountryID) -> [ProvinceID] {
        provinces.ids.filter { provinces.owner[$0.index] == country }
    }

    public func isRiverBorder(_ a: ProvinceID, _ b: ProvinceID) -> Bool {
        riverBorders.contains(ProvincePair(a, b))
    }

    public func stateName(of province: ProvinceID) -> String {
        states.name[provinces.state[province.index].index]
    }

    public func regionName(of province: ProvinceID) -> String {
        regions[states.region[provinces.state[province.index].index].index]
    }

    /// Adds a province and records it in its state's province list.
    @discardableResult
    public mutating func addProvince(
        name: String,
        location: GeoPoint,
        state: StateID,
        terrain: Terrain,
        isCoastal: Bool = false,
        areaKm2: Double = 0,
        labelPoint: MapPoint = MapPoint(x: 0, y: 0),
        owner: CountryID?,
        development: Int,
        population: Double,
        baseTax: Double,
        production: Double,
        religion: Religion,
        fortLevel: Int
    ) -> ProvinceID {
        let id = provinces.add(
            name: name, location: location, state: state, terrain: terrain,
            isCoastal: isCoastal, areaKm2: areaKm2, labelPoint: labelPoint,
            owner: owner, development: development, population: population,
            baseTax: baseTax, production: production, religion: religion,
            fortLevel: fortLevel
        )
        states.attach(id, to: state)
        return id
    }
}
