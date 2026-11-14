import Foundation

/// An instance of an available Casus Belli with its associated war goal and targets.
public struct CasusBelliInstance: Sendable, Equatable {
    public var type: CasusBelli
    public var target: CountryID
    public var warGoal: WarGoal
    public var targetProvince: ProvinceID?
    public var name: String
    public var description: String

    public init(
        type: CasusBelli,
        target: CountryID,
        warGoal: WarGoal,
        targetProvince: ProvinceID? = nil,
        name: String,
        description: String
    ) {
        self.type = type
        self.target = target
        self.warGoal = warGoal
        self.targetProvince = targetProvince
        self.name = name
        self.description = description
    }
}

/// Error returned when war declaration fails.
public enum WarDeclarationError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalid(reason: String)
    case requiresTruceBreak(truceUntil: GameDate)

    public var description: String {
        switch self {
        case .invalid(let reason):
            return reason
        case .requiresTruceBreak(let until):
            return "Active truce until \(until). Set breakTruce: true to proceed."
        }
    }
}

/// Validation result for declaring war.
public enum WarDeclarationValidation: Sendable, Equatable {
    case valid
    case requiresTruceBreak(truceUntil: GameDate)
    case invalid(reason: String)

    public var isValid: Bool {
        switch self {
        case .valid: return true
        default: return false
        }
    }
}

/// Evaluation of an ally's willingness to answer a call to arms.
public struct CallToArmsEvaluation: Sendable, Equatable {
    public var willAccept: Bool
    public var score: Int
    public var factors: [(name: String, score: Int)]

    public var reasons: [String] {
        factors.map { "\($0.name) (\($0.score >= 0 ? "+" : "")\($0.score))" }
    }

    public init(willAccept: Bool, score: Int, factors: [(name: String, score: Int)]) {
        self.willAccept = willAccept
        self.score = score
        self.factors = factors
    }

    public static func == (lhs: CallToArmsEvaluation, rhs: CallToArmsEvaluation) -> Bool {
        guard lhs.willAccept == rhs.willAccept, lhs.score == rhs.score, lhs.factors.count == rhs.factors.count else {
            return false
        }
        for (a, b) in zip(lhs.factors, rhs.factors) {
            if a.name != b.name || a.score != b.score { return false }
        }
        return true
    }
}

/// Result of issuing a call to arms to an ally.
public enum CallToArmsResult: Sendable, Equatable {
    case accepted
    case declined(reasons: [String])
}

// MARK: - Diplomacy War Declaration & Call to Arms API

extension Diplomacy {

    /// Generates aggressive expansion by `country` across other nations based on religious and geographic proximity.
    public mutating func generateAggressiveExpansion(by country: CountryID, amount: Double, world: World) {
        guard countryCount > 0 else { return }
        for other in world.countries.ids where other != country {
            var factor = 0.5
            let relCountry = world.countries.religion[country.index]
            let relOther = world.countries.religion[other.index]
            if relCountry.family == relOther.family {
                factor += 0.3
            }
            if world.areNeighbors(country, other) {
                factor += 0.2
            }
            let generated = amount * factor
            addAggressiveExpansion(target: country, observer: other, amount: generated)
            modifyOpinion(of: country, by: other, delta: -Int(generated))
        }
    }

    /// True if there is a royal marriage between the ruling families of countries `a` and `b`.
    public func hasRoyalMarriage(between a: CountryID, and b: CountryID, in world: World) -> Bool {
        guard a != b else { return false }
        if let rulerA = world.countries.ruler[a.index] {
            for spouse in world.people.characters.spouses[rulerA.index] {
                if let court = world.people.characters.court[spouse.index], court == b {
                    return true
                }
            }
        }
        if let rulerB = world.countries.ruler[b.index] {
            for spouse in world.people.characters.spouses[rulerB.index] {
                if let court = world.people.characters.court[spouse.index], court == a {
                    return true
                }
            }
        }
        return false
    }

