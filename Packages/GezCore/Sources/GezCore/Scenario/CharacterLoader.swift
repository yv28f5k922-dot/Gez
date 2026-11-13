import Foundation

/// Loads `Resources/characters1453.json` into `world.people` and sets each
/// country's ruler, heir, council and succession law.
enum CharacterLoader {
    static func loadBundled(into world: inout World) throws {
        guard let url = Bundle.module.url(forResource: "characters1453", withExtension: "json") else {
            throw Scenario1453.LoadError.missingResource
        }
        try load(from: Data(contentsOf: url), into: &world)
    }

    static func load(from data: Data, into world: inout World) throws {
        let file = try JSONDecoder().decode(CharacterFile.self, from: data)
        var people = People()
        for t in file.traits {
            people.traits.add(key: t.key, name: t.name, skills: t.skills)
        }
        for (i, t) in file.traits.enumerated() {
            if let o = t.opposite, let oid = people.traits.id(forKey: o) {
                people.traits.setOpposite(TraitID(i), oid)
            }
        }
        for (family, lists) in file.names {
            people.names.male[family] = lists.male
            people.names.female[family] = lists.female
        }
        for c in file.characters {
            guard let culture = world.cultures.id(forKey: c.culture) else {
                throw Scenario1453.LoadError.unknownValue("culture \(c.culture)")
            }
            guard let religion = Religion(rawValue: c.religion) else {
                throw Scenario1453.LoadError.unknownValue("religion \(c.religion)")
            }
            guard let country = world.countries.id(forTag: c.country) else {
                throw Scenario1453.LoadError.unknownValue("country \(c.country)")
            }
            people.characters.add(
                key: c.id, name: c.name, dynasty: c.dynasty, female: c.female,
                birth: GameDate(year: c.born[0], month: c.born[1], day: min(c.born[2], 28)),
                culture: culture, religion: religion, traits: c.traits.map(TraitID.init),
                skills: c.skills, court: country, invented: c.invented, note: c.note)
        }
        for (i, c) in file.characters.enumerated() {
            let id = CharacterID(i)
            if let f = c.father {
                people.characters.father[i] = CharacterID(f)
                people.characters.children[f].append(id)
            }
            if let m = c.mother {
                people.characters.mother[i] = CharacterID(m)
                people.characters.children[m].append(id)
            }
            for s in c.spouses { people.characters.marry(id, CharacterID(s)) }
            if let d = c.died {
                people.characters.death[i] = GameDate(year: d[0], month: d[1], day: min(d[2], 28))
            }
            people.characters.illegitimate[i] = c.illegitimate ?? false
        }
        world.people = people
        for (province, who) in file.holdings ?? [:] {
            guard let p = Int(province), p < world.provinces.count, who < people.characters.count else { continue }
            world.provinces.holder[p] = CharacterID(who)
        }

        for (tag, roles) in file.countries {
            guard let country = world.countries.id(forTag: tag) else { continue }
            world.countries.ruler[country.index] = CharacterID(roles.ruler)
            world.countries.heir[country.index] = roles.heir.map(CharacterID.init)
            for seat in CouncilSeat.allCases {
                if let who = roles.council[String(describing: seat)] {
                    world.countries.council[country.index][seat.rawValue] = CharacterID(who)
                }
            }
        }
        for c in world.countries.ids {
            world.countries.succession[c.index] = CharacterSystem.defaultLaw(world.countries.government[c.index])
        }
        for (tag, law) in file.succession {
            if let c = world.countries.id(forTag: tag), let l = SuccessionLaw(rawValue: law) {
                world.countries.succession[c.index] = l
            }
        }
    }
}

struct CharacterFile: Decodable {
    struct Trait: Decodable {
        let key: String
        let name: String
        let opposite: String?
        let skills: [Int]
    }

    struct Person: Decodable {
        let id: String
        let name: String
        let dynasty: String?
        let female: Bool
        let born: [Int]
        let father: Int?
        let mother: Int?
        let spouses: [Int]
        let culture: String
        let religion: String
        let traits: [Int]
        let skills: [Int]
        let country: String
        let invented: Bool
        let note: String?
        let died: [Int]?
        let illegitimate: Bool?
    }

    struct Roles: Decodable {
        let ruler: Int
        let heir: Int?
        let council: [String: Int]
    }

    struct Names: Decodable {
        let male: [String]
        let female: [String]
    }

    let names: [String: Names]
    let succession: [String: String]
    let traits: [Trait]
    let characters: [Person]
    let countries: [String: Roles]
    /// Province index (as text) → holder's character index.
    let holdings: [String: Int]?
}
