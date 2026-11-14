import Foundation

/// Tuning constants for multi-day field battles and short unfortified province occupation.
public enum BattleModel {
    /// Days per combat phase before alternating between Fire and Shock.
    public static let phaseDurationDays = 3
    /// Cavalry flanking damage bonus when one side has more active regiments than the opponent.
    public static let cavalryFlankingBonus = 0.35
    /// Attacker dice penalty when crossing a major river border into battle.
    public static let riverCrossingPenalty = -1
    /// Days required for an invading army to occupy an unfortified enemy province (fortLevel == 0).
    public static let unfortifiedTakeoverDays = 10
    /// Days required for a friendly army to liberate an unfortified occupied province.
    public static let liberationDays = 5
    /// Minimum daily casualty factor per unit of effective attack power.
    public static let baseCasualtyScale = 6.5

    /// Fire phase effectiveness multiplier per unit category and key.
    public static func fireMultiplier(unitKey: String, category: UnitCategory) -> Double {
        switch category {
        case .artillery:
            return 1.60
        case .ranged:
            return 1.35
        case .cavalry:
            return unitKey == "horse_archers" ? 1.15 : 0.25
        case .infantry:
            return unitKey == "janissaries" ? 0.85 : 0.45
        }
    }

    /// Shock phase effectiveness multiplier per unit category and key.
    public static func shockMultiplier(unitKey: String, category: UnitCategory) -> Double {
        switch category {
        case .cavalry:
            return 1.50
        case .infantry:
            return 1.35
        case .ranged:
            return unitKey == "war_wagons" ? 0.70 : 0.45
        case .artillery:
            return 0.25
        }
    }

    /// Attacker dice roll penalty from defending province terrain.
    public static func terrainAttackerPenalty(_ terrain: Terrain) -> Int {
        switch terrain {
        case .mountains:
            return -2
        case .hills, .forest, .marsh:
            return -1
        case .farmland, .plains, .desert, .steppe:
            return 0
        }
    }
}

/// Phase 7 Step 3: Auto-resolved multi-day field battles (Fire & Shock phases)
/// and short takeover occupation of unfortified provinces.
public enum BattleSystem {

    /// Runs daily battle initiation, combat resolution, shattered retreats,
    /// and unfortified province takeover progress.
    public static func runDaily(_ world: inout World, date: GameDate, random: inout GameRandom) {
        detectAndReinforceBattles(&world, date: date, random: &random)
        advanceActiveBattles(&world, date: date, random: &random)
        advanceUnfortifiedOccupation(&world)
    }

    // MARK: - 1. Battle Initiation & Reinforcement

    private static func detectAndReinforceBattles(
        _ world: inout World,
        date: GameDate,
        random: inout GameRandom
    ) {
        var armiesByProvince: [ProvinceID: [ArmyID]] = [:]
        for i in 0..<world.military.armies.count {
            guard world.military.armies.alive[i],
                  !world.military.armies.isRebel[i],
                  !world.military.armies.isRetreating[i],
                  world.military.armies.totalMen(of: ArmyID(Int32(i))) > 0 else { continue }
            let pid = world.military.armies.province[i]
            armiesByProvince[pid, default: []].append(ArmyID(Int32(i)))
        }

        for pid in armiesByProvince.keys.sorted(by: { $0.index < $1.index }) {
            let here = armiesByProvince[pid]!.sorted { $0.rawValue < $1.rawValue }
            guard here.count >= 2 else { continue }

            if let bIdx = world.military.battles.firstIndex(where: { $0.province == pid }) {
                reinforceExistingBattle(&world, battleIndex: bIdx, armiesHere: here)
            } else {
                tryStartBattle(&world, in: pid, armiesHere: here, date: date, random: &random)
            }
        }
    }

