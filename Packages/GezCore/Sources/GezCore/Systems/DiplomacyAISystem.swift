import Foundation

/// AI diplomacy and wartime decision-making for non-human countries.
/// Handles war peace settlements, alliance/pact management, opportunistic CB
/// war declarations, call-to-arms mobilization, and weekly wartime army orders.
public enum DiplomacyAISystem {

    // MARK: - Monthly Diplomacy AI

    /// Runs monthly diplomatic decisions (peace treaties, alliances, war declarations)
    /// for AI-controlled countries.
    public static func runMonthly(
        _ world: inout World,
        date: GameDate,
        random: inout GameRandom
    ) {
        let n = world.countries.count
        guard n > 0 else { return }

        // Prune stale pending offers whose wars ended
        let activeWarIDs = Set(world.diplomacy.wars.map(\.id))
        world.diplomacy.pendingPeaceOffers.removeAll { !activeWarIDs.contains($0.warID) }

        // Precompute fast per-country lookups in O(provinces + armies)
        var ownedProvinces = Array(repeating: [ProvinceID](), count: n)
        for p in 0..<world.provinces.count {
            if let owner = world.provinces.owner[p], owner.index < n {
                ownedProvinces[owner.index].append(ProvinceID(p))
            }
        }

        var landNeighbors = Array(repeating: Set<CountryID>(), count: n)
        for p in 0..<world.provinces.count {
            guard let ownerA = world.provinces.owner[p], ownerA.index < n else { continue }
            for nb in world.provinces.neighbors[p] {
                if let ownerB = world.provinces.owner[nb.index], ownerB != ownerA, ownerB.index < n {
                    landNeighbors[ownerA.index].insert(ownerB)
                }
            }
        }

        var soldiersByCountry = Array(repeating: 0, count: n)
        for idx in 0..<world.military.armies.count {
            guard world.military.armies.alive[idx], !world.military.armies.isRebel[idx] else { continue }
            let c = world.military.armies.owner[idx]
            if c.index < n {
                soldiersByCountry[c.index] += world.military.armies.totalMen(of: ArmyID(Int32(idx)))
            }
        }

        // 1. Evaluate ongoing wars for AI peace treaties or stalemate white peace
        resolveActiveWarsAI(&world, ownedProvinces: ownedProvinces, date: date)

        // 2. Peacetime treaties (every country) & war declarations (staggered half per month for speed)
        let loanCounts = computeLoanCounts(world, countryCount: n)
        for c in world.countries.ids {
            guard !world.humanCountries.contains(c),
                  !ownedProvinces[c.index].isEmpty,
                  world.countries.overlord[c.index] == nil else { continue }

            manageAlliancesAndPacts(
                &world,
                country: c,
                landNeighbors: landNeighbors[c.index],
                ownedProvinces: ownedProvinces,
                date: date,
                random: &random
            )

            guard (c.index + date.month) % 2 == 0 else { continue }

            considerWarDeclaration(
                &world,
                attacker: c,
                landNeighbors: landNeighbors[c.index],
                ownedProvinces: ownedProvinces,
                soldiersByCountry: soldiersByCountry,
                loanCount: loanCounts[c.index],
                date: date,
                random: &random
            )
        }
    }

    // MARK: - Weekly Wartime Military AI

