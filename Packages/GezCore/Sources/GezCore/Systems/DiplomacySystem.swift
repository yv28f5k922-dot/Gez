import Foundation

/// System governing daily and monthly diplomatic updates:
/// expiring truces, war score & ticking war goals, trust drift, AE decay,
/// war reparations, coalition formation, and diplomatic relation slot upkeep.
public enum DiplomacySystem {

    /// Daily diplomatic tick: expires truces and updates active war scores & ticking war goals.
    public static func runDaily(_ world: inout World, date: GameDate) {
        var toRemove: [(CountryID, CountryID)] = []
        for t in world.diplomacy.treaties where t.type == .truce {
            if let exp = t.expiry, date >= exp {
                toRemove.append((t.first, t.second))
            }
        }
        for (a, b) in toRemove {
            world.diplomacy.removeTreaty(.truce, between: a, and: b)
        }

        updateWarScores(&world)
    }

    /// Monthly diplomatic tick: trust drift, AE decay, war reparations, coalitions, and slot upkeep.
    public static func runMonthly(_ world: inout World, date: GameDate) {
        let n = world.countries.count
        guard n > 0 && world.diplomacy.countryCount == n else { return }

        // 1. Trust drift: drifts 1 point towards 50 every 5 months (~0.2 per month)
        if date.month % 5 == 0 {
            for i in 0..<world.diplomacy.trusts.count {
                let current = world.diplomacy.trusts[i]
                if current < 50 {
                    world.diplomacy.trusts[i] = current + 1
                } else if current > 50 {
                    world.diplomacy.trusts[i] = current - 1
                }
            }
        }

        // 2. Aggressive expansion decay: decay ~2.0 per year (~0.17 per month)
        // Scaled by ruler diplomacy skill: +2% decay speed per point of diplomacy
        var decayByCountry = [Double](repeating: 0.17, count: n)
        for cid in 0..<n {
            if let rulerID = world.countries.ruler[cid] {
                let dip = world.people.characters.skills[rulerID.index][Skill.diplomacy.rawValue]
                decayByCountry[cid] = 0.17 * (1.0 + Double(dip) * 0.02)
            }
        }
        for idx in 0..<world.diplomacy.aggressiveExpansion.count {
            let currentAE = world.diplomacy.aggressiveExpansion[idx]
            guard currentAE > 0 else { continue }
            let cIdx = idx % n
            let otherIdx = idx / n
            guard cIdx != otherIdx else { continue }
            world.diplomacy.aggressiveExpansion[idx] = Float(max(0.0, Double(currentAE) - decayByCountry[cIdx]))
        }

        // 3. War reparations (10% monthly income for 10 years)
        world.diplomacy.warReparations.removeAll { date >= $0.until }
        for rep in world.diplomacy.warReparations {
            let income = max(0.0, world.countries.lastMonthlyIncome[rep.payer.index])
            let payment = (income * 0.10 * 100.0).rounded() / 100.0
            if payment > 0 {
                world.countries.treasury[rep.payer.index] -= payment
                world.countries.treasury[rep.receiver.index] += payment
                world.countries.lastMonthlyExpenses[rep.payer.index] += payment
                world.countries.lastMonthlyIncome[rep.receiver.index] += payment
            }
        }

        // 4. Coalitions update
        updateCoalitions(&world)

        // 5. Diplomatic relation slot upkeep
        for c in world.countries.ids {
            let available = world.diplomacy.relationSlots(for: c, world: world)
            let used = world.diplomacy.usedRelationSlots(for: c, world: world)
            if used > available {
                let excess = used - available
                let cost = Double(excess) * 1.0
                world.countries.treasury[c.index] = max(0.0, world.countries.treasury[c.index] - cost)
                world.countries.lastMonthlyExpenses[c.index] += cost
            }
        }
    }

    // MARK: - War Score & Ticking War Goal

