/// Ordering, building and paying for buildings; and a simple AI that builds
/// for computer-run countries.
public enum BuildingSystem {
    /// Yearly upkeep per level paid by the state, as a share of the level-1
    /// cost. Workshops, farms and mines are run by their owners (no upkeep);
    /// the first fort level is a local lord's castle (free).
    public static func upkeepShare(_ category: BuildingCategory) -> Double {
        switch category {
        case .production: return 0
        case .trade, .religion: return 0.02
        case .military: return 0.01
        }
    }

    /// Ducats a year the owner pays for this many levels of a building.
    public static func yearlyUpkeep(_ type: BuildingType, levels: Int) -> Double {
        let paid = type.effect == .fort ? max(0, levels - 1) : levels
        return Double(paid) * type.cost * upkeepShare(type.category)
    }

    public enum Refusal: Equatable, Sendable {
        case notOwner, maxLevel, noSlots, alreadyBuilding, needsCoast, wrongGood, wrongTerrain, wrongReligion, cannotAfford

        public var reason: String {
            switch self {
            case .notOwner: return "Not your province"
            case .maxLevel: return "Already at level 5"
            case .noSlots: return "No free building slots"
            case .alreadyBuilding: return "Already being built"
            case .needsCoast: return "Needs a coast"
            case .wrongGood: return "Needs a matching trade good"
            case .wrongTerrain: return "Wrong terrain"
            case .wrongReligion: return "Wrong religion"
            case .cannotAfford: return "Not enough ducats"
            }
        }
    }

    /// Building slots: 4 + 2 × development, +2 on the coast, +2 in a market town.
    public static func slots(_ world: World, _ p: ProvinceID) -> Int {
        let isMarketTown = world.economy.markets.centre.contains(p)
        return 4 + 2 * world.provinces.development[p.index]
            + (world.provinces.isCoastal[p.index] ? 2 : 0) + (isMarketTown ? 2 : 0)
    }

    /// The level the next construction would reach.
    public static func nextLevel(_ world: World, _ p: ProvinceID, _ t: BuildingTypeID) -> Int {
        world.economy.buildings.level(p, t) + 1
    }

    /// Ducats plus the current market price of the materials.
    public static func cost(_ world: World, _ p: ProvinceID, _ t: BuildingTypeID) -> Double {
        let type = world.economy.buildingTypes[t.index]
        var total = type.ducats(forLevel: nextLevel(world, p, t))
        if let m = world.market(of: p) {
            for (g, amount) in type.materials {
                total += amount * world.economy.markets.price(m, g)
            }
        }
        if let owner = world.provinces.owner[p.index] {
            total *= 1 + world.countries.inflation[owner.index]
        }
        return total
    }

    /// Why the country can't build this here, or nil if it can. Pass
    /// `checkMoney: false` to ask only about the province.
    public static func refusal(_ world: World, _ country: CountryID, _ p: ProvinceID, _ t: BuildingTypeID,
                               checkMoney: Bool = true) -> Refusal? {
        let eco = world.economy
        let type = eco.buildingTypes[t.index]
        if world.provinces.owner[p.index] != country { return .notOwner }
        if eco.buildings.construction(p, t) != nil { return .alreadyBuilding }
        if eco.buildings.level(p, t) >= BuildingType.maxLevel { return .maxLevel }
        if type.requiresCoast && !world.provinces.isCoastal[p.index] { return .needsCoast }
        if !type.requiresGoods.isEmpty && !type.requiresGoods.contains(world.tradeGood(of: p)) { return .wrongGood }
        if !type.requiresTerrain.isEmpty && !type.requiresTerrain.contains(world.provinces.terrain[p.index]) { return .wrongTerrain }
        if let family = type.requiresFamily, world.provinces.religion[p.index].family != family { return .wrongReligion }
        if eco.buildings.slotsUsed(p) >= slots(world, p) { return .noSlots }
        if checkMoney && world.countries.treasury[country.index] < cost(world, p, t) { return .cannotAfford }
        return nil
    }

    /// Pays and starts building. Materials are bought from the province's
    /// market (they raise next month's demand there).
    @discardableResult
    public static func start(_ world: inout World, _ country: CountryID, _ p: ProvinceID, _ t: BuildingTypeID) -> Refusal? {
        if let r = refusal(world, country, p, t) { return r }
        let type = world.economy.buildingTypes[t.index]
        let level = nextLevel(world, p, t)
        world.countries.treasury[country.index] -= cost(world, p, t)
        if let m = world.market(of: p) {
            for (g, amount) in type.materials {
                world.economy.markets.pendingDemand[world.economy.markets.slot(m, g)] += amount
            }
        }
        let months = type.months(forLevel: level)
        world.economy.buildings.constructions.append(
            Construction(province: p, type: t, level: level, monthsLeft: months, totalMonths: months))
        return nil
    }