    /// Issues wartime movement & consolidation orders for idle AI armies.
    /// Called weekly so AI stacks keep marching cleanly between battles/occupations.
    public static func runWeeklyMilitary(_ world: inout World, date: GameDate) {
        let warSnapshot = world.diplomacy.wars
        guard !warSnapshot.isEmpty else { return }

        // Land masses: targets on another land mass cannot be reached by
        // marching, and a failed route search explores the whole map.
        let landMass = ArmySystem.landComponents(world)

        // Track enemy armies by province for quick tactical interception
        var armiesByProvince: [Int: [ArmyID]] = [:]
        var activeWarringCountries: Set<CountryID> = []
        for w in warSnapshot {
            for a in w.attackers { activeWarringCountries.insert(a) }
            for d in w.defenders { activeWarringCountries.insert(d) }
        }

        for idx in 0..<world.military.armies.count {
            guard world.military.armies.alive[idx], !world.military.armies.isRebel[idx] else { continue }
            let aid = ArmyID(Int32(idx))
            let pIdx = world.military.armies.province[idx].index
            armiesByProvince[pIdx, default: []].append(aid)
        }

        // First consolidate idle co-located AI armies at war
        for c in activeWarringCountries.sorted(by: { $0.index < $1.index }) {
            guard !world.humanCountries.contains(c) else { continue }
            // Ensure levies are raised if at war and under-strength
            let cArmies = world.military.armies(of: c)
            let totalMen = cArmies.reduce(0) { $0 + world.military.armies.totalMen(of: $1) }
            if totalMen == 0 && date >= GameDate(year: 1453, month: 6, day: 1) {
                _ = ArmySystem.raiseAllLevies(&world, c)
            }

            // Merge idle non-retreating stacks in the same province
            var byProv: [Int: [ArmyID]] = [:]
            for aid in world.military.armies(of: c) {
                let i = Int(aid.rawValue)
                guard !world.military.armies.isRebel[i],
                      !world.military.armies.isRetreating[i],
                      !world.military.isInBattle(aid),
                      world.military.armies.path[i].isEmpty else { continue }
                byProv[world.military.armies.province[i].index, default: []].append(aid)
            }
            for prov in byProv.keys.sorted() {
                if let list = byProv[prov], list.count > 1 {
                    _ = ArmySystem.mergeArmiesInProvince(&world, into: list[0])
                }
            }
        }

        // Gather war goals & unoccupied enemy targets per warring country
        for c in activeWarringCountries.sorted(by: { $0.index < $1.index }) {
            guard !world.humanCountries.contains(c) else { continue }
            let wars = world.diplomacy.activeWars(for: c)
            guard !wars.isEmpty else { continue }

            var enemies: Set<CountryID> = []
            var priorityTargets: [ProvinceID] = []
            for w in wars {
                let myEnemies = w.isAttacker(c) ? w.defenders : w.attackers
                for e in myEnemies { enemies.insert(e) }
                if case .conquerProvince(let goalProv) = w.warGoal {
                    if let gOwner = world.provinces.owner[goalProv.index],
                       myEnemies.contains(gOwner),
                       world.provinces.occupiedBy[goalProv.index] == nil {
                        priorityTargets.append(goalProv)
                    }
                }
            }
            guard !enemies.isEmpty else { continue }

            let idleArmies = world.military.armies(of: c).filter { aid in
                let i = Int(aid.rawValue)
                return !world.military.armies.isRebel[i]
                    && !world.military.armies.isRetreating[i]
                    && !world.military.isInBattle(aid)
                    && world.military.armies.path[i].isEmpty
            }
            guard !idleArmies.isEmpty else { continue }

            // Collect unoccupied enemy provinces & occupied friendly provinces to liberate
            var enemyProvs: [ProvinceID] = []
            var liberateProvs: [ProvinceID] = []
            for p in 0..<world.provinces.count {
                let pid = ProvinceID(p)
                guard let owner = world.provinces.owner[p] else { continue }
                if enemies.contains(owner) {
                    if let occ = world.provinces.occupiedBy[p] {
                        if enemies.contains(occ) { enemyProvs.append(pid) }
                    } else {
                        enemyProvs.append(pid)
                    }
                } else if owner == c, let occ = world.provinces.occupiedBy[p], enemies.contains(occ) {
                    liberateProvs.append(pid)
                }
            }

            let armyTable = world.military.armies
            for aid in idleArmies {
                let i = Int(aid.rawValue)
                let curProv = armyTable.province[i]
                let myMen = armyTable.totalMen(of: aid)
                guard myMen > 0 else { continue }

                // Skip moving if we are already actively occupying this province
                if let pOwner = world.provinces.owner[curProv.index],
                   enemies.contains(pOwner),
                   (world.provinces.occupiedBy[curProv.index].map { enemies.contains($0) } ?? true) {
                    continue
                }

                // 1. Check adjacent provinces for favorable enemy army engagement or undefended enemy land
                let neighbors = world.provinces.neighbors[curProv.index].sorted(by: { $0.index < $1.index })
                var engaged = false
                for nb in neighbors {
                    let nbArmies: [ArmyID] = armiesByProvince[nb.index] ?? []
                    var enemyMenInNb = 0
                    for otherID in nbArmies {
                        let oi = Int(otherID.rawValue)
                        if armyTable.alive[oi] && enemies.contains(armyTable.owner[oi]) {
                            enemyMenInNb += armyTable.totalMen(of: otherID)
                        }
                    }
                    if enemyMenInNb > 0 && Double(myMen) >= Double(enemyMenInNb) * 1.15 {
                        if ArmySystem.orderMove(&world, army: aid, to: nb) {
                            engaged = true
                            break
                        }
                    }
                }
                if engaged { continue }

                // 2. Adjacent undefended enemy province or occupied home province
                let adjTarget = neighbors.first { nb in
                    let nbArmies: [ArmyID] = armiesByProvince[nb.index] ?? []
                    let hasEnemyHere = nbArmies.contains { otherID in
                        let oi = Int(otherID.rawValue)
                        return armyTable.alive[oi] && enemies.contains(armyTable.owner[oi])
                    }
                    guard !hasEnemyHere else { return false }
                    if let owner = world.provinces.owner[nb.index] {
                        if enemies.contains(owner) && world.provinces.occupiedBy[nb.index] == nil {
                            return true
                        }
                        if owner == c, let occ = world.provinces.occupiedBy[nb.index], enemies.contains(occ) {
                            return true
                        }
                    }
                    return false
                }
                if let adjTarget = adjTarget {
                    if ArmySystem.orderMove(&world, army: aid, to: adjTarget) {
                        continue
                    }
                }

                // 3. Nearest priority war goal -> nearest unoccupied enemy prov -> nearest liberate prov
                let curPt = world.provinces.location[curProv.index]
                let candidatePools: [[ProvinceID]] = [priorityTargets, enemyProvs, liberateProvs]
                var ordered = false
                let myLand = landMass[curProv.index]
                for fullPool in candidatePools where !fullPool.isEmpty {
                    let pool = fullPool.filter { landMass[$0.index] == myLand }
                    guard !pool.isEmpty else { continue }
                    let sortedTargets = pool.sorted { a, b in
                        let pa = world.provinces.location[a.index]
                        let pb = world.provinces.location[b.index]
                        let da = hypot(pa.longitude - curPt.longitude, pa.latitude - curPt.latitude)
                        let db = hypot(pb.longitude - curPt.longitude, pb.latitude - curPt.latitude)
                        return da < db
                    }
                    for target in sortedTargets.prefix(5) {
                        if ArmySystem.orderMove(&world, army: aid, to: target) {
                            ordered = true
                            break
                        }
                    }
                    if ordered { break }
                }
            }
        }
    }