    private static func reinforceExistingBattle(
        _ world: inout World,
        battleIndex: Int,
        armiesHere: [ArmyID]
    ) {
        var battle = world.military.battles[battleIndex]
        for aid in armiesHere {
            guard !battle.attackers.contains(aid), !battle.defenders.contains(aid) else { continue }
            let idx = Int(aid.rawValue)
            let owner = world.military.armies.owner[idx]

            let joinsAttackers = owner == battle.attackerCountry
                || world.diplomacy.isAtWar(owner, battle.defenderCountry)
                || world.diplomacy.areAllies(owner, battle.attackerCountry)
            let joinsDefenders = owner == battle.defenderCountry
                || world.diplomacy.isAtWar(owner, battle.attackerCountry)
                || world.diplomacy.areAllies(owner, battle.defenderCountry)

            if joinsAttackers && !joinsDefenders {
                battle.attackers.append(aid)
                battle.attackerInitialMen += world.military.armies.totalMen(of: aid)
                world.military.armies.path[idx].removeAll()
                world.military.armies.moveStepDays[idx] = 0
            } else if joinsDefenders && !joinsAttackers {
                battle.defenders.append(aid)
                battle.defenderInitialMen += world.military.armies.totalMen(of: aid)
                world.military.armies.path[idx].removeAll()
                world.military.armies.moveStepDays[idx] = 0
            }
        }
        world.military.battles[battleIndex] = battle
    }

    private static func tryStartBattle(
        _ world: inout World,
        in province: ProvinceID,
        armiesHere: [ArmyID],
        date: GameDate,
        random: inout GameRandom
    ) {
        // Find any pair at war.
        var foundPair: (ArmyID, ArmyID)?
        outer: for aIdx in 0..<armiesHere.count {
            let a = armiesHere[aIdx]
            let ownerA = world.military.armies.owner[Int(a.rawValue)]
            for bIdx in (aIdx + 1)..<armiesHere.count {
                let b = armiesHere[bIdx]
                let ownerB = world.military.armies.owner[Int(b.rawValue)]
                if world.diplomacy.isAtWar(ownerA, ownerB) {
                    foundPair = (a, b)
                    break outer
                }
            }
        }
        guard let (first, second) = foundPair else { return }

        let controller = world.provinces.controller(of: province)
        let owner1 = world.military.armies.owner[Int(first.rawValue)]
        let owner2 = world.military.armies.owner[Int(second.rawValue)]

        // Determine defender side: prioritize province controller or stationary troops.
        let defenderCountry: CountryID
        let attackerCountry: CountryID
        if let ctrl = controller, owner1 == ctrl || world.diplomacy.areAllies(owner1, ctrl) {
            defenderCountry = owner1
            attackerCountry = owner2
        } else if let ctrl = controller, owner2 == ctrl || world.diplomacy.areAllies(owner2, ctrl) {
            defenderCountry = owner2
            attackerCountry = owner1
        } else if world.military.armies.previousProvince[Int(first.rawValue)] == nil
                    && world.military.armies.previousProvince[Int(second.rawValue)] != nil {
            defenderCountry = owner1
            attackerCountry = owner2
        } else if world.military.armies.previousProvince[Int(second.rawValue)] == nil
                    && world.military.armies.previousProvince[Int(first.rawValue)] != nil {
            defenderCountry = owner2
            attackerCountry = owner1
        } else {
            defenderCountry = owner1
            attackerCountry = owner2
        }

        var attackers: [ArmyID] = []
        var defenders: [ArmyID] = []
        for aid in armiesHere {
            let i = Int(aid.rawValue)
            let owner = world.military.armies.owner[i]
            if owner == defenderCountry || (!world.diplomacy.isAtWar(owner, defenderCountry) && world.diplomacy.isAtWar(owner, attackerCountry)) {
                defenders.append(aid)
                world.military.armies.path[i].removeAll()
                world.military.armies.moveStepDays[i] = 0
            } else if owner == attackerCountry || world.diplomacy.isAtWar(owner, defenderCountry) {
                attackers.append(aid)
                world.military.armies.path[i].removeAll()
                world.military.armies.moveStepDays[i] = 0
            }
        }
        guard !attackers.isEmpty, !defenders.isEmpty else { return }

        let isRiver = attackers.contains { aid in
            guard let prev = world.military.armies.previousProvince[Int(aid.rawValue)] else { return false }
            return world.isRiverBorder(prev, province)
        }

        let attMen = attackers.reduce(0) { $0 + world.military.armies.totalMen(of: $1) }
        let defMen = defenders.reduce(0) { $0 + world.military.armies.totalMen(of: $1) }

        let attRoll = Int.random(in: 0...9, using: &random)
        let defRoll = Int.random(in: 0...9, using: &random)

        let id = "battle_\(province.index)_\(date.year)_\(date.month)_\(date.day)_\(world.military.battles.count)"
        let battle = Battle(
            id: id,
            province: province,
            startDate: date,
            dayCount: 0,
            attackers: attackers,
            defenders: defenders,
            attackerCountry: attackerCountry,
            defenderCountry: defenderCountry,
            currentPhase: .fire,
            phaseDay: 1,
            isRiverCrossing: isRiver,
            attackerInitialMen: attMen,
            defenderInitialMen: defMen,
            attackerLosses: 0,
            defenderLosses: 0,
            attackerDiceRoll: attRoll,
            defenderDiceRoll: defRoll
        )
        world.military.battles.append(battle)
    }