    /// Monthly: progress constructions, pay upkeep.
    public static func runMonthly(_ world: inout World) {
        var finished: [Construction] = []
        var still: [Construction] = []
        for var c in world.economy.buildings.constructions {
            // A province that changed hands stops the work.
            c.monthsLeft -= 1
            if c.monthsLeft <= 0 { finished.append(c) } else { still.append(c) }
        }
        world.economy.buildings.constructions = still
        for c in finished {
            world.economy.buildings.setLevel(c.province, c.type, c.level)
            if world.economy.buildingTypes[c.type.index].effect == .fort {
                world.provinces.fortLevel[c.province.index] = c.level
            }
        }

        let eco = world.economy
        let T = eco.buildings.typeCount
        var upkeep = Array(repeating: 0.0, count: world.countries.count)
        for p in 0..<world.provinces.count {
            guard let owner = world.provinces.owner[p] else { continue }
            for t in 0..<T {
                let l = eco.buildings.level[p * T + t]
                if l > 0 {
                    upkeep[owner.index] += yearlyUpkeep(eco.buildingTypes[t], levels: l) / 12
                }
            }
        }
        for c in 0..<world.countries.count {
            world.countries.treasury[c] -= upkeep[c]
            world.countries.lastUpkeep[c] = upkeep[c]
            world.countries.lastMonthlyExpenses[c] = upkeep[c]
        }
    }

    // MARK: - AI

    /// Each month a twelfth of the computer-run countries consider building
    /// one thing: the best yearly return for the cost, if it pays back
    /// within about 15 years and leaves a reserve.
    public static func runAI(_ world: inout World, month: Int) {
        let reserveMonths = 6.0
        for c in world.countries.ids where c.index % 12 == month % 12 && !world.humanCountries.contains(c) {
            let income = world.countries.lastMonthlyIncome[c.index]
            let reserve = max(30, income * reserveMonths)
            guard world.countries.treasury[c.index] > reserve else { continue }
            var best: (score: Double, p: ProvinceID, t: BuildingTypeID)?
            let owned = world.provinces(ownedBy: c)
                .sorted { world.provinces.production[$0.index] > world.provinces.production[$1.index] }
                .prefix(8)
            for p in owned {
                for t in world.economy.buildingTypes.indices.map(BuildingTypeID.init) {
                    guard refusal(world, c, p, t) == nil else { continue }
                    let cost = cost(world, p, t)
                    guard world.countries.treasury[c.index] - cost > reserve else { continue }
                    let gain = yearlyGain(world, p, t)
                    let score = gain / cost
                    if score > 1.0 / 15, best == nil || score > best!.score {
                        best = (score, p, t)
                    }
                }
            }
            if let b = best {
                start(&world, c, b.p, b.t)
            }
        }
    }

    /// Rough ducats a year the owner gains from one more level (tax only,
    /// minus upkeep), plus small fixed values for buildings whose worth
    /// shows up later (forts, barracks, temples, colleges).
    public static func yearlyGain(_ world: World, _ p: ProvinceID, _ t: BuildingTypeID) -> Double {
        let eco = world.economy
        let type = eco.buildingTypes[t.index]
        let current = eco.buildings.level(p, t)
        let upkeep = yearlyUpkeep(type, levels: current + 1) - yearlyUpkeep(type, levels: current)
        let prov = world.provinces
        let range = eco.producers.range(for: p)
        func producerValue(_ match: (Int) -> Bool) -> Double {
            range.filter(match).reduce(0) { $0 + eco.producers.value[$1] * 12 }
        }
        let fish = eco.goods.id(forKey: "fish")
        var gain: Double
        switch type.effect {
        case .staple(let x):
            gain = producerValue { eco.producers.isStaple[$0] } * x * MarketModel.taxRaw
        case .trade(let x):
            gain = producerValue { !eco.producers.isStaple[$0] && eco.producers.good[$0] != fish } * x * MarketModel.taxRaw
        case .fish(let x):
            gain = producerValue { eco.producers.good[$0] == fish } * x * MarketModel.taxRaw
        case .workshop(let r):
            guard let m = world.market(of: p) else { return 0 }
            let recipe = eco.recipes[r]
            var unitCost = 0.0
            for input in recipe.inputs { unitCost += eco.markets.price(m, input.0) * input.1 }
            let margin = eco.markets.price(m, recipe.output) - unitCost
            // Only worth it while the market is short of the good.
            let i = eco.markets.slot(m, recipe.output)
            let shortage = eco.markets.demand[i] > eco.markets.supply[i] * 1.05 ? 1.0 : 0.2
            gain = Economy.jobsPerLevel * recipe.perThousand * max(0, margin) * MarketModel.taxCraft * shortage
        case .crafts(let x):
            gain = (0..<eco.buildings.typeCount).reduce(0) { $0 + eco.workshopValue[p.index * eco.buildings.typeCount + $1] * 12 }
                * x * MarketModel.taxCraft
        case .tax(let x):
            gain = prov.baseTax[p.index] * x
        case .mood, .learning, .fort, .manpower, .ships:
            gain = type.cost / 25
        }
        return gain - upkeep
    }
}