    // MARK: - Peace Treaty AI

    private static func resolveActiveWarsAI(
        _ world: inout World,
        ownedProvinces: [[ProvinceID]],
        date: GameDate
    ) {
        let wars = world.diplomacy.wars
        for war in wars {
            let wsPercent = Int((war.warScore * 100.0).rounded())
            let winner: CountryID = wsPercent >= 0 ? war.primaryAttacker : war.primaryDefender
            let loser: CountryID = wsPercent >= 0 ? war.primaryDefender : war.primaryAttacker
            let absWS = abs(wsPercent)

            let winnerHuman = world.humanCountries.contains(winner)
            let loserHuman = world.humanCountries.contains(loser)
            if winnerHuman { continue }

            let monthsFought = max(0, (date.year - war.startDate.year) * 12 + (date.month - war.startDate.month))
            let loserProvs = ownedProvinces[loser.index]
            let fullyOccupied = !loserProvs.isEmpty && loserProvs.allSatisfy { pid in
                world.provinces.occupiedBy[pid.index].map { war.areEnemies($0, loser) } ?? false
            }

            let isStalemate = monthsFought >= 48 && absWS < 15 && !fullyOccupied
            let wantsPeace = fullyOccupied || absWS >= 35 || isStalemate
            guard wantsPeace else { continue }

            var demands: [PeaceDemand] = []
            if !isStalemate {
                var remainingWS = fullyOccupied ? 100 : absWS
                // 1. Candidate provinces owned by loser that are occupied by winner's coalition (or all loser provs if total occupation)
                var candidateProvs: [ProvinceID] = []
                if case .conquerProvince(let goalProv) = war.warGoal,
                   world.provinces.owner[goalProv.index] == loser {
                    candidateProvs.append(goalProv)
                }
                let otherOccupied = loserProvs
                    .filter { pid in
                        !candidateProvs.contains(pid) &&
                        (fullyOccupied || (world.provinces.occupiedBy[pid.index].map { war.areEnemies($0, loser) } ?? false))
                    }
                    .sorted { a, b in
                        let aClaim = world.provinces.cores[a.index].contains(winner) || world.provinces.claims[a.index].contains(winner)
                        let bClaim = world.provinces.cores[b.index].contains(winner) || world.provinces.claims[b.index].contains(winner)
                        if aClaim != bClaim { return aClaim }
                        return world.provinces.development[a.index] < world.provinces.development[b.index]
                    }
                candidateProvs.append(contentsOf: otherOccupied)

                var tentativeAE = 0.0
                for pid in candidateProvs {
                    let demand = PeaceDemand.cedeProvince(province: pid, to: winner)
                    let cost = world.diplomacy.peaceDemandCost(demand, loser: loser, war: war, in: world)
                    let testOffer = PeaceOffer(warID: war.id, winner: winner, loser: loser, demands: [demand])
                    let ae = world.diplomacy.aggressiveExpansionForPeace(testOffer, war: war, in: world)
                    if cost <= remainingWS && (demands.isEmpty || tentativeAE + ae <= 48.0) {
                        demands.append(demand)
                        remainingWS -= cost
                        tentativeAE += ae
                    }
                    if demands.count >= 4 { break }
                }

                // 2. War reparations if spare war score
                if remainingWS >= 10 {
                    demands.append(.warReparations)
                    remainingWS -= 10
                }
                // 3. Ducat indemnity if treasury available
                let availDucats = max(0.0, min(200.0, world.countries.treasury[loser.index] * 0.5))
                if remainingWS >= 5 && availDucats >= 25.0 {
                    let rounded = (availDucats / 25.0).rounded(.down) * 25.0
                    let indCost = world.diplomacy.peaceDemandCost(.ducatIndemnity(amount: rounded), loser: loser, war: war, in: world)
                    if indCost <= remainingWS {
                        demands.append(.ducatIndemnity(amount: rounded))
                    }
                }
            }

            let offer = PeaceOffer(warID: war.id, winner: winner, loser: loser, demands: demands)
            if loserHuman {
                // Queue for human player response (replace any prior offer for same war)
                world.diplomacy.pendingPeaceOffers.removeAll { $0.warID == war.id }
                world.diplomacy.pendingPeaceOffers.append(offer)
            } else {
                let eval = world.diplomacy.evaluatePeaceOffer(offer, date: date, in: world)
                if eval.willAccept {
                    _ = world.executePeaceTreaty(offer, date: date)
                } else if isStalemate {
                    let whitePeace = PeaceOffer(warID: war.id, winner: winner, loser: loser, demands: [])
                    let wpEval = world.diplomacy.evaluatePeaceOffer(whitePeace, date: date, in: world)
                    if wpEval.willAccept {
                        _ = world.executePeaceTreaty(whitePeace, date: date)
                    }
                }
            }
        }
    }

