/// Trade routes: a country's merchants buy a good in one market and sell it
/// in another, along a path of linked markets. Routes are drawn by players
/// (and the AI); the 1453 routes come from `data/economy/routes_1453.txt`.

public struct TradeRoute: Sendable, Equatable, Codable {
    public var owner: CountryID
    public var good: GoodID
    public var from: MarketID
    public var to: MarketID
    /// Units a year the merchants try to move.
    public var volume: Double
    /// Markets passed through, from `from` to `to` (empty = no way through).
    public var path: [MarketID] = []
    /// Units actually moved last month.
    public var moved: Double = 0
    /// Ducats earned last month after buying, transport and tolls.
    public var profit: Double = 0
    /// Months in a row the route lost money.
    public var monthsLosing: Int = 0

    public init(owner: CountryID, good: GoodID, from: MarketID, to: MarketID, volume: Double) {
        self.owner = owner
        self.good = good
        self.from = from
        self.to = to
        self.volume = volume
    }
}

/// What a market's owner does with traffic passing through it.
public enum TollPolicy: String, CaseIterable, Sendable, Codable {
    case open, high, closed

    public var displayName: String {
        switch self {
        case .open: return "Normal tolls"
        case .high: return "High tolls"
        case .closed: return "Closed to foreigners"
        }
    }

    public var rate: Double {
        switch self {
        case .open: return 0.04
        case .high: return 0.10
        case .closed: return 0
        }
    }
}

public enum TradeModel {
    /// Cost per market-to-market step, as a share of the buying price.
    public static let landTransport = 0.04
    public static let seaTransport = 0.02
    /// Value (ducats a year) a link can carry before routes are squeezed.
    public static let landLinkCapacity = 1500.0
    public static let seaLinkCapacity = 3000.0
    /// Country trade capacity: base, per market town owned, per building level.
    public static let baseCapacity = 40.0
    public static let marketTownCapacity = 30.0
    public static func buildingCapacity(_ key: String) -> Double {
        switch key {
        case "market_hall": return 10
        case "port": return 15
        case "caravanserai": return 8
        case "road": return 4
        default: return 0
        }
    }
    /// Capacity a route uses: units × base price × steps / 10.
    public static func capacityUse(volume: Double, basePrice: Double, steps: Int) -> Double {
        volume * basePrice * Double(max(steps, 1)) / 10
    }
    public static let losingMonthsBeforeAICancels = 6
    /// Computer countries run at most this many routes.
    public static let maxAIRoutes = 8
}

extension World {
    /// The country owning a market's centre.
    public func marketOwner(_ m: MarketID) -> CountryID? {
        provinces.owner[economy.markets.centre[m.index].index]
    }

    /// Whether a country's merchants may pass through or trade in a market.
    public func canTrade(_ trader: CountryID, in m: MarketID) -> Bool {
        guard let owner = marketOwner(m), owner != trader else { return true }
        if countries.embargoes[owner.index].contains(trader) { return false }
        if countries.tollPolicy[owner.index] == .closed { return false }
        return true
    }

    /// Cheapest path of markets (sea steps cost less), avoiding markets
    /// closed to this trader. Nil if there is no way.
    public func tradePath(for trader: CountryID, from: MarketID, to: MarketID) -> [MarketID]? {
        guard canTrade(trader, in: from), canTrade(trader, in: to) else { return nil }
        if from == to { return [from] }
        let prev = tradeTree(for: trader, from: to, stopAt: from)
        guard prev[from.index] >= 0 else { return nil }
        // The tree grows from `to`, so walking back from `from` gives the path in order.
        var path = [from.index]
        while path.last! != to.index { path.append(prev[path.last!]) }
        return path.map(MarketID.init)
    }