    // MARK: - 2. Multi-Day Fire & Shock Resolution

    private struct SideCombatStats {
        var attack: Double
        var avgDefence: Double
        var activeRegiments: Int
        var activeMen: Int
        var highestMorale: Double
        var maxMartial: Int
        var discipline: Double
    }

    private static func computeSideStats(
        world: World,
        armies: [ArmyID],
        primaryCountry: CountryID,
        phase: BattlePhase,
        hasFlankingAdvantage: Bool
    ) -> SideCombatStats {
        var attack = 0.0
        var defSum = 0.0
        var activeRegs = 0
        var activeMen = 0
        var highestMorale = 0.0
        var maxMartial = 0

        for aid in armies {
            let i = Int(aid.rawValue)
            guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { continue }
            if let cmd = world.military.armies.commander[i], world.people.characters.isAlive(cmd) {
                let m = world.people.characters.skill(cmd, .martial)
                if m > maxMartial { maxMartial = m }
            }
            for reg in world.military.armies.regiments[i] where reg.men > 0 && reg.morale > 0.05 {
                let unit = world.military.unit(reg.type)
                let menRatio = Double(reg.men) / Double(max(1, unit.maxMen))
                var phaseMult: Double
                switch phase {
                case .fire:
                    phaseMult = BattleModel.fireMultiplier(unitKey: unit.key, category: unit.category)
                case .shock:
                    phaseMult = BattleModel.shockMultiplier(unitKey: unit.key, category: unit.category)
                }
                if unit.category == .cavalry && hasFlankingAdvantage {
                    phaseMult += BattleModel.cavalryFlankingBonus
                }
                attack += menRatio * unit.attack * phaseMult
                defSum += unit.defence
                activeRegs += 1
                activeMen += reg.men
                if reg.morale > highestMorale { highestMorale = reg.morale }
            }
        }

        let avgDefence = activeRegs > 0 ? defSum / Double(activeRegs) : 5.0
        let quality = max(0.5, 1.0 + world.government.modifier(primaryCountry, .armyQuality) + ArmySystem.marshalBonus(world, primaryCountry) * 0.5)
        return SideCombatStats(
            attack: attack,
            avgDefence: avgDefence,
            activeRegiments: activeRegs,
            activeMen: activeMen,
            highestMorale: highestMorale,
            maxMartial: maxMartial,
            discipline: quality
        )
    }

    private static func activeRegimentCount(world: World, armies: [ArmyID]) -> Int {
        var count = 0
        for aid in armies {
            let i = Int(aid.rawValue)
            guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { continue }
            for reg in world.military.armies.regiments[i] where reg.men > 0 && reg.morale > 0.05 {
                count += 1
            }
        }
        return count
    }