    // MARK: - Peacetime Treaties & War Declaration AI

    private static func manageAlliancesAndPacts(
        _ world: inout World,
        country c: CountryID,
        landNeighbors: Set<CountryID>,
        ownedProvinces: [[ProvinceID]],
        date: GameDate,
        random: inout GameRandom
    ) {
        // Break alliances with countries that deeply hate us
        let allies = world.diplomacy.treaties
            .filter { $0.type == .alliance && ($0.first == c || $0.second == c) }
            .map { $0.first == c ? $0.second : $0.first }
            .sorted { $0.index < $1.index }

        for ally in allies {
            if world.diplomacy.opinion(of: ally, by: c) < -45 || world.diplomacy.opinion(of: c, by: ally) < -45 {
                world.diplomacy.removeTreaty(.alliance, between: c, and: ally)
            }
        }

        let used = world.diplomacy.usedRelationSlots(for: c, world: world)
        let maxSlots = world.diplomacy.relationSlots(for: c, world: world)
        guard used < maxSlots else { return }

        // Look at neighbors with positive relations who have slots available
        let candidates = landNeighbors.sorted { $0.index < $1.index }.filter { other in
            guard !world.humanCountries.contains(other),
                  !ownedProvinces[other.index].isEmpty,
                  world.countries.overlord[other.index] == nil,
                  !world.diplomacy.isAtWar(c, other),
                  !world.diplomacy.areAllies(c, other),
                  !world.diplomacy.hasTruce(c, other) else { return false }
            let opMutual = min(world.diplomacy.opinion(of: other, by: c), world.diplomacy.opinion(of: c, by: other))
            return opMutual >= 15
        }

        guard let target = candidates.max(by: { a, b in
            world.diplomacy.opinion(of: a, by: c) < world.diplomacy.opinion(of: b, by: c)
        }) else { return }

        let targetUsed = world.diplomacy.usedRelationSlots(for: target, world: world)
        let targetMax = world.diplomacy.relationSlots(for: target, world: world)
        guard targetUsed < targetMax else { return }

        let sameFamily = world.countries.religion[c.index].family == world.countries.religion[target.index].family
        let roll = Double.random(in: 0..<1, using: &random)
        if sameFamily && roll < 0.35 {
            world.diplomacy.addTreaty(Treaty(first: c, second: target, type: .alliance, note: "AI Alliance \(date.year)"))
        } else if !world.diplomacy.hasTreaty(.nonAggression, between: c, and: target) && roll < 0.25 {
            world.diplomacy.addTreaty(Treaty(first: c, second: target, type: .nonAggression, note: "AI Pact \(date.year)"))
        }
    }

