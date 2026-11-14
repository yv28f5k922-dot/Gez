import Foundation

/// Zone of Control pathblocking, monthly siege progression, garrison replenishment,
/// and breached-fort Storm Assault mechanics.
public enum SiegeSystem {

    /// Surrender threshold (`roll + modifier + progress >= surrenderThreshold`).
    public static let surrenderThreshold = 15

    // MARK: - Zone of Control

    /// Hostile active forts whose Zone of Control covers `province` for `armyOwner`
    /// (the fort itself if fortified & controlled by an enemy, plus adjacent hostile active forts).
    public static func blockingForts(
        _ world: World,
        for armyOwner: CountryID,
        in province: ProvinceID
    ) -> [ProvinceID] {
        var forts: [ProvinceID] = []
        let checkProvs = [province] + world.provinces.neighbors[province.index]
        for candidate in checkProvs {
            let ci = candidate.index
            guard world.provinces.fortLevel[ci] > 0,
                  world.provinces.fortGarrison[ci] > 0,
                  let ctrl = world.provinces.controller(of: candidate),
                  world.diplomacy.isAtWar(armyOwner, ctrl) else { continue }
            forts.append(candidate)
        }
        return forts.sorted { $0.index < $1.index }
    }

    /// True if `armyOwner` may march from `from` to adjacent province `to` respecting Zone of Control.
    ///
    /// Hostile ZoC rules:
    /// - Entering friendly or allied-controlled territory (or `pathStart`) is always permitted.
    /// - From any province inside hostile ZoC, you may step directly onto a blocking fort itself
    ///   to besiege it, or fall back to friendly territory/`pathStart`, but not deeper into enemy land.
    public static func canStep(
        _ world: World,
        for armyOwner: CountryID,
        from u: ProvinceID,
        to v: ProvinceID,
        pathStart: ProvinceID
    ) -> Bool {
        if v == pathStart { return true }

        // Always allowed to step onto friendly or allied-controlled territory
        if let vCtrl = world.provinces.controller(of: v),
           vCtrl == armyOwner || world.diplomacy.areAllies(armyOwner, vCtrl) {
            return true
        }

        // If `u` is friendly/allied controlled, ZoC does not trap the army yet
        if let uCtrl = world.provinces.controller(of: u),
           uCtrl == armyOwner || world.diplomacy.areAllies(armyOwner, uCtrl) {
            return true
        }

        let fortsInU = blockingForts(world, for: armyOwner, in: u)
        if fortsInU.isEmpty {
            return true
        }

        // Inside a hostile fort's ZoC: may only attack one of the blocking forts directly
        // (and may not bypass an uncaptured fort itself to march past it).
        if fortsInU.contains(u) {
            return fortsInU.contains(v) && v != u
        }
        return fortsInU.contains(v)
    }

    // MARK: - Daily & Monthly Simulation