    /// Returns all valid casus belli instances available to `attacker` against `defender`.
    public func availableCasusBelli(attacker: CountryID, defender: CountryID, in world: World) -> [CasusBelliInstance] {
        guard attacker != defender else { return [] }
        var result: [CasusBelliInstance] = []

        // 1. Reconquest: Attacker has core on defender-owned province
        let defenderProvinces = world.provinces(ownedBy: defender).sorted { $0.index < $1.index }
        for p in defenderProvinces {
            if world.provinces.cores[p.index].contains(attacker) {
                let pName = world.provinces.name[p.index]
                result.append(CasusBelliInstance(
                    type: .reconquest,
                    target: defender,
                    warGoal: .conquerProvince(p),
                    targetProvince: p,
                    name: "Reconquest of \(pName)",
                    description: "Reclaim ancestral core province with zero aggressive expansion."
                ))
            }
        }

        // 2. Claim: Attacker has territorial claim on defender-owned province (non-core)
        for p in defenderProvinces {
            if world.provinces.claims[p.index].contains(attacker) && !world.provinces.cores[p.index].contains(attacker) {
                let pName = world.provinces.name[p.index]
                result.append(CasusBelliInstance(
                    type: .claim,
                    target: defender,
                    warGoal: .conquerProvince(p),
                    targetProvince: p,
                    name: "Conquest of \(pName)",
                    description: "Enforce territorial claim on \(pName)."
                ))
            }
        }

        // 3. Holy War: Different religious families and neighboring border
        let relA = world.countries.religion[attacker.index]
        let relB = world.countries.religion[defender.index]
        if relA.family != relB.family && world.areNeighbors(attacker, defender) {
            let defName = world.countries.name[defender.index]
            result.append(CasusBelliInstance(
                type: .holyWar,
                target: defender,
                warGoal: .superiority,
                targetProvince: nil,
                name: "Holy War against \(defName)",
                description: "Fight to defend and propagate the true faith."
            ))
        }

        // 4. Subjugation: Independent smaller neighbour (<= 6 provinces, attacker dev >= 2.5x defender dev)
        if world.areNeighbors(attacker, defender) && world.countries.overlord[defender.index] == nil {
            let defDev = world.totalDevelopment(of: defender)
            let attDev = world.totalDevelopment(of: attacker)
            if defenderProvinces.count <= 6 && attDev >= Int(Double(defDev) * 2.5) {
                let defName = world.countries.name[defender.index]
                if let cap = world.countries.capital[defender.index] {
                    result.append(CasusBelliInstance(
                        type: .subjugation,
                        target: defender,
                        warGoal: .conquerProvince(cap),
                        targetProvince: cap,
                        name: "Subjugation of \(defName)",
                        description: "Force \(defName) to swear fealty as a vassal state."
                    ))
                }
            }
        }

        // 5. Tribute: Steppe horde or eastern realm demanding tributary status
        if world.areNeighbors(attacker, defender) && world.countries.overlord[defender.index] == nil {
            let govA = world.countries.government[attacker.index]
            let isNomadOrEastern = (govA == .steppeHorde || relA.family == .dharmic || relA.family == .pagan)
            if isNomadOrEastern && world.totalDevelopment(of: attacker) > world.totalDevelopment(of: defender) {
                let defName = world.countries.name[defender.index]
                result.append(CasusBelliInstance(
                    type: .tribute,
                    target: defender,
                    warGoal: .superiority,
                    targetProvince: nil,
                    name: "Demand Tribute from \(defName)",
                    description: "Force \(defName) to pay annual tribute."
                ))
            }
        }

        // 6. Succession: Royal marriage exists and defender has no heir
        if hasRoyalMarriage(between: attacker, and: defender, in: world) {
            if world.countries.government[defender.index] != .republic && world.countries.heir[defender.index] == nil {
                let defName = world.countries.name[defender.index]
                if let cap = world.countries.capital[defender.index] {
                    result.append(CasusBelliInstance(
                        type: .succession,
                        target: defender,
                        warGoal: .conquerProvince(cap),
                        targetProvince: cap,
                        name: "War of Succession for \(defName)",
                        description: "Enforce claim to the vacant throne through royal dynastic ties."
                    ))
                }
            }
        }

        // 7. Coalition: Defender in coalition against defender (50+ AE with 4+ outraged countries)
        let inCoalition = coalitions[defender]?.contains(attacker) ?? false
        if inCoalition || aggressiveExpansion(of: defender, by: attacker) >= 50.0 {
            var outragedCount = 0
            for c in world.countries.ids where c != defender {
                if aggressiveExpansion(of: defender, by: c) >= 50.0 && opinion(of: defender, by: c) < 0 {
                    outragedCount += 1
                }
            }
            if inCoalition || outragedCount >= 4 {
                let defName = world.countries.name[defender.index]
                result.append(CasusBelliInstance(
                    type: .coalition,
                    target: defender,
                    warGoal: .superiority,
                    targetProvince: nil,
                    name: "Coalition Punitive War against \(defName)",
                    description: "Lead the international coalition to punish aggressive expansion."
                ))
            }
        }

        // 8. No-CB: Always available as fallback
        let defName = world.countries.name[defender.index]
        result.append(CasusBelliInstance(
            type: .noCB,
            target: defender,
            warGoal: .superiority,
            targetProvince: nil,
            name: "No Casus Belli against \(defName)",
            description: "Wage an unjust war without legitimate cause (-2 stability, +20 aggressive expansion)."
        ))

        return result
    }