    /// Cheapest paths from one market to every other (Dijkstra). Returns,
    /// for each market, the next market back toward `root` (-1 = unreachable).
    /// Markets closed to the trader can be ends of a path but not passed through.
    public func tradeTree(for trader: CountryID, from root: MarketID, stopAt: MarketID? = nil) -> [Int] {
        let n = economy.markets.count
        var open = Array(repeating: true, count: n)
        for m in 0..<n { open[m] = canTrade(trader, in: MarketID(m)) }
        var dist = Array(repeating: Double.infinity, count: n)
        var prev = Array(repeating: -1, count: n)
        var heap = MinHeap()
        dist[root.index] = 0
        prev[root.index] = root.index
        heap.push(0, root.index, 0)
        while let (d, u, _) = heap.pop() {
            if d > dist[u] { continue }
            if let s = stopAt, u == s.index { break }
            // Only the root may be left by a trader barred from passing through.
            if u != root.index && !open[u] { continue }
            for (v, sea) in economy.marketAdjacency[u] {
                let nd = d + (sea ? 0.6 : 1.0)
                if nd < dist[v.index] {
                    dist[v.index] = nd
                    prev[v.index] = u
                    heap.push(nd, v.index, 0)
                }
            }
        }
        return prev
    }

    func isSeaStep(_ a: MarketID, _ b: MarketID) -> Bool {
        let k = economy.linkLookup.isEmpty ? -1 : economy.linkLookup[a.index * economy.markets.count + b.index]
        return k >= 0 && economy.marketLinkIsSea[k]
    }

    /// How much trade a country's merchants can run.
    public func tradeCapacity(_ c: CountryID) -> Double {
        var cap = TradeModel.baseCapacity
        let T = economy.buildings.typeCount
        let perType = economy.buildingTypes.map { TradeModel.buildingCapacity($0.key) }
        for p in 0..<provinces.count where provinces.owner[p] == c {
            for t in 0..<T where perType[t] > 0 {
                cap += perType[t] * Double(economy.buildings.level[p * T + t])
            }
        }
        for m in economy.markets.ids where marketOwner(m) == c {
            cap += TradeModel.marketTownCapacity
        }
        return cap
    }

    public func tradeCapacityUsed(_ c: CountryID) -> Double {
        economy.routes.filter { $0.owner == c }.reduce(0) {
            $0 + TradeModel.capacityUse(volume: $1.volume, basePrice: economy.goods.basePrice[$1.good.index],
                                        steps: max(1, $1.path.count - 1))
        }
    }

    /// Expected yearly profit of a route at today's prices (before link
    /// congestion), with its path; nil if there is no way.
    public func routeEstimate(owner: CountryID, good: GoodID, from: MarketID, to: MarketID, volume: Double,
                              knownPath: [MarketID]? = nil)
        -> (profit: Double, path: [MarketID], capacity: Double)? {
        guard from != to, let path = knownPath ?? tradePath(for: owner, from: from, to: to) else { return nil }
        let mk = economy.markets
        let buy = mk.price(from, good), sell = mk.price(to, good)
        var costShare = 0.0
        for k in 1..<path.count {
            costShare += isSeaStep(path[k - 1], path[k]) ? TradeModel.seaTransport : TradeModel.landTransport
            if k < path.count - 1, let o = marketOwner(path[k]), o != owner {
                costShare += countries.tollPolicy[o.index].rate
            }
        }
        let perUnit = sell - buy * (1 + costShare)
        let cap = TradeModel.capacityUse(volume: volume, basePrice: economy.goods.basePrice[good.index], steps: path.count - 1)
        return (perUnit * volume, path, cap)
    }
}

public enum TradeSystem {
    public static let volumes: [Double] = [10, 25, 50, 100]

    public enum Refusal: Equatable, Sendable {
        case sameMarket, noPath, noCapacity

        public var reason: String {
            switch self {
            case .sameMarket: return "Pick two different markets"
            case .noPath: return "No open way between these markets"
            case .noCapacity: return "Not enough trade capacity"
            }
        }
    }

    @discardableResult
    public static func create(_ world: inout World, owner: CountryID, good: GoodID, from: MarketID, to: MarketID,
                              volume: Double, ignoreCapacity: Bool = false) -> Refusal? {
        if from == to { return .sameMarket }
        guard let path = world.tradePath(for: owner, from: from, to: to) else { return .noPath }
        let use = TradeModel.capacityUse(volume: volume, basePrice: world.economy.goods.basePrice[good.index], steps: path.count - 1)
        if !ignoreCapacity && world.tradeCapacityUsed(owner) + use > world.tradeCapacity(owner) { return .noCapacity }
        var route = TradeRoute(owner: owner, good: good, from: from, to: to, volume: volume)
        route.path = path
        world.economy.routes.append(route)
        return nil
    }