    /// Advances active sieges daily (starting, abandoning when undermanned, and running 30-day rolls).
    public static func runDaily(
        _ world: inout World,
        date: GameDate,
        random: inout GameRandom
    ) {
        let activeBattleProvs = Set(world.military.battles.map(\.province))

        // 1. Prune invalid sieges (province no longer fortified/enemy-controlled/at war)
        world.military.sieges.removeAll { siege in
            let p = siege.province.index
            guard world.provinces.fortLevel[p] > 0,
                  world.provinces.fortGarrison[p] > 0,
                  let ctrl = world.provinces.controller(of: siege.province) else { return true }
            return !world.diplomacy.isAtWar(siege.besieger, ctrl)
        }

        // 2. Build army lookup once and scan fortified provinces with armies or existing sieges
        var armiesByProvince: [ProvinceID: [ArmyID]] = [:]
        for i in 0..<world.military.armies.count {
            guard world.military.armies.alive[i],
                  !world.military.armies.isRebel[i],
                  !world.military.armies.isRetreating[i],
                  world.military.armies.totalMen(of: ArmyID(Int32(i))) > 0 else { continue }
            armiesByProvince[world.military.armies.province[i], default: []].append(ArmyID(Int32(i)))
        }

        var candidateProvs = Set(armiesByProvince.keys)
        candidateProvs.formUnion(world.military.sieges.map(\.province))

        for pid in candidateProvs.sorted(by: { $0.index < $1.index }) {
            let p = pid.index
            let fortLvl = world.provinces.fortLevel[p]
            guard fortLvl > 0, world.provinces.fortGarrison[p] > 0 else { continue }
            guard !activeBattleProvs.contains(pid) else { continue }
            guard let ctrl = world.provinces.controller(of: pid) else { continue }

            let armiesHere = (armiesByProvince[pid] ?? []).filter { aid in
                let i = Int(aid.rawValue)
                return world.diplomacy.isAtWar(world.military.armies.owner[i], ctrl)
            }.sorted { $0.rawValue < $1.rawValue }

            // Sum hostile men grouped by country
            var menByCountry: [CountryID: Int] = [:]
            var hostileArmiesHere: [ArmyID] = []
            for aid in armiesHere {
                let owner = world.military.armies.owner[Int(aid.rawValue)]
                menByCountry[owner, default: 0] += world.military.armies.totalMen(of: aid)
                hostileArmiesHere.append(aid)
            }

            let totalHostileMen = menByCountry.values.reduce(0, +)
            let minRequired = fortLvl * 1000

            if totalHostileMen < minRequired {
                // Under-strength or abandoned: remove siege if completely vacated
                if totalHostileMen == 0 {
                    world.military.sieges.removeAll { $0.province == pid }
                }
                continue
            }

            // Pick lead besieger deterministically (existing besieger if still present, else largest)
            let leadBesieger: CountryID
            if let existing = world.military.siege(in: pid), (menByCountry[existing.besieger] ?? 0) > 0 {
                leadBesieger = existing.besieger
            } else {
                leadBesieger = menByCountry.max { a, b in
                    if a.value != b.value { return a.value < b.value }
                    return a.key.index > b.key.index
                }!.key
            }

            // Capture coastal undefended vs blockaded state (landlocked = true)
            let isLandlockedOrBlockaded = !world.provinces.isCoastal[p]

            if let idx = world.military.sieges.firstIndex(where: { $0.province == pid }) {
                var siege = world.military.sieges[idx]
                siege.phaseDaysRemaining -= 1
                if siege.phaseDaysRemaining <= 0 {
                    resolveSiegePhase(
                        &world,
                        siege: &siege,
                        hostileArmies: hostileArmiesHere,
                        fortLevel: fortLvl,
                        random: &random
                    )
                    if siege.lastOutcome == .surrender {
                        world.military.sieges.remove(at: idx)
                        continue
                    }
                    siege.phaseDaysRemaining = 30
                }
                world.military.sieges[idx] = siege
            } else {
                world.military.sieges.append(Siege(
                    province: pid,
                    besieger: leadBesieger,
                    startDate: date,
                    progress: 0,
                    breached: false,
                    blockaded: isLandlockedOrBlockaded,
                    phaseDaysRemaining: 30
                ))
            }
        }
    }

    /// Replenishes garrisons monthly in unbesieged provinces.
    public static func runMonthly(_ world: inout World) {
        let besiegedProvs = Set(world.military.sieges.map(\.province))
        for p in 0..<world.provinces.count {
            let pid = ProvinceID(p)
            guard world.provinces.fortLevel[p] > 0, !besiegedProvs.contains(pid) else { continue }
            let cap = world.provinces.maxGarrison(of: pid)
            if world.provinces.fortGarrison[p] < cap {
                world.provinces.fortGarrison[p] = min(cap, world.provinces.fortGarrison[p] + 100)
            }
        }
    }

    // MARK: - Siege Phase Roll

