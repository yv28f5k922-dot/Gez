import Foundation

/// Loads `Resources/economy1453.json` (built by `tools/economy/econgen.py`)
/// into `world.economy` and joins provinces to markets.
enum EconomyLoader {
    static func loadBundled(into world: inout World) throws {
        guard let url = Bundle.module.url(forResource: "economy1453", withExtension: "json") else {
            throw Scenario1453.LoadError.missingResource
        }
        try load(from: Data(contentsOf: url), into: &world)
    }

    static func load(from data: Data, into world: inout World) throws {
        let file = try JSONDecoder().decode(EconomyFile.self, from: data)
        var eco = Economy()

        for g in file.goods {
            guard let category = GoodCategory(rawValue: g.category) else {
                throw Scenario1453.LoadError.unknownValue("good category \(g.category)")
            }
            eco.goods.add(
                key: g.key, name: g.name, category: category, basePrice: g.basePrice,
                color: RGB(UInt8(g.color[0]), UInt8(g.color[1]), UInt8(g.color[2])),
                yield: g.yield ?? 0,
                byproducts: (g.byproducts ?? []).map { (GoodID(Int($0[0])), $0[1]) }
            )
        }
        eco.recipes = file.recipes.map { r in
            Recipe(output: GoodID(r.output), perThousand: r.perThousand,
                   inputs: r.inputs.map { (GoodID(Int($0[0])), $0[1]) })
        }
        for n in file.needs {
            guard let cls = SocialClass(rawValue: n.socialClass) else {
                throw Scenario1453.LoadError.unknownValue("class \(n.socialClass)")
            }
            eco.needs.append(NeedGroup(
                socialClass: cls, name: n.name, amount: n.amount, goods: n.goods.map(GoodID.init),
                onlyFamily: n.only.flatMap(ReligionFamily.init(rawValue:)),
                notFamily: n.not.flatMap(ReligionFamily.init(rawValue:))))
        }

        eco.markets.setGoodCount(eco.goods.count)
        for m in file.markets {
            eco.markets.add(name: m.name, centre: ProvinceID(m.centre), basePrices: eco.goods.basePrice)
        }
        for im in file.imports {
            eco.markets.imports[im.market * eco.goods.count + im.good] += im.amount
        }

        guard file.producers.count == world.provinces.count else {
            throw Scenario1453.LoadError.unknownValue("producers for \(file.producers.count) provinces, map has \(world.provinces.count)")
        }
        for (p, list) in file.producers.enumerated() {
            eco.producers.beginProvince(ProvinceID(p))
            for (k, pr) in list.enumerated() {
                guard let kind = ProducerKind(rawValue: pr.kind) else {
                    throw Scenario1453.LoadError.unknownValue("producer kind \(pr.kind)")
                }
                eco.producers.add(good: GoodID(pr.good), kind: kind, recipe: pr.recipe ?? -1,
                                  share: pr.share, isStaple: k == 0 && kind == .raw)
            }
        }

        for b in file.buildings {
            guard let category = BuildingCategory(rawValue: b.category) else {
                throw Scenario1453.LoadError.unknownValue("building category \(b.category)")
            }
            let amount = b.amount ?? 0
            let effect: BuildingEffect
            switch b.effect {
            case "staple": effect = .staple(amount)
            case "trade": effect = .trade(amount)
            case "fish": effect = .fish(amount)
            case "workshop": effect = .workshop(recipe: b.recipe ?? 0)
            case "crafts": effect = .crafts(amount)
            case "tax": effect = .tax(amount)
            case "mood": effect = .mood(amount)
            case "learning": effect = .learning(amount)
            case "fort": effect = .fort
            case "manpower": effect = .manpower(amount)
            case "ships": effect = .ships(amount)
            case "routes": effect = .routes(amount)
            default: throw Scenario1453.LoadError.unknownValue("building effect \(b.effect)")
            }
            eco.buildingTypes.append(BuildingType(
                key: b.key, name: b.name, category: category, cost: b.cost, months: b.months,
                materials: b.materials.map { (GoodID(Int($0[0])), $0[1]) },
                effect: effect,
                requiresCoast: b.requiresCoast ?? false,
                requiresGoods: (b.requiresGoods ?? []).map(GoodID.init),
                requiresTerrain: (b.requiresTerrain ?? []).compactMap(Terrain.init(rawValue:)),
                requiresFamily: b.requiresFamily.flatMap(ReligionFamily.init(rawValue:))))
        }
        let typeCount = eco.buildingTypes.count
        eco.buildings.setup(provinces: world.provinces.count, types: typeCount)
        eco.workshopOutput = Array(repeating: 0, count: world.provinces.count * typeCount)
        eco.workshopValue = eco.workshopOutput
        for (p, list) in file.startBuildings.enumerated() where p < world.provinces.count {
            for pair in list where pair.count == 2 {
                eco.buildings.setLevel(ProvinceID(p), BuildingTypeID(pair[0]), min(pair[1], BuildingType.maxLevel))
            }
        }
        // Forts: the stronger of the data file and the development-based start.
        if let fort = eco.buildingTypes.firstIndex(where: { $0.effect == .fort }).map(BuildingTypeID.init) {
            for p in world.provinces.ids {
                let level = max(eco.buildings.level(p, fort), world.provinces.fortLevel[p.index])
                eco.buildings.setLevel(p, fort, min(level, BuildingType.maxLevel))
                world.provinces.fortLevel[p.index] = min(level, BuildingType.maxLevel)
            }
        }

        world.finance = Finance()
        for b in file.banks {
            world.finance.banks.add(name: b.name, home: ProvinceID(b.home), capital: b.capital,
                                    baseRate: b.rate, regions: b.regions.map(RegionID.init))
        }
        world.economy = eco
        world.assignMarkets()
        for r in file.routes {
            guard let owner = world.countries.id(forTag: r.owner) else {
                throw Scenario1453.LoadError.unknownValue("route owner \(r.owner)")
            }
            TradeSystem.create(&world, owner: owner, good: GoodID(r.good), from: MarketID(r.from), to: MarketID(r.to),
                               volume: r.volume, ignoreCapacity: true)
        }
    }
}