    /// Checks whether `attacker` can declare war on `defender`.
    public func canDeclareWar(
        attacker: CountryID,
        defender: CountryID,
        breakTruce: Bool = false,
        world: World
    ) -> WarDeclarationValidation {
        if attacker == defender {
            return .invalid(reason: "Cannot declare war on oneself.")
        }
        if isAtWar(attacker, defender) {
            return .invalid(reason: "Countries are already at war.")
        }
        if world.countries.overlord[attacker.index] != nil {
            return .invalid(reason: "Subject countries cannot declare external wars.")
        }
        if world.countries.overlord[defender.index] == attacker {
            return .invalid(reason: "Cannot declare war directly on your own subject.")
        }

        // Truce check
        if let truce = treaty(.truce, between: attacker, and: defender) {
            if !breakTruce {
                return .requiresTruceBreak(truceUntil: truce.expiry ?? GameDate(year: 1458, month: 1, day: 1))
            }
        }

        return .valid
    }

    /// Evaluates whether an ally will accept a call to arms based on trust, opinion, debt, truces, and strength.
    public func evaluateCallToArms(
        ally: CountryID,
        caller: CountryID,
        enemy: CountryID,
        isDefensive: Bool,
        in world: World
    ) -> CallToArmsEvaluation {
        var factors: [(name: String, score: Int)] = []

        // Defensive war bonus
        if isDefensive {
            factors.append(("Defensive War", 30))
        }

        // Trust in caller (scaled around neutral 50)
        let callerTrust = trust(of: caller, by: ally)
        let trustDelta = callerTrust - 50
        factors.append(("Trust in Caller", trustDelta))

        // Opinion of caller
        let callerOp = opinion(of: caller, by: ally)
        factors.append(("Opinion of Caller", callerOp / 4))

        // Opinion of enemy (hating the enemy increases willingness)
        let enemyOp = opinion(of: enemy, by: ally)
        factors.append(("Opinion of Enemy", -enemyOp / 4))

        // Active truce with enemy
        if hasTruce(ally, enemy) {
            factors.append(("Active Truce with Enemy", -50))
        }

        // Treasury / debt deficit
        if world.countries.treasury[ally.index] < 10.0 {
            factors.append(("Low Treasury / Debt", -20))
        }

        // Already fighting multiple wars
        let activeWars = activeWars(for: ally).count
        if activeWars >= 2 {
            factors.append(("Multiple Active Wars", -30))
        } else if activeWars == 1 {
            factors.append(("Already at War", -10))
        }

        // Allied with the enemy in offensive war
        if !isDefensive && areAllies(ally, enemy) {
            factors.append(("Allied with Enemy", -40))
        }

        // Relative military strength
        let friendlyForce = world.totalSoldiers(of: caller) + world.totalSoldiers(of: ally)
        let enemyForce = world.totalSoldiers(of: enemy)
        if friendlyForce >= max(1, Int(Double(enemyForce) * 1.5)) {
            factors.append(("Military Advantage", 15))
        } else if enemyForce >= max(1, friendlyForce * 2) {
            factors.append(("Enemy Military Superiority", -25))
        }

        // Theater proximity
        if world.areNeighbors(ally, enemy) || world.areNeighbors(ally, caller) {
            factors.append(("Adjacent Theater", 10))
        } else {
            factors.append(("Distant Conflict", -15))
        }

        let totalScore = factors.reduce(0) { $0 + $1.score }
        let willAccept = totalScore >= 0
        return CallToArmsEvaluation(willAccept: willAccept, score: totalScore, factors: factors)
    }