    private static func advanceActiveBattles(
        _ world: inout World,
        date: GameDate,
        random: inout GameRandom
    ) {
        var remainingBattles: [Battle] = []

        for var battle in world.military.battles {
            battle.dayCount += 1
            if battle.dayCount > 1 {
                battle.phaseDay += 1
                if battle.phaseDay > BattleModel.phaseDurationDays {
                    battle.phaseDay = 1
                    battle.currentPhase = (battle.currentPhase == .fire) ? .shock : .fire
                    battle.attackerDiceRoll = Int.random(in: 0...9, using: &random)
                    battle.defenderDiceRoll = Int.random(in: 0...9, using: &random)
                }
            }

            let attRegCount = activeRegimentCount(world: world, armies: battle.attackers)
            let defRegCount = activeRegimentCount(world: world, armies: battle.defenders)

            let attStats = computeSideStats(
                world: world,
                armies: battle.attackers,
                primaryCountry: battle.attackerCountry,
                phase: battle.currentPhase,
                hasFlankingAdvantage: attRegCount > defRegCount
            )
            let defStats = computeSideStats(
                world: world,
                armies: battle.defenders,
                primaryCountry: battle.defenderCountry,
                phase: battle.currentPhase,
                hasFlankingAdvantage: defRegCount > attRegCount
            )

            let terrainPen = BattleModel.terrainAttackerPenalty(world.provinces.terrain[battle.province.index])
            let riverPen = battle.isRiverCrossing ? BattleModel.riverCrossingPenalty : 0

            let attEffRoll = Double(battle.attackerDiceRoll + (attStats.maxMartial / 3) + terrainPen + riverPen)
            let defEffRoll = Double(battle.defenderDiceRoll + (defStats.maxMartial / 3))

            let attRollMult = max(0.45, 1.0 + (attEffRoll - 4.5) * 0.08)
            let defRollMult = max(0.45, 1.0 + (defEffRoll - 4.5) * 0.08)

            let attPower = attStats.attack * attRollMult * attStats.discipline
            let defPower = defStats.attack * defRollMult * defStats.discipline

            let defMitigation = 10.0 / (5.0 + defStats.avgDefence)
            let attMitigation = 10.0 / (5.0 + attStats.avgDefence)

            let targetDefLosses = Int((attPower * defMitigation * BattleModel.baseCasualtyScale / defStats.discipline).rounded())
            let targetAttLosses = Int((defPower * attMitigation * BattleModel.baseCasualtyScale / attStats.discipline).rounded())

            let actualDefLosses = applyCombatDamage(
                &world,
                armies: battle.defenders,
                targetLosses: targetDefLosses,
                moraleDamage: computeMoraleDamage(
                    losses: targetDefLosses,
                    totalMen: defStats.activeMen,
                    enemyPower: attPower,
                    ownPower: defPower
                )
            )
            let actualAttLosses = applyCombatDamage(
                &world,
                armies: battle.attackers,
                targetLosses: targetAttLosses,
                moraleDamage: computeMoraleDamage(
                    losses: targetAttLosses,
                    totalMen: attStats.activeMen,
                    enemyPower: defPower,
                    ownPower: attPower
                )
            )

            battle.defenderLosses += actualDefLosses
            battle.attackerLosses += actualAttLosses

            let attAfter = activeCombatMenAndMaxMorale(world: world, armies: battle.attackers)
            let defAfter = activeCombatMenAndMaxMorale(world: world, armies: battle.defenders)

            let attBroken = attAfter.men == 0 || attAfter.maxMorale <= 0.1
            let defBroken = defAfter.men == 0 || defAfter.maxMorale <= 0.1

            if !attBroken && !defBroken {
                remainingBattles.append(battle)
            } else {
                // Defender holds tie if both break on the same day.
                let attackerWon = defBroken && !attBroken
                concludeBattle(&world, battle: battle, attackerWon: attackerWon, date: date)
            }
        }

        world.military.battles = remainingBattles
    }

    private static func computeMoraleDamage(
        losses: Int,
        totalMen: Int,
        enemyPower: Double,
        ownPower: Double
    ) -> Double {
        let lossRatio = Double(losses) / Double(max(1, totalMen))
        let powerRatio = enemyPower / max(1.0, ownPower)
        let dmg = 0.14 + lossRatio * 4.0 + powerRatio * 0.10
        return max(0.08, min(0.85, dmg))
    }

    private static func applyCombatDamage(
        _ world: inout World,
        armies: [ArmyID],
        targetLosses: Int,
        moraleDamage: Double
    ) -> Int {
        var totalFightingMen = 0
        for aid in armies {
            let i = Int(aid.rawValue)
            guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { continue }
            for reg in world.military.armies.regiments[i] where reg.men > 0 && reg.morale > 0.05 {
                totalFightingMen += reg.men
            }
        }
        guard totalFightingMen > 0 else { return 0 }

        let totalLoss = min(totalFightingMen, max(0, targetLosses))
        var appliedLosses = 0

        for aid in armies {
            let i = Int(aid.rawValue)
            guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { continue }
            var surviving: [Regiment] = []
            for var reg in world.military.armies.regiments[i] {
                if reg.men > 0 && reg.morale > 0.05 {
                    let share = Double(reg.men) / Double(totalFightingMen)
                    let loss = min(reg.men, Int((Double(totalLoss) * share).rounded()))
                    reg.men -= loss
                    appliedLosses += loss
                    reg.morale = max(0.0, reg.morale - moraleDamage)
                }
                if reg.men > 0 {
                    surviving.append(reg)
                }
            }
            if surviving.isEmpty {
                world.military.armies.remove(aid)
            } else {
                world.military.armies.regiments[i] = surviving
            }
        }
        return appliedLosses
    }

