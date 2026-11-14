import Foundation

/// Loads `Resources/diplomacy1453.json` into `world.diplomacy`:
/// historical treaties, active starting wars, baseline opinions, and trust.
enum DiplomacyLoader {
    static func loadBundled(into world: inout World) throws {
        guard let url = Bundle.module.url(forResource: "diplomacy1453", withExtension: "json") else {
            throw Scenario1453.LoadError.missingResource
        }
        try load(from: Data(contentsOf: url), into: &world)
    }

    static func load(from data: Data, into world: inout World) throws {
        let file = try JSONDecoder().decode(DiplomacyFile.self, from: data)
        var dip = Diplomacy()
        dip.resize(countries: world.countries.count)

        // 1. Baseline diplomatic opinions & trust based on religion and government
        for a in world.countries.ids {
            for b in world.countries.ids where a != b {
                var opinion = 0
                let trust = 50

                let relA = world.countries.religion[a.index]
                let relB = world.countries.religion[b.index]
                if relA == relB {
                    opinion += 10
                } else if relA.family == relB.family {
                    opinion -= 10
                } else {
                    opinion -= 25
                }

                let govA = world.countries.government[a.index]
                let govB = world.countries.government[b.index]
                if govA == govB {
                    opinion += 10
                } else {
                    opinion -= 5
                }

                dip.setOpinion(of: b, by: a, value: opinion)
                dip.setTrust(of: b, by: a, value: trust)
            }
        }

        // 2. Overlords and subjects
        for c in world.countries.ids {
            if let overlord = world.countries.overlord[c.index] {
                let isVassal = world.countries.subjectType[c.index] == .vassal
                let opBonus = isVassal ? 30 : 15
                let trBonus = isVassal ? 60 : 55

                dip.modifyOpinion(of: c, by: overlord, delta: opBonus)
                dip.modifyOpinion(of: overlord, by: c, delta: opBonus)
                dip.setTrust(of: c, by: overlord, value: trBonus)
                dip.setTrust(of: overlord, by: c, value: trBonus)
            }
        }

        // 3. Historical treaties
        for t in file.treaties {
            guard let tagA = world.countries.id(forTag: t.firstTag) else {
                throw Scenario1453.LoadError.unknownValue("country tag \(t.firstTag)")
            }
            guard let tagB = world.countries.id(forTag: t.secondTag) else {
                throw Scenario1453.LoadError.unknownValue("country tag \(t.secondTag)")
            }
            guard let type = TreatyType(rawValue: t.type) else {
                throw Scenario1453.LoadError.unknownValue("treaty type \(t.type)")
            }

            var expiryDate: GameDate?
            if let exp = t.expiry {
                let parts = exp.split(separator: "-").compactMap { Int($0) }
                if parts.count == 3 {
                    expiryDate = GameDate(year: parts[0], month: parts[1], day: parts[2])
                }
            }

            dip.addTreaty(Treaty(first: tagA, second: tagB, type: type, expiry: expiryDate, note: t.note ?? ""))

            // Treaty opinion and trust adjustments
            switch type {
            case .alliance:
                dip.modifyOpinion(of: tagB, by: tagA, delta: 50)
                dip.modifyOpinion(of: tagA, by: tagB, delta: 50)
                dip.setTrust(of: tagB, by: tagA, value: 70)
                dip.setTrust(of: tagA, by: tagB, value: 70)
            case .guarantee:
                // Target has high opinion of guarantor
                dip.modifyOpinion(of: tagA, by: tagB, delta: 25)
                dip.setTrust(of: tagA, by: tagB, value: 65)
            case .nonAggression:
                dip.modifyOpinion(of: tagB, by: tagA, delta: 15)
                dip.modifyOpinion(of: tagA, by: tagB, delta: 15)
                dip.setTrust(of: tagB, by: tagA, value: 60)
                dip.setTrust(of: tagA, by: tagB, value: 60)
            case .militaryAccess:
                dip.modifyOpinion(of: tagA, by: tagB, delta: 10)
            case .truce:
                dip.modifyOpinion(of: tagB, by: tagA, delta: -15)
                dip.modifyOpinion(of: tagA, by: tagB, delta: -15)
            }
        }

        // 4. Historical active wars
        for w in file.wars {
            guard let cb = CasusBelli(rawValue: w.casusBelli) else {
                throw Scenario1453.LoadError.unknownValue("casus belli \(w.casusBelli)")
            }

            let goal: WarGoal
            switch w.warGoalType {
            case "conquer_province":
                guard let targetName = w.warGoalTarget, let pid = world.provinces.id(named: targetName) else {
                    throw Scenario1453.LoadError.unknownValue("province \(w.warGoalTarget ?? "nil")")
                }
                goal = .conquerProvince(pid)
            case "defend_capital":
                guard let targetName = w.warGoalTarget, let pid = world.provinces.id(named: targetName) else {
                    throw Scenario1453.LoadError.unknownValue("province \(w.warGoalTarget ?? "nil")")
                }
                goal = .defendCapital(pid)
            default:
                goal = .superiority
            }

            var attackers: [CountryID] = []
            for tag in w.attackers {
                guard let cid = world.countries.id(forTag: tag) else {
                    throw Scenario1453.LoadError.unknownValue("attacker tag \(tag)")
                }
                attackers.append(cid)
            }

            var defenders: [CountryID] = []
            for tag in w.defenders {
                guard let cid = world.countries.id(forTag: tag) else {
                    throw Scenario1453.LoadError.unknownValue("defender tag \(tag)")
                }
                defenders.append(cid)
            }

            let startParts = w.startDate.split(separator: "-").compactMap { Int($0) }
            let sDate = startParts.count == 3
                ? GameDate(year: startParts[0], month: startParts[1], day: startParts[2])
                : Scenario1453.startDate

            dip.addWar(War(
                id: w.id,
                name: w.name,
                startDate: sDate,
                casusBelli: cb,
                warGoal: goal,
                attackers: attackers,
                defenders: defenders,
                warScore: 0.0,
                note: w.note ?? ""
            ))

            // At war: -100 opinion, 10 trust between enemies
            for att in attackers {
                for def in defenders {
                    dip.setOpinion(of: def, by: att, value: -100)
                    dip.setOpinion(of: att, by: def, value: -100)
                    dip.setTrust(of: def, by: att, value: 10)
                    dip.setTrust(of: att, by: def, value: 10)
                }
            }
        }

        // 5. Traditional historical rivalries / tensions
        let rivals = [
            ("FRA", "ENG", -50, 20),
            ("TUR", "HUN", -50, 20),
            ("VEN", "GEN", -50, 20),
            ("VEN", "MLO", -40, 20),
            ("QAR", "AKK", -40, 20),
            ("DEL", "JAU", -40, 20),
            ("VIJ", "BAH", -50, 20),
            ("POL", "TEU", -40, 25),
        ]
        for (tagA, tagB, opDelta, trustVal) in rivals {
            if let idA = world.countries.id(forTag: tagA), let idB = world.countries.id(forTag: tagB) {
                // If not already at war (which sets -100)
                if !dip.isAtWar(idA, idB) {
                    dip.modifyOpinion(of: idB, by: idA, delta: opDelta)
                    dip.modifyOpinion(of: idA, by: idB, delta: opDelta)
                    dip.setTrust(of: idB, by: idA, value: trustVal)
                    dip.setTrust(of: idA, by: idB, value: trustVal)
                }
            }
        }

        world.diplomacy = dip
    }
}

// MARK: - JSON Shape

private struct DiplomacyFile: Decodable {
    let treaties: [TreatyEntry]
    let wars: [WarEntry]
}

private struct TreatyEntry: Decodable {
    let firstTag: String
    let secondTag: String
    let type: String
    let expiry: String?
    let note: String?
}

private struct WarEntry: Decodable {
    let id: String
    let name: String
    let startDate: String
    let casusBelli: String
    let warGoalType: String
    let warGoalTarget: String?
    let attackers: [String]
    let defenders: [String]
    let note: String?
}