    private static func resolveSiegePhase(
        _ world: inout World,
        siege: inout Siege,
        hostileArmies: [ArmyID],
        fortLevel: Int,
        random: inout GameRandom
    ) {
        let pid = siege.province
        let p = pid.index

        // Compute modifiers
        var artRegiments = 0
        var bestMartial = 0
        for aid in hostileArmies {
            let i = Int(aid.rawValue)
            for r in world.military.armies.regiments[i] where r.men > 0 {
                let ut = world.military.unit(r.type)
                if ut.category == .artillery { artRegiments += 1 }
            }
            if let cmd = world.military.armies.commander[i] {
                bestMartial = max(bestMartial, world.people.characters.skills[cmd.index][Skill.martial.rawValue])
            }
        }

        let artBonus = min(5, artRegiments)
        let cmdBonus = bestMartial / 4
        let breachBonus = siege.breached ? 2 : 0
        let coastalPenalty = (world.provinces.isCoastal[p] && !siege.blockaded) ? -2 : 0
        let fortPenalty = -fortLevel

        let modifier = max(-7, artBonus + cmdBonus + breachBonus + coastalPenalty + fortPenalty)
        let roll = Int.random(in: 1...14, using: &random)
        siege.lastRoll = roll
        siege.lastModifier = modifier

        let total = roll + modifier + siege.progress
        let garrison = world.provinces.fortGarrison[p]

        if total >= surrenderThreshold || garrison <= 0 {
            siege.lastOutcome = .surrender
            captureFort(&world, province: pid, capturer: siege.besieger)
            return
        }

        if roll == 1 {
            siege.lastOutcome = .diseaseOutbreak
            applyDiseaseLosses(&world, armies: hostileArmies, fraction: 0.05)
            return
        }

        // Wall breach on natural high roll (13-14) or with artillery support at 12+
        if !siege.breached && (roll >= 13 || (roll + artBonus >= 14 && artBonus > 0)) {
            siege.breached = true
            siege.progress += 2
            siege.lastOutcome = .wallBreach
            return
        }

        switch total {
        case ...4:
            siege.lastOutcome = .suppliesHolding
        case 5...7:
            siege.progress += 1
            let loss = max(25, Int(Double(garrison) * 0.05))
            world.provinces.fortGarrison[p] = max(0, garrison - loss)
            siege.lastOutcome = .foodShortage
        case 8...10:
            siege.progress += 2
            let loss = max(50, Int(Double(garrison) * 0.10))
            world.provinces.fortGarrison[p] = max(0, garrison - loss)
            siege.lastOutcome = .waterShortage
        case 11...13:
            siege.progress += 2
            let loss = max(75, Int(Double(garrison) * 0.15))
            world.provinces.fortGarrison[p] = max(0, garrison - loss)
            siege.lastOutcome = .defenderDesertion
        default:
            if !siege.breached {
                siege.breached = true
                siege.progress += 2
                siege.lastOutcome = .wallBreach
            } else {
                siege.progress += 3
                let loss = max(100, Int(Double(garrison) * 0.20))
                world.provinces.fortGarrison[p] = max(0, garrison - loss)
                siege.lastOutcome = .defenderDesertion
            }
        }

        if world.provinces.fortGarrison[p] <= 0 {
            siege.lastOutcome = .surrender
            captureFort(&world, province: pid, capturer: siege.besieger)
        }
    }

    // MARK: - Storm Assault

