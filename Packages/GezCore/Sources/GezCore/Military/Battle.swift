import Foundation

/// Combat phase of an active field battle, alternating every 3 days.
public enum BattlePhase: String, Sendable, Codable, CaseIterable {
    case fire
    case shock

    public var displayName: String {
        switch self {
        case .fire:  return "Fire"
        case .shock: return "Shock"
        }
    }
}

/// An ongoing multi-day field battle taking place in a province.
public struct Battle: Sendable, Identifiable, Equatable, Codable {
    public var id: String
    public var province: ProvinceID
    public var startDate: GameDate
    public var dayCount: Int
    /// Armies fighting on the attacking (invading) side.
    public var attackers: [ArmyID]
    /// Armies fighting on the defending side.
    public var defenders: [ArmyID]
    /// Primary commanding country for each side.
    public var attackerCountry: CountryID
    public var defenderCountry: CountryID
    public var currentPhase: BattlePhase
    public var phaseDay: Int
    /// True if attacking forces crossed a major river into this province.
    public var isRiverCrossing: Bool
    public var attackerInitialMen: Int
    public var defenderInitialMen: Int
    public var attackerLosses: Int
    public var defenderLosses: Int
    /// Current 0...9 commander dice rolls for the active 3-day phase.
    public var attackerDiceRoll: Int
    public var defenderDiceRoll: Int

    public init(
        id: String,
        province: ProvinceID,
        startDate: GameDate,
        dayCount: Int = 0,
        attackers: [ArmyID],
        defenders: [ArmyID],
        attackerCountry: CountryID,
        defenderCountry: CountryID,
        currentPhase: BattlePhase = .fire,
        phaseDay: Int = 1,
        isRiverCrossing: Bool = false,
        attackerInitialMen: Int,
        defenderInitialMen: Int,
        attackerLosses: Int = 0,
        defenderLosses: Int = 0,
        attackerDiceRoll: Int = 5,
        defenderDiceRoll: Int = 5
    ) {
        self.id = id
        self.province = province
        self.startDate = startDate
        self.dayCount = dayCount
        self.attackers = attackers
        self.defenders = defenders
        self.attackerCountry = attackerCountry
        self.defenderCountry = defenderCountry
        self.currentPhase = currentPhase
        self.phaseDay = phaseDay
        self.isRiverCrossing = isRiverCrossing
        self.attackerInitialMen = attackerInitialMen
        self.defenderInitialMen = defenderInitialMen
        self.attackerLosses = attackerLosses
        self.defenderLosses = defenderLosses
        self.attackerDiceRoll = attackerDiceRoll
        self.defenderDiceRoll = defenderDiceRoll
    }
}

/// Archived summary of a completed field battle.
public struct BattleReport: Sendable, Identifiable, Equatable, Codable {
    public var id: String
    public var province: ProvinceID
    public var startDate: GameDate
    public var endDate: GameDate
    public var attackerCountry: CountryID
    public var defenderCountry: CountryID
    public var winner: CountryID
    public var attackerInitialMen: Int
    public var defenderInitialMen: Int
    public var attackerLosses: Int
    public var defenderLosses: Int
    public var daysFought: Int
    public var wasStackwipe: Bool

    public init(
        id: String,
        province: ProvinceID,
        startDate: GameDate,
        endDate: GameDate,
        attackerCountry: CountryID,
        defenderCountry: CountryID,
        winner: CountryID,
        attackerInitialMen: Int,
        defenderInitialMen: Int,
        attackerLosses: Int,
        defenderLosses: Int,
        daysFought: Int,
        wasStackwipe: Bool
    ) {
        self.id = id
        self.province = province
        self.startDate = startDate
        self.endDate = endDate
        self.attackerCountry = attackerCountry
        self.defenderCountry = defenderCountry
        self.winner = winner
        self.attackerInitialMen = attackerInitialMen
        self.defenderInitialMen = defenderInitialMen
        self.attackerLosses = attackerLosses
        self.defenderLosses = defenderLosses
        self.daysFought = daysFought
        self.wasStackwipe = wasStackwipe
    }
}