    public static func cancel(_ world: inout World, route index: Int) {
        guard world.economy.routes.indices.contains(index) else { return }
        world.economy.routes.remove(at: index)
    }

    /// Re-finds every route's path (borders, embargoes and tolls change).
    public static func refreshPaths(_ world: inout World) {
        for k in world.economy.routes.indices {
            let r = world.economy.routes[k]
            world.economy.routes[k].path = world.tradePath(for: r.owner, from: r.from, to: r.to) ?? []
        }
    }

    /// Value a link can carry this month (ports, roads, market halls and
    /// caravanserais at either end raise it).
    static func linkCapacities(_ world: World) -> [Double] {
        let eco = world.economy
        let T = eco.buildings.typeCount
        func level(_ m: MarketID, _ key: String) -> Double {
            guard let t = eco.buildingType(key: key) else { return 0 }
            return Double(eco.buildings.level[eco.markets.centre[m.index].index * T + t.index])
        }
        var bonusLand = Array(repeating: 0.0, count: eco.markets.count)
        var bonusSea = bonusLand
        for m in eco.markets.ids {
            var routesBonus = 0.0
            if let t = eco.buildingTypes.firstIndex(where: { if case .routes = $0.effect { return true }; return false }),
               case .routes(let x) = eco.buildingTypes[t].effect {
                routesBonus = x * Double(eco.buildings.level[eco.markets.centre[m.index].index * T + t])
            }
            bonusLand[m.index] = 0.1 * level(m, "road") + 0.1 * level(m, "market_hall") + routesBonus
            bonusSea[m.index] = 0.2 * level(m, "port") + 0.1 * level(m, "market_hall")
        }
        return eco.marketLinks.enumerated().map { k, link in
            let sea = k < eco.marketLinkIsSea.count && eco.marketLinkIsSea[k]
            let bonus = sea ? bonusSea[link.0.index] + bonusSea[link.1.index]
                            : bonusLand[link.0.index] + bonusLand[link.1.index]
            return (sea ? TradeModel.seaLinkCapacity : TradeModel.landLinkCapacity) * (1 + bonus)
        }
    }

    /// Step 1 (inside the market month, before prices move): routes buy at
    /// the source and deliver at the destination. Returns units delivered per route.
    static func move(_ world: World, avail: [Double], S: inout [Double], D: inout [Double]) -> [Double] {
        let eco = world.economy
        let G = eco.goods.count
        guard !eco.routes.isEmpty else { return [] }
        let mc = eco.markets.count
        let capacity = linkCapacities(world)
        var load = Array(repeating: 0.0, count: eco.marketLinks.count)
        var routeLinks: [[Int]] = []
        for r in eco.routes {
            var links: [Int] = []
            if r.path.count > 1 {
                for k in 1..<r.path.count {
                    let l = eco.linkLookup[r.path[k - 1].index * mc + r.path[k].index]
                    if l >= 0 { links.append(l) }
                }
            }
            routeLinks.append(links)
            let value = r.volume * eco.goods.basePrice[r.good.index]
            for l in links { load[l] += value }
        }
        var delivered = Array(repeating: 0.0, count: eco.routes.count)
        for (k, r) in eco.routes.enumerated() {
            guard r.path.count > 1 else { continue }
            var scale = 1.0
            for l in routeLinks[k] where load[l] > capacity[l] { scale = min(scale, capacity[l] / load[l]) }
            let want = r.volume / 12 * scale
            let got = want * avail[r.from.index * G + r.good.index]
            D[r.from.index * G + r.good.index] += want
            S[r.to.index * G + r.good.index] += got
            delivered[k] = got
        }
        return delivered
    }

