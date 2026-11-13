/// Owns the world state and advances it one day at a time.
///
/// The tick order is fixed and documented here so results are deterministic:
/// 1. advance the date
/// 2. daily systems (movement, sieges, battles: later milestones)
/// 3. monthly systems on the 1st of each month
/// 4. yearly systems on 1 January
public final class Simulation {
    public private(set) var date: GameDate
    public var world: World
    public private(set) var random: GameRandom
    public private(set) var ticksRun: Int = 0

    public init(world: World, startDate: GameDate, seed: UInt64 = 1453) {
        self.world = world
        self.date = startDate
        self.random = GameRandom(seed: seed)
    }

    public func advance(days: Int) {
        for _ in 0..<max(0, days) {
            tick()
        }
    }

    public func tick() {
        date.advanceOneDay()
        ticksRun += 1

        // Daily systems go here.

        if date.isFirstOfMonth {
            TradeSystem.refreshPaths(&world)
            EconomySystem.runMonthly(&world)
            BuildingSystem.runMonthly(&world)
            FinanceSystem.runMonthly(&world)
            FinanceSystem.runAI(&world)
            TradeSystem.runAI(&world, month: date.month)
            BuildingSystem.runAI(&world, month: date.month)
            PopulationSystem.runMonthly(&world)
            CharacterSystem.runMonthly(&world, date: date, random: &random)
            VassalSystem.runMonthly(&world, date: date, random: &random)
        }

        if date.isFirstOfYear {
            CharacterSystem.runYearly(&world, date: date, random: &random)
            VassalSystem.runYearly(&world, date: date, random: &random)
        }
    }
}
