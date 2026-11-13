import Foundation

/// Loads `Resources/government1453.json` into `world.government`: the
/// rules, and each country's 1453 laws, reforms and estates.
enum GovernmentLoader {
    static func loadBundled(into world: inout World) throws {
        guard let url = Bundle.module.url(forResource: "government1453", withExtension: "json") else {
            throw Scenario1453.LoadError.missingResource
        }
        try load(from: Data(contentsOf: url), into: &world)
    }

    static func load(from data: Data, into world: inout World) throws {
        let file = try JSONDecoder().decode(GovernmentFile.self, from: data)
        var rules = GovernmentRules()
        let estateKeys = file.estates.map(\.key)
        let n = estateKeys.count

        func effects(_ e: GovernmentFile.Eff) throws -> Effects {
            var out = Effects(estates: n)
            for (k, v) in e.m {
                guard let m = Modifier(key: k) else { throw Scenario1453.LoadError.unknownValue("modifier \(k)") }
                out[m] += v
            }
            for (k, v) in e.l {
                guard let i = estateKeys.firstIndex(of: k) else { throw Scenario1453.LoadError.unknownValue("estate \(k)") }
                out.loyalty[i] += v
            }
            for (k, v) in e.p {
                guard let i = estateKeys.firstIndex(of: k) else { throw Scenario1453.LoadError.unknownValue("estate \(k)") }
                out.power[i] += v
            }
            return out
        }

        for e in file.estates {
            let source: EstateSource
            if e.source.hasPrefix("class:") {
                guard let cls = SocialClass(rawValue: String(e.source.dropFirst(6))) else {
                    throw Scenario1453.LoadError.unknownValue("estate source \(e.source)")
                }
                source = .socialClass(cls)
            } else if e.source.hasPrefix("fixed:") {
                source = .fixed(Double(e.source.dropFirst(6)) ?? 0.1)
            } else if e.source == "dhimmi" {
                source = .dhimmi
            } else if e.source == "rajput" {
                source = .rajput
            } else if e.source == "tribes" {
                source = .tribes
            } else {
                throw Scenario1453.LoadError.unknownValue("estate source \(e.source)")
            }
            rules.estates.append(EstateDef(key: e.key, name: e.name, source: source, weight: e.weight,
                                           loyal: try effects(e.loyal), disloyal: try effects(e.disloyal)))
        }
        rules.tribalCultures = Set(file.tribalCultures.compactMap { world.cultures.id(forKey: $0) })
        rules.rajputCultures = Set(file.rajputCultures.compactMap { world.cultures.id(forKey: $0) })
        for p in file.privileges {
            guard let e = estateKeys.firstIndex(of: p.estate) else { throw Scenario1453.LoadError.unknownValue("estate \(p.estate)") }
            rules.privileges.append(PrivilegeDef(estate: EstateID(e), key: p.key, name: p.name, loyalty: p.loyalty,
                                                 power: p.power, effects: try effects(p.effects), gold: p.gold))
        }
        for a in file.lawAreas {
            let options = try a.options.map { o in
                LawOption(key: o.key, name: o.name, effects: try effects(o.effects),
                          governments: o.governments.compactMap(GovernmentType.init(rawValue:)))
            }
            rules.lawAreas.append(LawArea(key: a.key, name: a.name, options: options))
        }
        for (g, tiers) in file.reforms {
            guard let gov = GovernmentType(rawValue: g) else { throw Scenario1453.LoadError.unknownValue("government \(g)") }
            rules.reforms[gov] = try tiers.map { t in
                ReformTier(cost: t.cost, options: try t.options.map { o in
                    ReformOption(key: o.key, name: o.name, effects: try effects(o.effects),
                                 becomes: o.becomes.flatMap(GovernmentType.init(rawValue:)))
                })
            }
        }

        var gov = Government()
        gov.rules = rules
        gov.resize(countries: world.countries.count)
        let successionArea = rules.successionArea
        for c in world.countries.ids {
            let i = c.index
            if let entry = file.countries[world.countries.tag[i]] {
                for (area, option) in entry.laws {
                    if let a = rules.lawArea(forKey: area) { gov.laws[i][a] = option }
                }
                gov.reforms[i] = entry.reforms
                gov.stability[i] = entry.stability
                gov.estates[i] = entry.estates.compactMap { k in estateKeys.firstIndex(of: k).map(EstateID.init) }
            }
            // Succession law mirrors the characters' succession.
            if let a = successionArea {
                let law = world.countries.succession[i]
                gov.laws[i][a] = rules.lawAreas[a].options.firstIndex { $0.key == law.rawValue } ?? 0
            }
        }
        world.government = gov
        GovernmentSystem.settle(&world)
    }
}

struct GovernmentFile: Decodable {
    struct Eff: Decodable {
        let m: [String: Double]
        let l: [String: Double]
        let p: [String: Double]
    }

    struct Estate: Decodable {
        let key: String
        let name: String
        let source: String
        let weight: Double
        let loyal: Eff
        let disloyal: Eff
    }

    struct Privilege: Decodable {
        let estate: String
        let key: String
        let name: String
        let loyalty: Double
        let power: Double
        let effects: Eff
        let gold: Double
    }

    struct Option: Decodable {
        let key: String
        let name: String
        let effects: Eff
        let governments: [String]
    }

    struct Area: Decodable {
        let key: String
        let name: String
        let options: [Option]
    }

    struct Reform: Decodable {
        let key: String
        let name: String
        let effects: Eff
        let becomes: String?
    }

    struct Tier: Decodable {
        let cost: Double
        let options: [Reform]
    }

    struct Country: Decodable {
        let laws: [String: Int]
        let reforms: [Int]
        let estates: [String]
        let stability: Int
    }

    let estates: [Estate]
    let tribalCultures: [String]
    let rajputCultures: [String]
    let privileges: [Privilege]
    let lawAreas: [Area]
    let reforms: [String: [Tier]]
    let countries: [String: Country]
}