    /// Step 2 (after prices move): merchants' profits and tolls. Returns
    /// (profit per country, tolls per country) for the month.
    static func settle(_ world: inout World, delivered: [Double], sold: [Double]) -> ([Double], [Double]) {
        let C = world.countries.count
        var profit = Array(repeating: 0.0, count: C)
        var tolls = Array(repeating: 0.0, count: C)
        guard !delivered.isEmpty else { return (profit, tolls) }
        let G = world.economy.goods.count
        let price = world.economy.markets.price
        for k in world.economy.routes.indices {
            var r = world.economy.routes[k]
            let units = delivered[k]
            let buy = price[r.from.index * G + r.good.index]
            let sell = price[r.to.index * G + r.good.index] * sold[r.to.index * G + r.good.index]
            var cost = units * buy
            if r.path.count > 1 {
                for s in 1..<r.path.count {
                    cost += units * buy * (world.isSeaStep(r.path[s - 1], r.path[s]) ? TradeModel.seaTransport : TradeModel.landTransport)
                    if s < r.path.count - 1, let o = world.marketOwner(r.path[s]), o != r.owner {
                        let toll = units * buy * world.countries.tollPolicy[o.index].rate
                        tolls[o.index] += toll
                        cost += toll
                    }
                }
            }
            r.moved = units
            r.profit = units * sell - cost
            r.monthsLosing = r.profit < 0 ? r.monthsLosing + 1 : 0
            profit[r.owner.index] += r.profit
            world.economy.routes[k] = r
        }
        return (profit, tolls)
    }

    /// Computer countries drop routes that keep losing money and, a twelfth
    /// of them each month, open the most profitable route into their home market.
    public static func runAI(_ world: inout World, month: Int) {
        world.economy.routes.removeAll {
            !world.humanCountries.contains($0.owner) && $0.monthsLosing >= TradeModel.losingMonthsBeforeAICancels
        }
        let eco = world.economy
        let G = eco.goods.count
        for c in world.countries.ids where c.index % 12 == month % 12 && !world.humanCountries.contains(c) {
            guard let capital = world.countries.capital[c.index], let home = world.market(of: capital) else { continue }
            let free = world.tradeCapacity(c) - world.tradeCapacityUsed(c)
            guard free > 10, world.canTrade(c, in: home),
                  world.economy.routes.filter({ $0.owner == c }).count < TradeModel.maxAIRoutes else { continue }
            let tree = world.tradeTree(for: c, from: home)
            func path(from src: MarketID) -> [MarketID]? {
                guard tree[src.index] >= 0, world.canTrade(c, in: src) else { return nil }
                var p = [src.index]
                while p.last! != home.index && p.count <= 6 { p.append(tree[p.last!]) }
                return p.last! == home.index ? p.map(MarketID.init) : nil
            }
            var paths: [Int: [MarketID]] = [:]
            for m in eco.markets.ids where m != home {
                if let p = path(from: m), p.count <= 5 { paths[m.index] = p }
            }
            var best: (profit: Double, good: GoodID, from: MarketID, volume: Double)?
            for g in eco.goods.ids {
                let i = home.index * G + g.index
                guard eco.markets.demand[i] > eco.markets.supply[i] * 1.1 else { continue }
                let shortYearly = (eco.markets.demand[i] - eco.markets.supply[i]) * 12
                let volume = min(25, max(5, shortYearly * 0.5))
                for src in eco.markets.ids where src != home {
                    guard let known = paths[src.index] else { continue }
                    let s = src.index * G + g.index
                    guard eco.markets.supply[s] > eco.markets.demand[s] * 1.1,
                          eco.markets.price[s] < eco.markets.price[i] * 0.75 else { continue }
                    guard let est = world.routeEstimate(owner: c, good: g, from: src, to: home, volume: volume, knownPath: known),
                          est.capacity <= free, est.profit > 0 else { continue }
                    if best == nil || est.profit > best!.profit {
                        best = (est.profit, g, src, volume)
                    }
                }
            }
            if let b = best, b.profit > 2 {
                create(&world, owner: c, good: b.good, from: b.from, to: home, volume: b.volume)
            }
        }
    }
}
