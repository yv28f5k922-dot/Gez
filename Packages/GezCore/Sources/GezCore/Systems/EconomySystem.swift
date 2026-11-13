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
