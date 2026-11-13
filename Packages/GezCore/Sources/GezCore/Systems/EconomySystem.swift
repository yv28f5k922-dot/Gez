/// Monthly income and spending. Income now comes from the market model
/// (`MarketSystem`); expenses (armies, buildings, loans) come later.
public enum EconomySystem {
    public static func runMonthly(_ world: inout World) {
        MarketSystem.runMonthly(&world)
    }
}

/// Monthly population growth. Placeholder flat rate per pop until food,
/// disease, war devastation, conversion, assimilation and migration arrive.
public enum PopulationSystem {
    public static let yearlyGrowthRate = 0.004

    public static func runMonthly(_ world: inout World) {
        let factor = 1 + yearlyGrowthRate / 12
        for i in 0..<world.pops.count {
            world.pops.size[i] *= factor
        }
        for p in 0..<world.provinces.count {
            var total = 0.0
            for i in world.pops.range(for: ProvinceID(p)) { total += world.pops.size[i] }
            world.provinces.population[p] = total
        }
    }
}