    public func generateWarTitle(
        attackerName: String,
        defenderName: String,
        cb: CasusBelli,
        goal: WarGoal,
        world: World
    ) -> String {
        switch cb {
        case .reconquest:
            if case .conquerProvince(let pid) = goal {
                return "\(attackerName) Reconquest of \(world.provinces.name[pid.index])"
            }
            return "\(attackerName) Reconquest War against \(defenderName)"
        case .claim:
            if case .conquerProvince(let pid) = goal {
                return "\(attackerName) Conquest of \(world.provinces.name[pid.index])"
            }
            return "\(attackerName) Conquest War against \(defenderName)"
        case .holyWar:
            return "\(attackerName) Holy War against \(defenderName)"
        case .subjugation:
            return "\(attackerName) Subjugation of \(defenderName)"
        case .tribute:
            return "\(attackerName) Demand for Tribute from \(defenderName)"
        case .succession:
            return "\(attackerName) War of Succession for \(defenderName)"
        case .coalition:
            return "Coalition Punitive War against \(defenderName)"
        case .noCB:
            return "\(attackerName) War against \(defenderName)"
        }
    }
}

// MARK: - World War Declaration & Call to Arms Operations

extension World {

    /// Declares war between `attacker` and `defender`.
    /// Handles stability, aggressive expansion, breaking conflicting treaties, and calling in subjects.
    public mutating func declareWar(
        attacker: CountryID,
        defender: CountryID,
        casusBelli: CasusBelli,
        warGoal: WarGoal,
        breakTruce: Bool = false,
        date: GameDate
    ) -> Result<War, WarDeclarationError> {
        let check = diplomacy.canDeclareWar(attacker: attacker, defender: defender, breakTruce: breakTruce, world: self)
        switch check {
        case .invalid(let reason):
            return .failure(.invalid(reason: reason))
        case .requiresTruceBreak(let until):
            return .failure(.requiresTruceBreak(truceUntil: until))
        case .valid:
            break
        }

        // 1. Truce break penalty
        if diplomacy.treaty(.truce, between: attacker, and: defender) != nil {
            GovernmentSystem.changeStability(&self, attacker, by: -5)
            diplomacy.generateAggressiveExpansion(by: attacker, amount: 50.0, world: self)
            for other in countries.ids where other != attacker {
                diplomacy.modifyTrust(of: attacker, by: other, delta: -30)
            }
            diplomacy.removeTreaty(.truce, between: attacker, and: defender)
        }

        // 2. No-CB penalty
        if casusBelli == .noCB {
            GovernmentSystem.changeStability(&self, attacker, by: -2)
            diplomacy.generateAggressiveExpansion(by: attacker, amount: 20.0, world: self)
        }

        // 3. Break conflicting treaties between attacker and defender
        diplomacy.removeTreaty(.alliance, between: attacker, and: defender)
        diplomacy.removeTreaty(.guarantee, between: attacker, and: defender)
        diplomacy.removeTreaty(.guarantee, between: defender, and: attacker)
        diplomacy.removeTreaty(.nonAggression, between: attacker, and: defender)
        diplomacy.removeTreaty(.militaryAccess, between: attacker, and: defender)
        diplomacy.removeTreaty(.militaryAccess, between: defender, and: attacker)

        // 4. Belligerents: Attacker + subjects vs Defender + subjects
        var attackers = [attacker]
        var defenders = [defender]

        for s in countries.subjects(of: attacker) {
            if !attackers.contains(s) { attackers.append(s) }
        }
        for s in countries.subjects(of: defender) {
            if !defenders.contains(s) { defenders.append(s) }
        }

        // Coalition call-ins: offensive punitive coalition against defender
        if casusBelli == .coalition, let coalMembers = diplomacy.coalitions[defender] {
            for m in coalMembers.sorted(by: { $0.index < $1.index }) where !attackers.contains(m) && m != attacker && m != defender {
                attackers.append(m)
                for s in countries.subjects(of: m) where !attackers.contains(s) {
                    attackers.append(s)
                }
            }
        }
        // Defensive coalition: if attacker targets any member of a coalition formed against attacker
        if let coalAgainstAttacker = diplomacy.coalitions[attacker], coalAgainstAttacker.contains(defender) {
            for m in coalAgainstAttacker.sorted(by: { $0.index < $1.index }) where !defenders.contains(m) && m != attacker {
                defenders.append(m)
                for s in countries.subjects(of: m) where !defenders.contains(s) {
                    defenders.append(s)
                }
            }
        }

        // 5. Hostility relations: -100 opinion and low trust between enemy sides
        for a in attackers {
            for d in defenders {
                diplomacy.setOpinion(of: d, by: a, value: -100)
                diplomacy.setOpinion(of: a, by: d, value: -100)
                diplomacy.setTrust(of: d, by: a, value: min(10, diplomacy.trust(of: d, by: a)))
                diplomacy.setTrust(of: a, by: d, value: min(10, diplomacy.trust(of: a, by: d)))
            }
        }

        // 6. War generation
        let attTag = countries.tag[attacker.index]
        let defTag = countries.tag[defender.index]
        let attName = countries.name[attacker.index]
        let defName = countries.name[defender.index]
        let warID = "war_\(attTag)_\(defTag)_\(date.year)_\(date.month)_\(date.day)"
        let warName = diplomacy.generateWarTitle(attackerName: attName, defenderName: defName, cb: casusBelli, goal: warGoal, world: self)

        let war = War(
            id: warID,
            name: warName,
            startDate: date,
            casusBelli: casusBelli,
            warGoal: warGoal,
            attackers: attackers,
            defenders: defenders,
            warScore: 0.0,
            note: "Declared with \(casusBelli.rawValue)"
        )
        diplomacy.addWar(war)
        return .success(war)
    }

