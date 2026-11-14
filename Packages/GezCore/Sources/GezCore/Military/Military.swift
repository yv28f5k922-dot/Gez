// Pure-Swift data models for Phase 6: unit types, regiments, struct-of-arrays
// army table, and per-country military state (national manpower and upkeep).

public struct UnitTypeID: Hashable, Sendable, Codable {
    public var rawValue: UInt8
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }
}

public struct ArmyID: Hashable, Sendable, Codable {
    public var rawValue: Int32
    public init(_ rawValue: Int32) { self.rawValue = rawValue }
}

public enum UnitCategory: String, Sendable, Codable, CaseIterable {
    case infantry
    case cavalry
    case ranged
    case artillery

    public var displayName: String {
        switch self {
        case .infantry:  return "Infantry"
        case .cavalry:   return "Cavalry"
        case .ranged:    return "Ranged"
        case .artillery: return "Artillery"
        }
    }
}

/// How a regiment was raised and how it is sustained.
public enum RegimentOrigin: String, Sendable, Codable, CaseIterable {
    /// Recruited from the national manpower pool using ducats and market goods;
    /// reinforces monthly in supplied friendly provinces.
    case professional
    /// Hired for gold alone without drawing on national manpower or local pops.
    case mercenary
    /// Mustered directly from a province's peasant, noble, or tribal pops;
    /// shrinks the local workforce while raised and returns survivors on disband.
    case levy

    public var displayName: String {
        switch self {
        case .professional: return "Professional"
        case .mercenary:    return "Mercenary"
        case .levy:         return "Levy"
        }
    }
}

/// A single unlock clause on a regional special unit. Multiple clauses on the
/// same `UnitType` are OR-ed: matching any clause allows recruitment.
public enum UnitUnlock: Sendable, Equatable {
    case estate([String])
    case government([GovernmentType])
    case culture([String])
    case region([String])
    case tags([String])
}

/// Static definition of a regiment type loaded from `military1453.json`.
public struct UnitType: Sendable {
    public var id: UnitTypeID
    public var key: String
    public var name: String
    public var category: UnitCategory
    public var maxMen: Int
    /// Relative march pace (1.0 = normal foot pace ~30 km/day on open plains).
    public var speed: Double
    public var attack: Double
    public var defence: Double
    public var morale: Double
    public var siege: Double
    /// Recruitment cost in ducats for a professional regiment.
    public var cost: Double
    /// Monthly upkeep in ducats at full strength for a professional regiment.
    public var upkeep: Double
    /// Market goods demanded in the recruiting province when raising a
    /// professional regiment.
    public var goods: [(GoodID, Double)]
    /// Empty means every country can recruit this unit; non-empty means any
    /// matching rule unlocks it.
    public var requires: [UnitUnlock]

    public init(
        id: UnitTypeID,
        key: String,
        name: String,
        category: UnitCategory,
        maxMen: Int,
        speed: Double,
        attack: Double,
        defence: Double,
        morale: Double,
        siege: Double,
        cost: Double,
        upkeep: Double,
        goods: [(GoodID, Double)],
        requires: [UnitUnlock]
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.category = category
        self.maxMen = maxMen
        self.speed = speed
        self.attack = attack
        self.defence = defence
        self.morale = morale
        self.siege = siege
        self.cost = cost
        self.upkeep = upkeep
        self.goods = goods
        self.requires = requires
    }
}

/// One regiment inside an army.
public struct Regiment: Sendable, Equatable, Codable {
    public var type: UnitTypeID
    public var origin: RegimentOrigin
    public var men: Int
    public var morale: Double
    /// For `.levy` regiments, the province whose pops supplied these men so
    /// survivors return to work when disbanded.
    public var homeProvince: ProvinceID?

    public init(
        type: UnitTypeID,
        origin: RegimentOrigin,
        men: Int,
        morale: Double,
        homeProvince: ProvinceID? = nil
    ) {
        self.type = type
        self.origin = origin
        self.men = men
        self.morale = morale
        self.homeProvince = homeProvince
    }
}

/// Struct-of-arrays table of all armies on the map.
/// Slots are recycled via `alive` when an army is disbanded or destroyed so
/// `ArmyID` indices stay stable while an army lives.
public struct ArmyTable: Sendable, Codable {
    public var name: [String] = []
    public var owner: [CountryID] = []
    public var province: [ProvinceID] = []
    public var commander: [CharacterID?] = []
    public var regiments: [[Regiment]] = []
    /// Remaining province hops on the army's march (`path.first` is the next
    /// adjacent province being entered).
    public var path: [[ProvinceID]] = []
    /// Days spent marching toward `path.first`.
    public var moveProgressDays: [Double] = []
    /// Total days required to enter `path.first`.
    public var moveStepDays: [Double] = []
    /// True when this army is a rebellious great vassal's levy host in open revolt.
    public var isRebel: [Bool] = []
    /// The revolting great vassal leading this rebel host, if any.
    public var rebelLeader: [CharacterID?] = []
    /// Previous province stepped from (used for river crossing battle penalties).
    public var previousProvince: [ProvinceID?] = []
    /// True while an army is executing a shattered retreat after a defeated battle.
    public var isRetreating: [Bool] = []
    public var alive: [Bool] = []

