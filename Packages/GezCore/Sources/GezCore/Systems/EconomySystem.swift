/// Monthly income. First pass: taxes plus production, no expenses yet.
/// Army maintenance, buildings, trade and estates come in later milestones.
public enum EconomySystem {
    public static func runMonthly(_ world: inout World) {
        var income = [Double](repeating: 0, count: world.countries.count)
        let provinces = world.provinces
        for i in 0..<provinces.count {
            guard let owner = provinces.owner[i] else { continue }
            income[owner.index] += (provinces.baseTax[i] + provinces.production[i]) / 12
        }
        for c in 0..<world.countries.count {
            world.countries.treasury[c] += income[c]
            world.countries.lastMonthlyIncome[c] = income[c]
        }
    }
}

/// Monthly population growth. Placeholder flat rate until pops get
/// food, disease, war devastation and migration.
public enum PopulationSystem {
    public static let yearlyGrowthRate = 0.004

    public static func runMonthly(_ world: inout World) {
        let factor = 1 + yearlyGrowthRate / 12
        for i in 0..<world.provinces.count {
            world.provinces.population[i] *= factor
        }
    }
}