    /// Issues a call to arms to an ally. If accepted, ally joins the war. If declined, the alliance is broken with trust penalty.
    public mutating func callToArms(
        caller: CountryID,
        ally: CountryID,
        warID: String
    ) -> CallToArmsResult {
        guard var war = diplomacy.wars.first(where: { $0.id == warID }) else {
            return .declined(reasons: ["War not found."])
        }
        guard war.isParticipant(caller) else {
            return .declined(reasons: ["Caller is not a belligerent in this war."])
        }
        guard !war.isParticipant(ally) else {
            return .declined(reasons: ["Ally is already participating in this war."])
        }
        guard diplomacy.areAllies(caller, ally) else {
            return .declined(reasons: ["No active alliance between caller and ally."])
        }

        let isDefensive = war.primaryDefender == caller || war.isDefender(caller)
        let primaryEnemy = isDefensive ? war.primaryAttacker : war.primaryDefender
        let evaluation = diplomacy.evaluateCallToArms(ally: ally, caller: caller, enemy: primaryEnemy, isDefensive: isDefensive, in: self)

        if evaluation.willAccept {
            // Join war side
            if isDefensive {
                war.addDefender(ally)
            } else {
                war.addAttacker(ally)
            }
            diplomacy.updateWar(war)

            // Mutual trust boost
            diplomacy.modifyTrust(of: ally, by: caller, delta: 10)
            diplomacy.modifyTrust(of: caller, by: ally, delta: 10)

            // Hostility with opposing side
            let enemies = isDefensive ? war.attackers : war.defenders
            for enemy in enemies {
                diplomacy.setOpinion(of: enemy, by: ally, value: -100)
                diplomacy.setOpinion(of: ally, by: enemy, value: -100)
                diplomacy.setTrust(of: enemy, by: ally, value: min(10, diplomacy.trust(of: enemy, by: ally)))
                diplomacy.setTrust(of: ally, by: enemy, value: min(10, diplomacy.trust(of: ally, by: enemy)))
            }

            return .accepted
        } else {
            // Broken alliance
            diplomacy.removeTreaty(.alliance, between: caller, and: ally)
            diplomacy.modifyTrust(of: ally, by: caller, delta: -25)
            diplomacy.modifyTrust(of: caller, by: ally, delta: -25)
            diplomacy.modifyOpinion(of: ally, by: caller, delta: -50) // Dishonored alliance

            let negativeReasons = evaluation.factors.filter { $0.score < 0 }.map { "\($0.name) (\($0.score))" }
            return .declined(reasons: negativeReasons)
        }
    }
}
