import Foundation

/// Tuning numbers for the market model. `tools/economy/prototype.py` is a
/// Python copy used for balancing; keep the two in step.
public enum MarketModel {
    /// Staple food per 1,000 workers per year on plains.
    public static let stapleYield = 1.5
    public static let seaCost = 0.35
    public static let portCost = 50.0
    /// Prices move this share of the way to their target each month.
    public static let priceSpeed = 0.25
    /// Prices stay between these multiples of the base price.
    public static let priceMin = 0.2
    public static let priceMax = 5.0
    public static let satisfactionSpeed = 0.2
    public static let startingSatisfaction = 0.7
    /// Tax taken from farms and mines, and from workshop profits.
    public static let taxRaw = 0.025
    public static let taxCraft = 0.03
    /// A workshop missing all of a minor input still works at this rate.
    public static let secondaryFloor = 0.6
    /// Surplus nobody local wants still sells this share to passing traders.
    public static let minimumSold = 0.25
    public static let exchangePasses = 3
    public static let exchangeRate = 0.5
    public static let exchangeLoss = 0.1

    public static func terrainFood(_ t: Terrain) -> Double {
        switch t {
        case .farmland: return 1.2
        case .plains: return 1.0
        case .hills: return 0.85
        case .mountains: return 0.6
        case .forest: return 0.75
        case .marsh: return 0.75
        case .desert: return 0.45
        case .steppe: return 0.7
        }
    }

    public static func terrainCost(_ t: Terrain) -> Double {
        switch t {
        case .farmland, .plains: return 1.0
        case .hills: return 1.5
        case .mountains: return 3.0
        case .forest: return 1.6
        case .marsh, .desert: return 2.0
        case .steppe: return 1.2
        }
    }

    /// Great-circle distance in kilometres.
    public static func km(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let r = Double.pi / 180
        let la1 = a.latitude * r, la2 = b.latitude * r
        let dLa = la2 - la1, dLo = (b.longitude - a.longitude) * r
        let h = sin(dLa / 2) * sin(dLa / 2) + cos(la1) * cos(la2) * sin(dLo / 2) * sin(dLo / 2)
        return 12742 * asin(min(1, h.squareRoot()))
    }
}