    private static func activeCombatMenAndMaxMorale(world: World, armies: [ArmyID]) -> (men: Int, maxMorale: Double) {
        var men = 0
        var maxM = 0.0
        for aid in armies {
            let i = Int(aid.rawValue)
            guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { continue }
            for reg in world.military.armies.regiments[i] where reg.men > 0 {
                men += reg.men
                if reg.morale > maxM { maxM = reg.morale }
            }
        }
        return (men, maxM)
    }

    // MARK: - Battle Conclusion & Shattered Retreat

    private static func concludeBattle(
        _ world: inout World,
        battle: Battle,
        attackerWon: Bool,
        date: GameDate
    ) {
        let winnerCountry = attackerWon ? battle.attackerCountry : battle.defenderCountry
        let winningArmies = attackerWon ? battle.attackers : battle.defenders
        let losingArmies = attackerWon ? battle.defenders : battle.attackers

        let winMen = winningArmies.reduce(0) { $0 + world.military.armies.totalMen(of: $1) }
        let loseMen = losingArmies.reduce(0) { $0 + world.military.armies.totalMen(of: $1) }

        // Stackwipe if eliminated or overrun in <= 3 days at 8:1 disadvantage
        let isOverrun = loseMen > 0 && battle.dayCount <= 3 && winMen >= loseMen * 8
        let wasStackwipe = (loseMen == 0) || isOverrun

        if wasStackwipe {
            for aid in losingArmies {
                world.military.armies.remove(aid)
            }
        } else {
            // Shattered retreat to safe friendly province
            for aid in losingArmies {
                let i = Int(aid.rawValue)
                guard i >= 0 && i < world.military.armies.count && world.military.armies.alive[i] else { continue }
                let owner = world.military.armies.owner[i]
                // Minimum floor morale for retreat survival
                for rIdx in world.military.armies.regiments[i].indices {
                    world.military.armies.regiments[i][rIdx].morale = max(0.5, world.military.armies.regiments[i][rIdx].morale)
                }
                let retreatProv = findRetreatProvince(world: world, for: owner, from: battle.province)
                if retreatProv != battle.province {
                    world.military.armies.isRetreating[i] = true
                    ArmySystem.orderMove(&world, army: aid, to: retreatProv)
                }
            }
        }

        // Update War battle warScore (clamped -0.40 ... +0.40)
        if var war = world.diplomacy.activeWar(between: battle.attackerCountry, and: battle.defenderCountry) {
            let totalCas = Double(battle.attackerLosses + battle.defenderLosses)
            let delta = min(0.15, (totalCas / 25_000.0) * 0.12 + 0.025)
            let sign = war.isAttacker(winnerCountry) ? 1.0 : -1.0
            war.battleWarScore = max(-0.40, min(0.40, war.battleWarScore + sign * delta))
            war.warScore = max(-1.0, min(1.0, war.battleWarScore))
            world.diplomacy.updateWar(war)
        }

        // Archive BattleReport
        let report = BattleReport(
            id: battle.id,
            province: battle.province,
            startDate: battle.startDate,
            endDate: date,
            attackerCountry: battle.attackerCountry,
            defenderCountry: battle.defenderCountry,
            winner: winnerCountry,
            attackerInitialMen: battle.attackerInitialMen,
            defenderInitialMen: battle.defenderInitialMen,
            attackerLosses: battle.attackerLosses,
            defenderLosses: battle.defenderLosses,
            daysFought: battle.dayCount,
            wasStackwipe: wasStackwipe
        )
        world.military.recentBattles.append(report)
        if world.military.recentBattles.count > 50 {
            world.military.recentBattles.removeFirst(world.military.recentBattles.count - 50)
        }

        // Record in court chronicles
        let pName = world.provinces.name[battle.province.index]
        let winName = world.countries.name[winnerCountry.index]
        let loseCountry = attackerWon ? battle.defenderCountry : battle.attackerCountry
        let summary = "\(winName) wins the Battle of \(pName) (\(battle.dayCount) days; \(battle.attackerLosses) attacker / \(battle.defenderLosses) defender casualties)."
        world.people.record(date, winnerCountry, summary)
        world.people.record(date, loseCountry, summary)
    }

