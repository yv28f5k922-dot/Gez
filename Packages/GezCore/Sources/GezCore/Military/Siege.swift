import Foundation

/// Outcome of a monthly siege phase roll.
public enum SiegeOutcome: String, Sendable, Equatable, Codable {
    case suppliesHolding = "Supplies Holding"
    case foodShortage = "Food Shortage"
    case waterShortage = "Water Shortage"
    case defenderDesertion = "Defender Desertion"
    case diseaseOutbreak = "Disease Outbreak"
    case wallBreach = "Wall Breached"
    case surrender = "Fort Surrendered"
}

/// Active siege against a fortified province (`fortLevel > 0`).
public struct Siege: Sendable, Identifiable, Equatable {
    public var id: String
    public var province: ProvinceID
    public var besieger: CountryID
    public var startDate: GameDate
    /// Cumulative siege progress from 0 toward surrender threshold.
    public var progress: Int
    /// Whether artillery/rolls have breached the walls, unlocking Storm Assault.
    public var breached: Bool
    /// True if coastal fort is blockaded (or landlocked).
    public var blockaded: Bool
    public var lastRoll: Int?
    public var lastModifier: Int
    public var lastOutcome: SiegeOutcome?
    public var phaseDaysRemaining: Int

    public init(
        province: ProvinceID,
        besieger: CountryID,
        startDate: GameDate,
        progress: Int = 0,
        breached: Bool = false,
        blockaded: Bool = true,
        lastRoll: Int? = nil,
        lastModifier: Int = 0,
        lastOutcome: SiegeOutcome? = nil,
        phaseDaysRemaining: Int = 30
    ) {
        self.id = "siege_\(province.index)"
        self.province = province
        self.besieger = besieger
        self.startDate = startDate
        self.progress = progress
        self.breached = breached
        self.blockaded = blockaded
        self.lastRoll = lastRoll
        self.lastModifier = lastModifier
        self.lastOutcome = lastOutcome
        self.phaseDaysRemaining = phaseDaysRemaining
    }
}

/// Outcome of an infantry/cavalry Storm Assault against a breached fort.
public struct AssaultResult: Sendable, Equatable {
    public var captured: Bool
    public var attackerLosses: Int
    public var garrisonLosses: Int
    public var remainingGarrison: Int
    public var refusalReason: String?

    public init(
        captured: Bool,
        attackerLosses: Int,
        garrisonLosses: Int,
        remainingGarrison: Int,
        refusalReason: String? = nil
    ) {
        self.captured = captured
        self.attackerLosses = attackerLosses
        self.garrisonLosses = garrisonLosses
        self.remainingGarrison = remainingGarrison
        self.refusalReason = refusalReason
    }
}
