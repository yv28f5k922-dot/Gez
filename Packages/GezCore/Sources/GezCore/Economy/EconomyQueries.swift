/// Read-only questions the interface asks about the economy.
extension World {
    /// The good a province is known for: its trade good, or its staple food.
    public func tradeGood(of province: ProvinceID) -> GoodID {
        let eco = economy
        let r = eco.producers.range(for: province)
        for k in r where eco.producers.kind[k] == .raw && !eco.producers.isStaple[k]
            && eco.goods.key[eco.producers.good[k].index] != "fish" {
            return eco.producers.good[k]
        }
        return r.isEmpty ? GoodID(0) : eco.producers.good[r.lowerBound]
    }

    /// Population-weighted satisfaction of one class in some provinces
    /// (nil if nobody of that class lives there).
    public func satisfaction(of socialClass: SocialClass, in provinceIDs: [ProvinceID]) -> Double? {
        var sum = 0.0, weight = 0.0
        for p in provinceIDs {
            for i in pops.range(for: p) where pops.socialClass[i] == socialClass {
                sum += pops.satisfaction[i] * pops.size[i]
                weight += pops.size[i]
            }
        }
        return weight > 0 ? sum / weight : nil
    }

    public func market(of province: ProvinceID) -> MarketID? {
        province.index < economy.provinceMarket.count ? economy.provinceMarket[province.index] : nil
    }
}

extension MarketSystem {
    /// Runs the market for some months so prices and satisfaction settle
    /// before the game starts, without changing anyone's treasury.
    public static func warmUp(_ world: inout World, months: Int) {
        let treasury = world.countries.treasury
        for _ in 0..<months { runMonthly(&world) }
        world.countries.treasury = treasury
    }
}