// MARK: - JSON shape (matches tools/economy/econgen.py)

struct EconomyFile: Decodable {
    struct Good: Decodable {
        let key: String
        let name: String
        let category: String
        let basePrice: Double
        let color: [Int]
        let yield: Double?
        let byproducts: [[Double]]?
    }

    struct RecipeRow: Decodable {
        let output: Int
        let perThousand: Double
        let inputs: [[Double]]
    }

    struct Need: Decodable {
        let socialClass: String
        let name: String
        let amount: Double
        let goods: [Int]
        let only: String?
        let not: String?
    }

    struct Market: Decodable {
        let name: String
        let centre: Int
    }

    struct Import: Decodable {
        let market: Int
        let good: Int
        let amount: Double
    }

    struct Producer: Decodable {
        let good: Int
        let kind: String
        let share: Double
        let recipe: Int?
    }

    let goods: [Good]
    let recipes: [RecipeRow]
    let needs: [Need]
    let markets: [Market]
    struct Building: Decodable {
        let key: String
        let name: String
        let category: String
        let cost: Double
        let months: Int
        let materials: [[Double]]
        let effect: String
        let amount: Double?
        let recipe: Int?
        let requiresCoast: Bool?
        let requiresGoods: [Int]?
        let requiresTerrain: [String]?
        let requiresFamily: String?
    }

    struct Bank: Decodable {
        let name: String
        let home: Int
        let capital: Double
        let rate: Double
        let regions: [Int]
    }

    struct Route: Decodable {
        let owner: String
        let good: Int
        let from: Int
        let to: Int
        let volume: Double
    }

    let routes: [Route]
    let banks: [Bank]
    let imports: [Import]
    let producers: [[Producer]]
    let buildings: [Building]
    let startBuildings: [[[Int]]]
}
