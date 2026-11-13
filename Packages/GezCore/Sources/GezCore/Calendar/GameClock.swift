/// Game speed, EU4 style: paused plus five speeds.
public enum GameSpeed: Int, CaseIterable, Sendable {
    case paused = 0, one, two, three, four, five

    /// How many in-game days pass per real second.
    public var daysPerSecond: Double {
        switch self {
        case .paused: return 0
        case .one: return 0.5
        case .two: return 1
        case .three: return 2.5
        case .four: return 6
        case .five: return 20
        }
    }
}

/// Converts real elapsed time into a whole number of daily ticks.
///
/// The front end calls `daysToAdvance(elapsedSeconds:)` every frame and then
/// runs that many ticks. Fractions of a day carry over between frames so the
/// game speed is exact regardless of frame rate.
public struct GameClock: Sendable {
    public var speed: GameSpeed = .paused {
        didSet { if speed == .paused { accumulator = 0 } }
    }
    /// Safety cap so a long frame hitch (or the app returning from background)
    /// can't trigger hundreds of ticks at once.
    public var maxDaysPerUpdate: Int = 30
    private var accumulator: Double = 0

    public init(speed: GameSpeed = .paused) {
        self.speed = speed
    }

    public mutating func daysToAdvance(elapsedSeconds: Double) -> Int {
        guard speed != .paused, elapsedSeconds > 0 else { return 0 }
        accumulator += elapsedSeconds * speed.daysPerSecond
        let whole = Int(accumulator)
        accumulator -= Double(whole)
        if whole > maxDaysPerUpdate {
            accumulator = 0
            return maxDaysPerUpdate
        }
        return whole
    }
}