    /// Recomputes every active war's `tickingWarScore` (±0.25 max), occupation score,
    /// and total `warScore` (-1.0 to +1.0 from attacker's point of view).
    public static func updateWarScores(_ world: inout World) {
        guard !world.diplomacy.wars.isEmpty else { return }
        var ownedCount = [Int](repeating: 0, count: world.countries.count)
        for p in 0..<world.provinces.count {
            if let owner = world.provinces.owner[p] {
                ownedCount[owner.index] += 1
            }
        }
        for idx in world.diplomacy.wars.indices {
            var war = world.diplomacy.wars[idx]

            // 1. Ticking war goal (-0.25 ... +0.25; ~+0.03 per month / +0.25 in ~8 months)
            let tickStep = 0.001
            switch war.warGoal {
            case .conquerProvince(let pid):
                if let ctrl = world.provinces.controller(of: pid) {
                    if war.isAttacker(ctrl) {
                        war.tickingWarScore = min(0.25, war.tickingWarScore + tickStep)
                    } else if war.isDefender(ctrl) {
                        war.tickingWarScore = max(-0.25, war.tickingWarScore - tickStep)
                    }
                }
            case .defendCapital(let pid):
                if let ctrl = world.provinces.controller(of: pid) {
                    if war.isDefender(ctrl) {
                        war.tickingWarScore = max(-0.25, war.tickingWarScore - tickStep)
                    } else if war.isAttacker(ctrl) {
                        war.tickingWarScore = min(0.25, war.tickingWarScore + tickStep)
                    }
                }
            case .superiority:
                if war.battleWarScore >= 0.10 {
                    war.tickingWarScore = min(0.25, war.tickingWarScore + tickStep)
                } else if war.battleWarScore <= -0.10 {
                    war.tickingWarScore = max(-0.25, war.tickingWarScore - tickStep)
                }
            }

            // 2. Province & capital occupation score
            var defTotalDev = 0
            var defOccupiedDev = 0
            var attTotalDev = 0
            var attOccupiedDev = 0
            var primaryDefUnoccupiedProvs = 0
            var primaryAttUnoccupiedProvs = 0

            let pDef = war.primaryDefender
            let pAtt = war.primaryAttacker

            for p in 0..<world.provinces.count {
                guard let owner = world.provinces.owner[p] else { continue }
                let dev = max(1, world.provinces.development[p])
                let occ = world.provinces.occupiedBy[p]

                if war.isDefender(owner) {
                    defTotalDev += dev
                    if let occ = occ, war.isAttacker(occ) {
                        defOccupiedDev += dev
                    } else if owner == pDef {
                        primaryDefUnoccupiedProvs += 1
                    }
                } else if war.isAttacker(owner) {
                    attTotalDev += dev
                    if let occ = occ, war.isDefender(occ) {
                        attOccupiedDev += dev
                    } else if owner == pAtt {
                        primaryAttUnoccupiedProvs += 1
                    }
                }
            }

            let primaryDefOwnedCount = ownedCount[pDef.index]
            let primaryAttOwnedCount = ownedCount[pAtt.index]

            if primaryDefOwnedCount > 0 && primaryDefUnoccupiedProvs == 0 {
                // Primary defender 100% occupied -> +100% attacker warscore
                war.warScore = 1.0
            } else if primaryAttOwnedCount > 0 && primaryAttUnoccupiedProvs == 0 {
                // Primary attacker 100% occupied -> -100% warscore
                war.warScore = -1.0
            } else {
                var occAtt = (Double(defOccupiedDev) / Double(max(1, defTotalDev))) * 0.65
                if let defCap = world.countries.capital[pDef.index],
                   let occ = world.provinces.occupiedBy[defCap.index],
                   war.isAttacker(occ) {
                    occAtt += 0.15
                }

                var occDef = (Double(attOccupiedDev) / Double(max(1, attTotalDev))) * 0.65
                if let attCap = world.countries.capital[pAtt.index],
                   let occ = world.provinces.occupiedBy[attCap.index],
                   war.isDefender(occ) {
                    occDef += 0.15
                }

                let occNet = max(-0.75, min(0.75, occAtt - occDef))
                let combined = war.battleWarScore + occNet + war.tickingWarScore
                war.warScore = max(-1.0, min(1.0, combined))
            }

            world.diplomacy.wars[idx] = war
        }
    }

    // MARK: - Coalition Formation & Maintenance

    /// Forms or dissolves defensive/punitive coalitions against aggressive expanders.
    /// Requires 50+ AE with 4+ outraged independent countries (dissolves below 2 members / 30 AE).
    public static func updateCoalitions(_ world: inout World) {
        let countries = world.countries.ids
        let n = countries.count
        var ownedCount = Array(repeating: 0, count: n)
        for p in 0..<world.provinces.count {
            if let owner = world.provinces.owner[p], owner.index < n {
                ownedCount[owner.index] += 1
            }
        }

        for target in countries {
            guard ownedCount[target.index] > 0 else {
                world.diplomacy.coalitions.removeValue(forKey: target)
                continue
            }

            var currentMembers = world.diplomacy.coalitions[target] ?? []
            if !currentMembers.isEmpty {
                currentMembers = currentMembers.filter { m in
                    guard m != target,
                          ownedCount[m.index] > 0,
                          world.countries.overlord[m.index] == nil else { return false }
                    guard world.diplomacy.aggressiveExpansion(of: target, by: m) >= 30.0
                            && world.diplomacy.opinion(of: target, by: m) < 0 else { return false }
                    return !world.diplomacy.hasTruce(m, target)
                }
            }

            // Find all eligible countries at 50+ AE with negative opinion (check cheap scalar arrays first)
            var outraged50: [CountryID] = []
            for other in countries where other != target {
                guard ownedCount[other.index] > 0,
                      world.countries.overlord[other.index] == nil else { continue }
                let ae = world.diplomacy.aggressiveExpansion(of: target, by: other)
                guard ae >= 50.0 else { continue }
                let op = world.diplomacy.opinion(of: target, by: other)
                guard op < 0,
                      !world.diplomacy.isAtWar(other, target),
                      !world.diplomacy.hasTruce(other, target) else { continue }
                outraged50.append(other)
            }

            if outraged50.count >= 4 {
                for m in outraged50 {
                    currentMembers.insert(m)
                }
            } else if currentMembers.count < 2 {
                currentMembers.removeAll()
            } else {
                for m in outraged50 {
                    currentMembers.insert(m)
                }
            }

            if currentMembers.isEmpty {
                world.diplomacy.coalitions.removeValue(forKey: target)
            } else {
                world.diplomacy.coalitions[target] = currentMembers
            }
        }
    }
}
