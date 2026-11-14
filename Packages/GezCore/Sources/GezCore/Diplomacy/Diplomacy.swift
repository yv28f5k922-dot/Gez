import Foundation

/// Supported diplomatic treaty types between countries (Phase 7, owner's choice).
public enum TreatyType: String, Codable, Sendable, CaseIterable {
    case alliance
    case guarantee
    case nonAggression = "non_aggression"
    case militaryAccess = "military_access"
    case truce
}

/// A formal diplomatic treaty between two sovereign countries.
public struct Treaty: Sendable, Equatable {
    public var first: CountryID
    public var second: CountryID
    public var type: TreatyType
    public var expiry: GameDate?
    public var note: String

    public init(first: CountryID, second: CountryID, type: TreatyType, expiry: GameDate? = nil, note: String = "") {
        self.first = first
        self.second = second
        self.type = type
        self.expiry = expiry
        self.note = note
    }

    /// True if the treaty involves both countries (order-independent for mutual treaties).
    public func involves(_ a: CountryID, _ b: CountryID) -> Bool {
        (first == a && second == b) || (first == b && second == a)
    }
}

/// Casus belli types recognized in the international order (Phase 7, owner's choice).
public enum CasusBelli: String, Codable, Sendable, CaseIterable {
    case reconquest
    case claim
    case holyWar
    case subjugation
    case tribute
    case succession
    case coalition
    case noCB
}

/// War goal specifying what must be held or achieved to earn ticking war score.
public enum WarGoal: Sendable, Equatable {
    case conquerProvince(ProvinceID)
    case superiority
    case defendCapital(ProvinceID)
}

/// An active war between two hostile coalitions.
public struct War: Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var startDate: GameDate
    public var casusBelli: CasusBelli
    public var warGoal: WarGoal
    /// Primary attacker is index 0.
    public var attackers: [CountryID]
    /// Primary defender is index 0.
    public var defenders: [CountryID]
    /// War score from attacker's point of view (-1.0 ... +1.0, representing -100% to +100%).
    public var warScore: Double
    /// War score earned specifically from field battles (-0.40 ... +0.40).
    public var battleWarScore: Double
    /// Ticking war score from holding the war goal (-0.25 ... +0.25).
    public var tickingWarScore: Double
    public var note: String

    public init(
        id: String,
        name: String,
        startDate: GameDate,
        casusBelli: CasusBelli,
        warGoal: WarGoal,
        attackers: [CountryID],
        defenders: [CountryID],
        warScore: Double = 0.0,
        battleWarScore: Double = 0.0,
        tickingWarScore: Double = 0.0,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.casusBelli = casusBelli
        self.warGoal = warGoal
        self.attackers = attackers
        self.defenders = defenders
        self.warScore = warScore
        self.battleWarScore = battleWarScore
        self.tickingWarScore = tickingWarScore
        self.note = note
    }

    public var primaryAttacker: CountryID { attackers[0] }
    public var primaryDefender: CountryID { defenders[0] }

    public func isAttacker(_ country: CountryID) -> Bool { attackers.contains(country) }
    public func isDefender(_ country: CountryID) -> Bool { defenders.contains(country) }
    public func isParticipant(_ country: CountryID) -> Bool { isAttacker(country) || isDefender(country) }

    public func areEnemies(_ a: CountryID, _ b: CountryID) -> Bool {
        (isAttacker(a) && isDefender(b)) || (isDefender(a) && isAttacker(b))
    }

    public mutating func addAttacker(_ country: CountryID) {
        if !attackers.contains(country) {
            attackers.append(country)
        }
    }

    public mutating func addDefender(_ country: CountryID) {
        if !defenders.contains(country) {
            defenders.append(country)
        }
    }
}

/// Active war reparations agreement: payer pays 10% of monthly income to receiver until `until`.
public struct WarReparation: Sendable, Equatable {
    public var payer: CountryID
    public var receiver: CountryID
    public var until: GameDate

    public init(payer: CountryID, receiver: CountryID, until: GameDate) {
        self.payer = payer
        self.receiver = receiver
        self.until = until
    }
}

/// Complete diplomatic relations state stored on `World`.
///
/// Matrix values (opinion, trust, aggressive expansion) are stored as flat 1D arrays
/// indexed by `observer.index * countryCount + target.index` for cache-friendly access.
public struct Diplomacy: Sendable {
    public var countryCount: Int = 0

