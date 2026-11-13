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

        world.economy = eco
        world.assignMarkets()
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
    let imports: [Import]
    let producers: [[Producer]]
}