    public init() {}

    public var count: Int { name.count }

    @discardableResult
    public mutating func append(
        name: String,
        owner: CountryID,
        province: ProvinceID,
        commander: CharacterID? = nil,
        regiments: [Regiment],
        isRebel: Bool = false,
        rebelLeader: CharacterID? = nil
    ) -> ArmyID {
        let id = ArmyID(Int32(self.name.count))
        self.name.append(name)
        self.owner.append(owner)
        self.province.append(province)
        self.commander.append(commander)
        self.regiments.append(regiments)
        self.path.append([])
        self.moveProgressDays.append(0)
        self.moveStepDays.append(0)
        self.isRebel.append(isRebel)
        self.rebelLeader.append(rebelLeader)
        self.previousProvince.append(nil)
        self.isRetreating.append(false)
        self.alive.append(true)
        return id
    }

    public mutating func remove(_ id: ArmyID) {
        let i = Int(id.rawValue)
        guard i >= 0 && i < alive.count else { return }
        alive[i] = false
        commander[i] = nil
        rebelLeader[i] = nil
        previousProvince[i] = nil
        isRetreating[i] = false
        regiments[i].removeAll()
        path[i].removeAll()
        moveProgressDays[i] = 0
        moveStepDays[i] = 0
    }

    public func totalMen(of id: ArmyID) -> Int {
        let i = Int(id.rawValue)
        guard i >= 0 && i < alive.count && alive[i] else { return 0 }
        var sum = 0
        for r in regiments[i] { sum += r.men }
        return sum
    }

    public func destination(of id: ArmyID) -> ProvinceID? {
        let i = Int(id.rawValue)
        guard i >= 0 && i < alive.count && alive[i] else { return nil }
        return path[i].last
    }
}

/// Complete military state stored on `World`.
public struct Military: Sendable {
    public var unitTypes: [UnitType] = []
    public var unitByKey: [String: UnitTypeID] = [:]
    public var armies = ArmyTable()

    /// Current national manpower pool (in men), indexed by `CountryID`.
    public var manpower: [Double] = []
    /// Maximum national manpower pool (in men), indexed by `CountryID`.
    public var maxManpower: [Double] = []
    /// Last month's total army upkeep (ducats), indexed by `CountryID`.
    public var lastArmyUpkeep: [Double] = []
    /// Last month's total attrition deaths (men), indexed by `CountryID`.
    public var lastAttritionLosses: [Int] = []
    /// Ongoing multi-day field battles across the map.
    public var battles: [Battle] = []
    /// Archive of recent completed battles (up to 50).
    public var recentBattles: [BattleReport] = []
    /// Active sieges against fortified provinces.
    public var sieges: [Siege] = []

    public init() {}

    public mutating func resize(countries n: Int) {
        manpower = Array(repeating: 0, count: n)
        maxManpower = Array(repeating: 0, count: n)
        lastArmyUpkeep = Array(repeating: 0, count: n)
        lastAttritionLosses = Array(repeating: 0, count: n)
    }

    public func unit(_ key: String) -> UnitType? {
        guard let id = unitByKey[key] else { return nil }
        return unitTypes[Int(id.rawValue)]
    }

    public func unit(_ id: UnitTypeID) -> UnitType {
        unitTypes[Int(id.rawValue)]
    }

    public func armies(of country: CountryID, includeRebels: Bool = false) -> [ArmyID] {
        var result: [ArmyID] = []
        for i in 0..<armies.count {
            guard armies.alive[i], armies.owner[i] == country else { continue }
            if !includeRebels && armies.isRebel[i] { continue }
            result.append(ArmyID(Int32(i)))
        }
        return result
    }

    public func rebelArmies(of country: CountryID) -> [ArmyID] {
        var result: [ArmyID] = []
        for i in 0..<armies.count {
            guard armies.alive[i], armies.owner[i] == country, armies.isRebel[i] else { continue }
            result.append(ArmyID(Int32(i)))
        }
        return result
    }

    public func armies(in province: ProvinceID) -> [ArmyID] {
        var result: [ArmyID] = []
        for i in 0..<armies.count {
            guard armies.alive[i], armies.province[i] == province else { continue }
            result.append(ArmyID(Int32(i)))
        }
        return result
    }

    public func totalMen(of country: CountryID) -> Int {
        var sum = 0
        for id in armies(of: country) {
            sum += armies.totalMen(of: id)
        }
        return sum
    }

    public func totalMen(of country: CountryID, origin: RegimentOrigin) -> Int {
        var sum = 0
        for id in armies(of: country) {
            for r in armies.regiments[Int(id.rawValue)] where r.origin == origin {
                sum += r.men
            }
        }
        return sum
    }

    public func isInBattle(_ army: ArmyID) -> Bool {
        battles.contains { $0.attackers.contains(army) || $0.defenders.contains(army) }
    }

    public func battle(in province: ProvinceID) -> Battle? {
        battles.first { $0.province == province }
    }

    public func siege(in province: ProvinceID) -> Siege? {
        sieges.first { $0.province == province }
    }
}