    /// Bilateral opinion (-100 ... +100). Indexed by observer * countryCount + target.
    public var opinions: [Int16] = []

    /// Bilateral trust (0 ... 100, default 50). Indexed by observer * countryCount + target.
    public var trusts: [Int8] = []

    /// Aggressive expansion generated by target in observer's eyes (0.0 ... 1000.0).
    public var aggressiveExpansion: [Float] = []

    /// Active treaties across all nations.
    public var treaties: [Treaty] = []

    /// Active wars currently being waged.
    public var wars: [War] = []

    /// Active war reparations (10% monthly income transfers for 10 years).
    public var warReparations: [WarReparation] = []

    /// Active coalitions against aggressive expanders: target -> coalition member countries.
    public var coalitions: [CountryID: Set<CountryID>] = [:]

    public init() {}

    public mutating func resize(countries n: Int) {
        self.countryCount = n
        let size = n * n
        self.opinions = Array(repeating: 0, count: size)
        self.trusts = Array(repeating: 50, count: size)
        self.aggressiveExpansion = Array(repeating: 0.0, count: size)
    }

    private func index(observer: CountryID, target: CountryID) -> Int {
        precondition(observer.index < countryCount && target.index < countryCount, "CountryID out of bounds")
        return observer.index * countryCount + target.index
    }

    // MARK: - Opinion (-100 ... +100)

    public func opinion(of target: CountryID, by observer: CountryID) -> Int {
        guard countryCount > 0, observer.index < countryCount, target.index < countryCount else { return 0 }
        if observer == target { return 100 }
        return Int(opinions[index(observer: observer, target: target)])
    }

    public mutating func setOpinion(of target: CountryID, by observer: CountryID, value: Int) {
        guard countryCount > 0, observer.index < countryCount, target.index < countryCount else { return }
        guard observer != target else { return }
        let clamped = Int16(max(-100, min(100, value)))
        opinions[index(observer: observer, target: target)] = clamped
    }

    public mutating func modifyOpinion(of target: CountryID, by observer: CountryID, delta: Int) {
        let current = opinion(of: target, by: observer)
        setOpinion(of: target, by: observer, value: current + delta)
    }

    // MARK: - Trust (0 ... 100, default 50)

    public func trust(of target: CountryID, by observer: CountryID) -> Int {
        guard countryCount > 0, observer.index < countryCount, target.index < countryCount else { return 50 }
        if observer == target { return 100 }
        return Int(trusts[index(observer: observer, target: target)])
    }

    public mutating func setTrust(of target: CountryID, by observer: CountryID, value: Int) {
        guard countryCount > 0, observer.index < countryCount, target.index < countryCount else { return }
        guard observer != target else { return }
        let clamped = Int8(max(0, min(100, value)))
        trusts[index(observer: observer, target: target)] = clamped
    }

    public mutating func modifyTrust(of target: CountryID, by observer: CountryID, delta: Int) {
        let current = trust(of: target, by: observer)
        setTrust(of: target, by: observer, value: current + delta)
    }

    // MARK: - Aggressive Expansion

    public func aggressiveExpansion(of target: CountryID, by observer: CountryID) -> Double {
        guard countryCount > 0, observer.index < countryCount, target.index < countryCount else { return 0 }
        if observer == target { return 0 }
        return Double(aggressiveExpansion[index(observer: observer, target: target)])
    }

    public mutating func addAggressiveExpansion(target: CountryID, observer: CountryID, amount: Double) {
        guard countryCount > 0, observer.index < countryCount, target.index < countryCount else { return }
        guard observer != target else { return }
        let idx = index(observer: observer, target: target)
        let newAE = max(0.0, Float(aggressiveExpansion[idx]) + Float(amount))
        aggressiveExpansion[idx] = newAE
    }

    public mutating func decayAggressiveExpansion(amount: Double) {
        guard countryCount > 0 else { return }
        let amt = Float(amount)
        for i in 0..<aggressiveExpansion.count {
            if aggressiveExpansion[i] > 0 {
                aggressiveExpansion[i] = max(0.0, aggressiveExpansion[i] - amt)
            }
        }
    }

    // MARK: - Diplomatic Relation Slots