    /// Orders a high-casualty Storm Assault against a breached fort (`siege.breached == true`).
    @discardableResult
    public static func assaultFort(
        _ world: inout World,
        province pid: ProvinceID,
        attacker: CountryID,
        random: inout GameRandom
    ) -> AssaultResult {
        let p = pid.index
        guard world.provinces.fortLevel[p] > 0 else {
            return AssaultResult(captured: false, attackerLosses: 0, garrisonLosses: 0, remainingGarrison: 0, refusalReason: "Province has no fort.")
        }
        guard let siegeIdx = world.military.sieges.firstIndex(where: { $0.province == pid && $0.besieger == attacker }) else {
            return AssaultResult(captured: false, attackerLosses: 0, garrisonLosses: 0, remainingGarrison: world.provinces.fortGarrison[p], refusalReason: "No active siege led by attacker.")
        }
        let siege = world.military.sieges[siegeIdx]
        guard siege.breached else {
            return AssaultResult(captured: false, attackerLosses: 0, garrisonLosses: 0, remainingGarrison: world.provinces.fortGarrison[p], refusalReason: "Walls must be breached before storming.")
        }
        guard world.military.battle(in: pid) == nil else {
            return AssaultResult(captured: false, attackerLosses: 0, garrisonLosses: 0, remainingGarrison: world.provinces.fortGarrison[p], refusalReason: "Field battle in progress.")
        }

        let besiegingArmies = world.military.armies(in: pid).filter { aid in
            let i = Int(aid.rawValue)
            return !world.military.armies.isRebel[i]
                && !world.military.armies.isRetreating[i]
                && world.military.armies.owner[i] == attacker
        }.sorted { $0.rawValue < $1.rawValue }

        let totalAttackers = besiegingArmies.reduce(0) { $0 + world.military.armies.totalMen(of: $1) }
        guard totalAttackers >= 500 else {
            return AssaultResult(captured: false, attackerLosses: 0, garrisonLosses: 0, remainingGarrison: world.provinces.fortGarrison[p], refusalReason: "Insufficient besiegers to assault.")
        }

        let startGarrison = max(1, world.provinces.fortGarrison[p])
        let rollMod = Double(Int.random(in: 7...13, using: &random)) / 10.0

        // Attacker shock kills defenders, but fortified defenders inflict heavy casualties (1.5x per soldier)
        let garrisonLosses = min(startGarrison, max(100, Int(Double(totalAttackers) * 0.25 * rollMod)))
        let attackerLossesRaw = Int(Double(startGarrison) * 0.55 / rollMod)
        let attackerLosses = min(totalAttackers, max(50, attackerLossesRaw))

        applyProportionalLosses(&world, armies: besiegingArmies, totalLoss: attackerLosses, totalPool: totalAttackers)
        let remainingGarrison = max(0, startGarrison - garrisonLosses)
        world.provinces.fortGarrison[p] = remainingGarrison

        if remainingGarrison == 0 {
            captureFort(&world, province: pid, capturer: attacker)
            world.military.sieges.remove(at: siegeIdx)
            return AssaultResult(captured: true, attackerLosses: attackerLosses, garrisonLosses: garrisonLosses, remainingGarrison: 0)
        } else {
            // Assault weakened garrison even if it held
            return AssaultResult(captured: false, attackerLosses: attackerLosses, garrisonLosses: garrisonLosses, remainingGarrison: remainingGarrison)
        }
    }

    // MARK: - Helpers

    private static func captureFort(_ world: inout World, province pid: ProvinceID, capturer: CountryID) {
        let p = pid.index
        let cap = world.provinces.maxGarrison(of: pid)
        if world.provinces.owner[p] == capturer {
            // Liberated home fort
            world.provinces.occupiedBy[p] = nil
        } else {
            world.provinces.occupiedBy[p] = capturer
        }
        world.provinces.fortGarrison[p] = max(100, cap / 5)
    }

    private static func applyDiseaseLosses(_ world: inout World, armies: [ArmyID], fraction: Double) {
        for aid in armies {
            let i = Int(aid.rawValue)
            for r in world.military.armies.regiments[i].indices {
                let men = world.military.armies.regiments[i][r].men
                let loss = max(1, Int((Double(men) * fraction).rounded()))
                world.military.armies.regiments[i][r].men = max(0, men - loss)
            }
            world.military.armies.regiments[i].removeAll { $0.men <= 0 }
            if world.military.armies.totalMen(of: aid) == 0 {
                world.military.armies.remove(aid)
            }
        }
    }

    private static func applyProportionalLosses(_ world: inout World, armies: [ArmyID], totalLoss: Int, totalPool: Int) {
        guard totalPool > 0, totalLoss > 0 else { return }
        let ratio = min(1.0, Double(totalLoss) / Double(totalPool))
        applyDiseaseLosses(&world, armies: armies, fraction: ratio)
    }
}