/// The monthly economy:
/// 1. farms, mines and workshops produce (workshops limited by last month's inputs)
/// 2. pops and workshops ask for goods
/// 3. surplus flows to neighbouring markets that are short
/// 4. markets clear: prices move toward demand / supply
/// 5. pops grow more or less satisfied
/// 6. producers earn money and countries collect tax
public enum MarketSystem {
    public static func runMonthly(_ world: inout World) {
        let eco = world.economy
        let G = eco.goods.count
        let M = eco.markets.count
        guard G > 0, M > 0, !eco.provinceMarket.isEmpty else { return }
        let P = world.provinces.count
        let base = eco.goods.basePrice
        let avail = eco.markets.met

        // Workers in thousands, by province.
        var rural = Array(repeating: 0.0, count: P)
        var burghers = Array(repeating: 0.0, count: P)
        for i in 0..<world.pops.count {
            let p = world.pops.province[i].index
            switch world.pops.socialClass[i] {
            case .peasants, .slaves: rural[p] += world.pops.size[i] / 1000
            case .burghers: burghers[p] += world.pops.size[i] / 1000
            default: break
            }
        }

        var S = eco.markets.imports.map { $0 / 12 }
        var D = Array(repeating: 0.0, count: M * G)
        var producers = eco.producers

        // 1. Production.
        let bonus = BuildingBonuses(eco, provinces: P)
        let fishGood = eco.goods.id(forKey: "fish")
        for k in 0..<producers.count where producers.kind[k] == .raw {
            let p = producers.province[k].index
            let m = eco.provinceMarket[p].index
            let g = producers.good[k].index
            let workers = rural[p] * producers.share[k]
            let y: Double
            if producers.isStaple[k] {
                y = MarketModel.stapleYield * MarketModel.terrainFood(world.provinces.terrain[p]) * (1 + bonus.staple[p])
            } else if producers.good[k] == fishGood {
                y = eco.goods.yield[g] * (1 + bonus.fish[p])
            } else {
                y = eco.goods.yield[g] * (1 + bonus.trade[p])
            }
            let out = workers * y / 12
            producers.output[k] = out
            S[m * G + g] += out
            for (bg, amount) in eco.goods.byproducts[g] {
                S[m * G + bg.index] += out * amount
            }
        }
        // Workshops: buildings give burgher jobs; if there are fewer burghers
        // than jobs, every workshop in the province runs short-handed.
        let T = eco.buildings.typeCount
        var workshopOutput = Array(repeating: 0.0, count: P * T)
        for p in 0..<P {
            var jobs = 0.0
            for t in 0..<T {
                if case .workshop = eco.buildingTypes[t].effect {
                    jobs += Double(eco.buildings.level[p * T + t]) * Economy.jobsPerLevel
                }
            }
            guard jobs > 0 else { continue }
            let fill = min(1, burghers[p] * Economy.workshopShare / jobs)
            let m = eco.provinceMarket[p].index
            for t in 0..<T {
                guard case .workshop(let r) = eco.buildingTypes[t].effect else { continue }
                let level = eco.buildings.level[p * T + t]
                guard level > 0 else { continue }
                let recipe = eco.recipes[r]
                let potential = Double(level) * Economy.jobsPerLevel * fill * recipe.perThousand * (1 + bonus.crafts[p]) / 12
                var f = 1.0
                for (n, input) in recipe.inputs.enumerated() {
                    let a = avail[m * G + input.0.index]
                    f *= n == 0 ? a : MarketModel.secondaryFloor + (1 - MarketModel.secondaryFloor) * a
                    D[m * G + input.0.index] += potential * input.1
                }
                let out = potential * f
                workshopOutput[p * T + t] = out
                S[m * G + recipe.output.index] += out
            }
        }
        // Building materials bought last month.
        for i in 0..<(M * G) { D[i] += eco.markets.pendingDemand[i] }

        // 2. What people want, split between substitutes by what is on offer.
        // People are grouped by (market, class, religion family): everyone in
        // a group has the same needs and faces the same prices.
        let classes = SocialClass.allCases
        let families = ReligionFamily.allCases
        let C = classes.count, F = families.count
        func groupIndex(_ m: Int, _ c: SocialClass, _ f: ReligionFamily) -> Int {
            (m * C + classes.firstIndex(of: c)!) * F + families.firstIndex(of: f)!
        }
        var groupSize = Array(repeating: 0.0, count: M * C * F)
        var popGroup = Array(repeating: 0, count: world.pops.count)
        for i in 0..<world.pops.count {
            let m = eco.provinceMarket[world.pops.province[i].index].index
            let gi = groupIndex(m, world.pops.socialClass[i], world.pops.religion[i].family)
            popGroup[i] = gi
            groupSize[gi] += world.pops.size[i] / 1000
        }
        let offered = S
        // shareTable[m][need] = split of the need between its goods.
        var shareTable: [[[Double]]] = []
        shareTable.reserveCapacity(M)
        for m in 0..<M {
            shareTable.append(eco.needs.map { need in
                let ws = need.goods.map { max(offered[m * G + $0.index], 0) }
                let total = ws.reduce(0, +)
                return total > 0 ? ws.map { $0 / total } : Array(repeating: 1 / Double(ws.count), count: ws.count)
            })
        }
        for m in 0..<M {
            for c in classes {
                for f in families {
                    let size = groupSize[groupIndex(m, c, f)]
                    guard size > 0 else { continue }
                    for (n, need) in eco.needs.enumerated() where need.socialClass == c && need.applies(to: f) {
                        let amount = need.amount * size / 12
                        for (g, s) in zip(need.goods, shareTable[m][n]) {
                            D[m * G + g.index] += amount * s
                        }
                    }
                }
            }
        }

        // 3. Trade routes buy and deliver; then petty trade: surplus flows to
        // neighbouring markets that are short.
        let delivered = TradeSystem.move(world, avail: avail, S: &S, D: &D)
        for _ in 0..<MarketModel.exchangePasses {
            for (a, b) in eco.marketLinks {
                for g in 0..<G {
                    let ia = a.index * G + g, ib = b.index * G + g
                    let ea = S[ia] - D[ia], eb = S[ib] - D[ib]
                    if ea > 0 && eb < 0 {
                        let t = MarketModel.exchangeRate * min(ea, -eb)
                        S[ia] -= t
                        S[ib] += t * (1 - MarketModel.exchangeLoss)
                    } else if eb > 0 && ea < 0 {
                        let t = MarketModel.exchangeRate * min(eb, -ea)
                        S[ib] -= t
                        S[ia] += t * (1 - MarketModel.exchangeLoss)
                    }
                }
            }
        }

        // 4. Markets clear.
        var markets = eco.markets
        var met = Array(repeating: 1.0, count: M * G)
        var sold = Array(repeating: 1.0, count: M * G)
        for m in 0..<M {
            for g in 0..<G {
                let i = m * G + g
                let s = S[i], d = D[i]
                let target: Double
                if d <= 0 {
                    met[i] = 1
                    sold[i] = s > 0 ? MarketModel.minimumSold : 1
                    target = base[g] * MarketModel.priceMin
                } else if s <= 0 {
                    met[i] = 0
                    target = base[g] * MarketModel.priceMax
                } else {
                    met[i] = min(1, s / d)
                    sold[i] = max(MarketModel.minimumSold, min(1, d / s))
                    target = base[g] * min(MarketModel.priceMax, max(MarketModel.priceMin, (d / s).squareRoot()))
                }
                markets.price[i] += MarketModel.priceSpeed * (target - markets.price[i])
            }
        }
        markets.supply = S
        markets.demand = D
        markets.met = met

        // 5. Satisfaction: value-weighted share of needs met, per group.
        var groupSatisfaction = Array(repeating: -1.0, count: M * C * F)
        for m in 0..<M {
            for c in classes {
                for f in families {
                    let gi = groupIndex(m, c, f)
                    guard groupSize[gi] > 0 else { continue }
                    var got = 0.0, wanted = 0.0
                    for (n, need) in eco.needs.enumerated() where need.socialClass == c && need.applies(to: f) {
                        var value = 0.0, fulfil = 0.0
                        for (g, s) in zip(need.goods, shareTable[m][n]) {
                            value += base[g.index] * s
                            fulfil += met[m * G + g.index] * s
                        }
                        got += need.amount * value * fulfil
                        wanted += need.amount * value
                    }
                    if wanted > 0 { groupSatisfaction[gi] = got / wanted }
                }
            }
        }
        var pops = world.pops
        for i in 0..<pops.count {
            let needsMet = groupSatisfaction[popGroup[i]]
            if needsMet >= 0 {
                let p = pops.province[i].index
                var target = needsMet + bonus.mood[p]
                if let owner = world.provinces.owner[p] {
                    target += world.taxMood(owner, pops.socialClass[i]) + world.financeMood(owner, pops.socialClass[i])
                }
                target = min(1, max(0, target))
                pops.satisfaction[i] += MarketModel.satisfactionSpeed * (target - pops.satisfaction[i])
            }
        }

        // 6. Money.
        var income = Array(repeating: 0.0, count: world.countries.count)
        var provinceValue = Array(repeating: 0.0, count: P)
        var provinceTax = Array(repeating: 0.0, count: P)
        var landValue = Array(repeating: 0.0, count: P)
        for k in 0..<producers.count where producers.kind[k] == .raw {
            let p = producers.province[k].index
            let m = eco.provinceMarket[p].index
            let g = producers.good[k].index
            let out = producers.output[k]
            var value = out * markets.price[m * G + g] * sold[m * G + g]
            for (bg, amount) in eco.goods.byproducts[g] {
                let j = m * G + bg.index
                value += out * amount * markets.price[j] * sold[j]
            }
            producers.value[k] = value
            provinceValue[p] += value
            landValue[p] += value
        }
        var workshopValue = Array(repeating: 0.0, count: P * T)
        var craftValue = Array(repeating: 0.0, count: P)
        for p in 0..<P {
            let m = eco.provinceMarket[p].index
            for t in 0..<T where workshopOutput[p * T + t] > 0 {
                guard case .workshop(let r) = eco.buildingTypes[t].effect else { continue }
                let recipe = eco.recipes[r]
                var cost = 0.0
                for input in recipe.inputs {
                    cost += markets.price[m * G + input.0.index] * input.1
                }
                let g = recipe.output.index
                let value = max(0, workshopOutput[p * T + t] * (markets.price[m * G + g] * sold[m * G + g] - cost))
                workshopValue[p * T + t] = value
                provinceValue[p] += value
                craftValue[p] += value
            }
        }
        let rulerBonus = world.countries.ids.map { CharacterSystem.taxBonus(world, $0) }
        for c in world.countries.ids {
            world.countries.learning[c.index] += CharacterSystem.learningPerYear(world, c) / 12
        }
        var classTax = Array(repeating: Array(repeating: 0.0, count: TaxClass.allCases.count), count: world.countries.count)
        var vassalTax = Array(repeating: 0.0, count: world.countries.count)
        for p in 0..<P {
            guard let owner = world.provinces.owner[p] else {
                provinceTax[p] = (landValue[p] * MarketModel.taxRaw + craftValue[p] * MarketModel.taxCraft) * (1 + bonus.tax[p])
                continue
            }
            let o = owner.index
            let factor = (1 + bonus.tax[p] + rulerBonus[o]) * (world.countries.bankruptMonthsLeft[o] > 0 ? Finance.bankruptcyIncome : 1)
            for tc in TaxClass.allCases {
                let baseValue = tc == .burghers ? craftValue[p] : landValue[p] * tc.shareOfLand
                let tax = baseValue * tc.normalRate * world.countries.taxLevel[o][tc.rawValue] * factor
                classTax[o][tc.rawValue] += tax
                provinceTax[p] += tax
            }
            if let h = world.provinces.holder[p] {
                // A great vassal keeps his share, or everything if he refuses.
                let kept = world.people.refusing.contains(h) ? provinceTax[p] : provinceTax[p] * VassalModel.keepShare
                world.people.characters.gold[h.index] += kept
                vassalTax[o] += kept
                income[o] += provinceTax[p] - kept
            } else {
                income[o] += provinceTax[p]
            }
            world.countries.learning[o] += bonus.learning[p] / 12
        }
        world.countries.lastTax = classTax
        world.countries.lastVassalTax = vassalTax

        markets.pendingDemand = Array(repeating: 0, count: M * G)
        world.economy.workshopOutput = workshopOutput
        world.economy.workshopValue = workshopValue
        world.economy.markets = markets
        world.economy.producers = producers
        let (tradeProfit, tolls) = TradeSystem.settle(&world, delivered: delivered, sold: sold)
        for c in 0..<world.countries.count {
            income[c] += tradeProfit[c] + tolls[c]
        }
        world.countries.lastTrade = tradeProfit
        world.countries.lastTolls = tolls
        world.pops = pops
        for p in 0..<P {
            world.provinces.production[p] = provinceValue[p] * 12
            world.provinces.baseTax[p] = provinceTax[p] * 12
        }
        for c in 0..<world.countries.count {
            world.countries.treasury[c] += income[c]
            world.countries.lastMonthlyIncome[c] = income[c]
        }
    }
}