    /// Diplomatic relation slots available to a country: base 4 + ruler Diplomacy skill / 5.
    public func relationSlots(for country: CountryID, world: World) -> Int {
        var slots = 4
        if let rulerID = world.countries.ruler[country.index] {
            let dipSkill = world.people.characters.skills[rulerID.index][Skill.diplomacy.rawValue]
            slots += dipSkill / 5
        }
        if let chancellorID = world.countries.council[country.index][CouncilSeat.chancellor.rawValue] {
            let chanSkill = world.people.characters.skills[chancellorID.index][Skill.diplomacy.rawValue]
            slots += chanSkill / 10
        }
        return slots
    }

    /// Number of diplomatic relation slots currently used:
    /// Alliances, guarantees (by guarantor), non-aggression pacts, royal marriages, and vassals (by overlord).
    public func usedRelationSlots(for country: CountryID, world: World) -> Int {
        var used = 0

        for t in treaties {
            switch t.type {
            case .alliance, .nonAggression:
                if t.first == country || t.second == country { used += 1 }
            case .guarantee:
                if t.first == country { used += 1 }
            case .militaryAccess, .truce:
                break // Access and truces do not take up diplomatic slots
            }
        }

        // Royal marriages with other ruling families take slots
        // Check marriages of ruling family
        if let rulerID = world.countries.ruler[country.index] {
            for spouseID in world.people.characters.spouses[rulerID.index] {
                // If spouse is from a different court
                if let spouseCourt = world.people.characters.court[spouseID.index], spouseCourt != country {
                    used += 1
                }
            }
        }

        // Vassals take a slot from the overlord
        let vassals = world.countries.subjects(of: country)
        used += vassals.count

        return used
    }

    // MARK: - Treaties

    public func hasTreaty(_ type: TreatyType, between a: CountryID, and b: CountryID) -> Bool {
        treaties.contains { t in
            guard t.type == type else { return false }
            switch type {
            case .alliance, .nonAggression, .truce:
                return t.involves(a, b)
            case .guarantee:
                return t.first == a && t.second == b
            case .militaryAccess:
                return t.first == a && t.second == b
            }
        }
    }

    public func treaty(_ type: TreatyType, between a: CountryID, and b: CountryID) -> Treaty? {
        treaties.first { t in
            guard t.type == type else { return false }
            switch type {
            case .alliance, .nonAggression, .truce:
                return t.involves(a, b)
            case .guarantee, .militaryAccess:
                return t.first == a && t.second == b
            }
        }
    }

    public mutating func addTreaty(_ treaty: Treaty) {
        if !hasTreaty(treaty.type, between: treaty.first, and: treaty.second) {
            treaties.append(treaty)
        }
    }

    public mutating func removeTreaty(_ type: TreatyType, between a: CountryID, and b: CountryID) {
        treaties.removeAll { t in
            guard t.type == type else { return false }
            switch type {
            case .alliance, .nonAggression, .truce:
                return t.involves(a, b)
            case .guarantee, .militaryAccess:
                return t.first == a && t.second == b
            }
        }
    }

    public func areAllies(_ a: CountryID, _ b: CountryID) -> Bool {
        hasTreaty(.alliance, between: a, and: b)
    }

    public func hasTruce(_ a: CountryID, _ b: CountryID) -> Bool {
        hasTreaty(.truce, between: a, and: b)
    }

    public func hasMilitaryAccess(country: CountryID, through territoryOwner: CountryID) -> Bool {
        if country == territoryOwner { return true }
        if areAllies(country, territoryOwner) { return true }
        if hasTreaty(.militaryAccess, between: territoryOwner, and: country) { return true }
        return false
    }

    // MARK: - Wars

    public func isAtWar(_ a: CountryID, _ b: CountryID) -> Bool {
        wars.contains { $0.areEnemies(a, b) }
    }

    public func activeWar(between a: CountryID, and b: CountryID) -> War? {
        wars.first { $0.areEnemies(a, b) }
    }

    public func activeWars(for country: CountryID) -> [War] {
        wars.filter { $0.isParticipant(country) }
    }

    public mutating func addWar(_ war: War) {
        if !wars.contains(where: { $0.id == war.id }) {
            wars.append(war)
        }
    }

    public mutating func updateWar(_ war: War) {
        if let idx = wars.firstIndex(where: { $0.id == war.id }) {
            wars[idx] = war
        }
    }

    public mutating func endWar(id: String) {
        wars.removeAll { $0.id == id }
    }
}