    private static func findRetreatProvince(
        world: World,
        for country: CountryID,
        from start: ProvinceID
    ) -> ProvinceID {
        func hasEnemyArmy(in pid: ProvinceID) -> Bool {
            world.military.armies(in: pid).contains { aid in
                let idx = Int(aid.rawValue)
                return !world.military.armies.isRebel[idx]
                    && world.diplomacy.isAtWar(country, world.military.armies.owner[idx])
            }
        }

        // BFS up to 4 hops to find safe owned province ideally 2-4 hops away
        var visited: Set<ProvinceID> = [start]
        var queue: [(ProvinceID, Int)] = [(start, 0)]
        var candidates: [(ProvinceID, Int)] = []

        var head = 0
        while head < queue.count && head < 80 {
            let (cur, dist) = queue[head]
            head += 1
            if dist >= 1 && dist <= 4 {
                if world.provinces.owner[cur.index] == country
                    && world.provinces.occupiedBy[cur.index] == nil
                    && !hasEnemyArmy(in: cur) {
                    candidates.append((cur, dist))
                }
            }
            if dist < 4 {
                for nb in world.provinces.neighbors[cur.index].sorted(by: { $0.index < $1.index }) {
                    if visited.insert(nb).inserted {
                        queue.append((nb, dist + 1))
                    }
                }
            }
        }

        // Prefer 2+ hops away, else closest safe province
        if let farSafe = candidates.filter({ $0.1 >= 2 }).sorted(by: { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0.index < $1.0.index) }).first {
            return farSafe.0
        }
        if let nearSafe = candidates.first {
            return nearSafe.0
        }
        if let cap = world.countries.capital[country.index],
           cap != start,
           world.provinces.occupiedBy[cap.index] == nil,
           !hasEnemyArmy(in: cap) {
            return cap
        }
        if let anyOwned = world.provinces(ownedBy: country).first(where: { $0 != start && !hasEnemyArmy(in: $0) }) {
            return anyOwned
        }
        return world.provinces.neighbors[start.index].first(where: { !hasEnemyArmy(in: $0) }) ?? start
    }

    // MARK: - 3. Unfortified Province Takeover Occupation

    private static func advanceUnfortifiedOccupation(_ world: inout World) {
        let activeBattleProvs = Set(world.military.battles.map(\.province))

        for p in 0..<world.provinces.count {
            let pid = ProvinceID(p)
            if activeBattleProvs.contains(pid) { continue }

            // Collect non-rebel, non-retreating armies standing in `pid`
            let armiesHere = world.military.armies(in: pid).filter { aid in
                let i = Int(aid.rawValue)
                return !world.military.armies.isRebel[i] && !world.military.armies.isRetreating[i]
            }.sorted { $0.rawValue < $1.rawValue }

            if armiesHere.isEmpty || world.provinces.fortLevel[p] > 0 {
                world.provinces.occupationProgressDays[p] = 0
                world.provinces.occupationTarget[p] = nil
                continue
            }

            guard let controller = world.provinces.controller(of: pid) else {
                world.provinces.occupationProgressDays[p] = 0
                world.provinces.occupationTarget[p] = nil
                continue
            }

            // If any defending/friendly army stands here, hostile takeover cannot progress.
            let defenderPresent = armiesHere.contains { aid in
                let owner = world.military.armies.owner[Int(aid.rawValue)]
                return owner == controller || world.diplomacy.areAllies(owner, controller) || !world.diplomacy.isAtWar(owner, controller)
            }
            if defenderPresent {
                world.provinces.occupationProgressDays[p] = 0
                world.provinces.occupationTarget[p] = nil
                continue
            }

            // Pick the occupier (owner of first hostile army here).
            let occupier = world.military.armies.owner[Int(armiesHere[0].rawValue)]
            let isLiberation = (world.provinces.occupiedBy[p] != nil)
                && (world.provinces.owner[p] == occupier
                    || (world.provinces.owner[p].map { world.diplomacy.areAllies($0, occupier) } ?? false))

            let requiredDays = isLiberation ? BattleModel.liberationDays : BattleModel.unfortifiedTakeoverDays

            if world.provinces.occupationTarget[p] != occupier {
                world.provinces.occupationTarget[p] = occupier
                world.provinces.occupationProgressDays[p] = 0
            }

            world.provinces.occupationProgressDays[p] += 1
            if world.provinces.occupationProgressDays[p] >= requiredDays {
                if isLiberation {
                    world.provinces.occupiedBy[p] = nil
                } else {
                    world.provinces.occupiedBy[p] = occupier
                }
                world.provinces.occupationTarget[p] = nil
                world.provinces.occupationProgressDays[p] = 0
            }
        }
    }
}
