import Foundation

/// Loads `Resources/military1453.json` into `world.military`: the 15 unit
/// types (5 core + 10 historical 1453 regional units) and the 30 May 1453
/// standing armies on the map.
enum MilitaryLoader {
    static func loadBundled(into world: inout World) throws {
        guard let url = Bundle.module.url(forResource: "military1453", withExtension: "json") else {
            throw Scenario1453.LoadError.missingResource
        }
        try load(from: Data(contentsOf: url), into: &world)
    }

    static func load(from data: Data, into world: inout World) throws {
        let file = try JSONDecoder().decode(MilitaryFile.self, from: data)
        var mil = Military()
        mil.resize(countries: world.countries.count)

        for (idx, u) in file.units.enumerated() {
            guard let cat = UnitCategory(rawValue: u.category) else {
                throw Scenario1453.LoadError.unknownValue("unit category \(u.category)")
            }
            var goods: [(GoodID, Double)] = []
            for key in u.goods.keys.sorted() {
                guard let gid = world.economy.goods.id(forKey: key) else {
                    throw Scenario1453.LoadError.unknownValue("good \(key)")
                }
                goods.append((gid, u.goods[key]!))
            }
            var requires: [UnitUnlock] = []
            for req in u.requires {
                switch req.kind {
                case "estate":
                    requires.append(.estate(req.values))
                case "government":
                    let govs = try req.values.map { raw -> GovernmentType in
                        guard let g = GovernmentType(rawValue: raw) else {
                            throw Scenario1453.LoadError.unknownValue("government \(raw)")
                        }
                        return g
                    }
                    requires.append(.government(govs))
                case "culture":
                    requires.append(.culture(req.values))
                case "region":
                    requires.append(.region(req.values))
                case "tags":
                    requires.append(.tags(req.values))
                default:
                    throw Scenario1453.LoadError.unknownValue("unit requirement \(req.kind)")
                }
            }
            let id = UnitTypeID(UInt8(idx))
            let unit = UnitType(
                id: id,
                key: u.key,
                name: u.name,
                category: cat,
                maxMen: u.men,
                speed: u.speed,
                attack: u.attack,
                defence: u.defence,
                morale: u.morale,
                siege: u.siege,
                cost: u.cost,
                upkeep: u.upkeep,
                goods: goods,
                requires: requires
            )
            mil.unitTypes.append(unit)
            mil.unitByKey[u.key] = id
        }

        for a in file.armies {
            guard let cid = world.countries.id(forTag: a.country) else {
                throw Scenario1453.LoadError.unknownValue("country \(a.country)")
            }
            guard a.province >= 0 && a.province < world.provinces.count else {
                throw Scenario1453.LoadError.unknownValue("province \(a.province)")
            }
            let pid = ProvinceID(a.province)
            var commander: CharacterID?
            if let key = a.commander {
                guard let ch = world.people.characters.id(forKey: key) else {
                    throw Scenario1453.LoadError.unknownValue("commander \(key)")
                }
                commander = ch
            }
            var regs: [Regiment] = []
            for r in a.regiments {
                guard let uid = mil.unitByKey[r.type] else {
                    throw Scenario1453.LoadError.unknownValue("unit \(r.type)")
                }
                guard let origin = RegimentOrigin(rawValue: r.origin) else {
                    throw Scenario1453.LoadError.unknownValue("origin \(r.origin)")
                }
                let u = mil.unit(uid)
                regs.append(Regiment(
                    type: uid,
                    origin: origin,
                    men: r.men,
                    morale: u.morale,
                    homeProvince: origin == .levy ? pid : nil
                ))
            }
            mil.armies.append(
                name: a.name,
                owner: cid,
                province: pid,
                commander: commander,
                regiments: regs
            )
        }

        // Seed starting national manpower pools from owned provinces and barracks.
        let typeCount = world.economy.buildings.typeCount
        for cid in world.countries.ids {
            var popSum = 0.0
            var barracksBonus = 0.0
            for pid in world.provinces(ownedBy: cid) {
                popSum += world.provinces.population[pid.index]
                for t in 0..<typeCount {
                    if case .manpower(let x) = world.economy.buildingTypes[t].effect {
                        let lvl = world.economy.buildings.level(pid, BuildingTypeID(t))
                        if lvl > 0 {
                            barracksBonus += Double(lvl) * x * 1_000.0
                        }
                    }
                }
            }
            let base = max(1_000.0, (popSum * 0.012 + barracksBonus).rounded())
            mil.maxManpower[cid.index] = base
            mil.manpower[cid.index] = (base * 0.75).rounded()
        }

        world.military = mil
    }
}

struct MilitaryFile: Decodable {
    struct Requirement: Decodable {
        let kind: String
        let values: [String]
    }

    struct Unit: Decodable {
        let key: String
        let name: String
        let category: String
        let men: Int
        let speed: Double
        let attack: Double
        let defence: Double
        let morale: Double
        let siege: Double
        let cost: Double
        let upkeep: Double
        let goods: [String: Double]
        let requires: [Requirement]
    }

    struct RegimentEntry: Decodable {
        let type: String
        let origin: String
        let men: Int
    }

    struct ArmyEntry: Decodable {
        let country: String
        let name: String
        let province: Int
        let commander: String?
        let regiments: [RegimentEntry]
    }

    let units: [Unit]
    let armies: [ArmyEntry]
}