    private static func considerWarDeclaration(
        _ world: inout World,
        attacker: CountryID,
        landNeighbors: Set<CountryID>,
        ownedProvinces: [[ProvinceID]],
        soldiersByCountry: [Int],
        loanCount: Int,
        date: GameDate,
        random: inout GameRandom
    ) {
        // Respect initial 1453 historical wars first (~5 months grace)
        guard date >= GameDate(year: 1453, month: 11, day: 1) else { return }
        guard world.diplomacy.activeWars(for: attacker).isEmpty,
              world.countries.bankruptMonthsLeft[attacker.index] == 0,
              loanCount < 2,
              world.government.stability[attacker.index] >= 0,
              (world.countries.treasury[attacker.index] >= 25.0 ||
               world.countries.lastMonthlyIncome[attacker.index] >= world.countries.lastMonthlyExpenses[attacker.index]),
              soldiersByCountry[attacker.index] >= 1000 else { return }

        // Do not expand recklessly while neighbors have high AE against us
        let maxAE = landNeighbors.reduce(0.0) { cur, nb in
            max(cur, world.diplomacy.aggressiveExpansion(of: attacker, by: nb))
        }
        if maxAE >= 35.0 { return }

        // Evaluate CB targets among adjacent neighbors, prioritizing strongest CB + easiest target
        struct WarCandidate {
            var target: CountryID
            var cb: CasusBelliInstance
            var enemyStrength: Int
            var score: Int
        }
        var candidates: [WarCandidate] = []
        let ourStrength = soldiersByCountry[attacker.index]

        for target in landNeighbors.sorted(by: { $0.index < $1.index }) {
            guard !ownedProvinces[target.index].isEmpty,
                  world.countries.overlord[target.index] != attacker,
                  !world.diplomacy.hasTruce(attacker, target),
                  !world.diplomacy.areAllies(attacker, target),
                  !world.diplomacy.hasTreaty(.nonAggression, between: attacker, and: target),
                  !world.diplomacy.hasTreaty(.guarantee, between: attacker, and: target) else { continue }

            // Avoid starting a coalition war if defender belongs to a coalition against us
            if let coal = world.diplomacy.coalitions[attacker], coal.contains(target) {
                continue
            }

            let cbs = world.diplomacy.availableCasusBelli(attacker: attacker, defender: target, in: world)
                .filter { $0.type != .noCB }
            guard let chosenCB = bestCB(from: cbs) else { continue }

            let check = world.diplomacy.canDeclareWar(
                attacker: attacker,
                defender: target,
                breakTruce: false,
                world: world
            )
            guard case .valid = check else { continue }

            var enemyStrength = soldiersByCountry[target.index]
            for ally in world.countries.ids where ally != attacker && ally != target {
                if world.diplomacy.areAllies(target, ally) || world.diplomacy.hasTreaty(.guarantee, between: ally, and: target) {
                    enemyStrength += soldiersByCountry[ally.index]
                }
            }
            if let ov = world.countries.overlord[target.index] {
                enemyStrength += soldiersByCountry[ov.index]
            }

            let ratioReq = (chosenCB.type == .subjugation || chosenCB.type == .tribute) ? 2.5 : 1.35
            guard Double(ourStrength) >= max(1000.0, Double(enemyStrength) * ratioReq) else { continue }

            let cbScore: Int = switch chosenCB.type {
            case .reconquest: 500
            case .claim: 400
            case .coalition: 350
            case .subjugation: 300
            case .holyWar: 200
            case .tribute: 100
            case .succession: 100
            case .noCB: 0
            }
            let ratioScore = (ourStrength - enemyStrength) / 100
            candidates.append(WarCandidate(target: target, cb: chosenCB, enemyStrength: enemyStrength, score: cbScore + ratioScore))
        }

        guard let best = candidates.max(by: {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.target.index > $1.target.index
        }) else { return }

        let chance: Double = switch best.cb.type {
        case .reconquest, .claim, .coalition: 0.22
        case .holyWar: 0.08
        case .subjugation, .tribute, .succession: 0.04
        case .noCB: 0.0
        }
        guard Double.random(in: 0..<1, using: &random) < chance else { return }

        let target = best.target
        let chosenCB = best.cb
        let result = world.declareWar(
            attacker: attacker,
            defender: target,
            casusBelli: chosenCB.type,
            warGoal: chosenCB.warGoal,
            breakTruce: false,
            date: date
        )
        if case .success(let war) = result {
            for other in world.countries.ids where other != attacker && other != target {
                if world.diplomacy.areAllies(target, other) || world.diplomacy.hasTreaty(.guarantee, between: other, and: target) {
                    _ = world.callToArms(caller: target, ally: other, warID: war.id)
                } else if world.diplomacy.areAllies(attacker, other) && world.diplomacy.activeWars(for: other).isEmpty {
                    _ = world.callToArms(caller: attacker, ally: other, warID: war.id)
                }
            }
            if let latestWar = world.diplomacy.wars.first(where: { $0.id == war.id }) {
                for p in latestWar.attackers + latestWar.defenders {
                    if !world.humanCountries.contains(p) {
                        _ = ArmySystem.raiseAllLevies(&world, p)
                    }
                }
            }
        }
    }

    private static func bestCB(from cbs: [CasusBelliInstance]) -> CasusBelliInstance? {
        let priority: [CasusBelli] = [.reconquest, .coalition, .claim, .subjugation, .holyWar, .tribute]
        for type in priority {
            if let match = cbs.first(where: { $0.type == type }) {
                return match
            }
        }
        return cbs.first
    }

    private static func computeLoanCounts(_ world: World, countryCount: Int) -> [Int] {
        var counts = Array(repeating: 0, count: countryCount)
        for loan in world.finance.loans where loan.country.index < countryCount {
            counts[loan.country.index] += 1
        }
        return counts
    }
}
