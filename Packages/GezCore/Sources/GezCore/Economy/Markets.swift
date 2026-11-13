import Foundation

public struct MarketID: Hashable, Sendable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

/// Trade centres. Each has a price, supply and demand for every good,
/// stored flat: `[market * goodCount + good]`.
public struct MarketTable: Sendable {
    public private(set) var name: [String] = []
    public private(set) var centre: [ProvinceID] = []
    public private(set) var goodCount: Int = 0
    /// Ducats per unit.
    public var price: [Double] = []
    /// Units available last month (local output, imports and exchange).
    public var supply: [Double] = []
    /// Units wanted last month.
    public var demand: [Double] = []
    /// Share of demand that was met last month (0 to 1).
    public var met: [Double] = []
    /// Units arriving from beyond the map each year.
    public var imports: [Double] = []
    /// One-off purchases (building materials) added to next month's demand.
    public var pendingDemand: [Double] = []

    public init() {}

    public var count: Int { name.count }
    public var ids: [MarketID] { (0..<count).map(MarketID.init) }

    public mutating func setGoodCount(_ n: Int) {
        precondition(count == 0, "set the good count before adding markets")
        goodCount = n
    }

    @discardableResult
    public mutating func add(name: String, centre: ProvinceID, basePrices: [Double]) -> MarketID {
        precondition(basePrices.count == goodCount)
        let id = MarketID(count)
        self.name.append(name)
        self.centre.append(centre)
        price += basePrices
        supply += Array(repeating: 0, count: goodCount)
        demand += Array(repeating: 0, count: goodCount)
        met += Array(repeating: 1, count: goodCount)
        imports += Array(repeating: 0, count: goodCount)
        pendingDemand += Array(repeating: 0, count: goodCount)
        return id
    }

    @inline(__always)
    public func slot(_ m: MarketID, _ g: GoodID) -> Int { m.index * goodCount + g.index }

    public func price(_ m: MarketID, _ g: GoodID) -> Double { price[slot(m, g)] }

    public func id(named name: String) -> MarketID? {
        self.name.firstIndex(of: name).map(MarketID.init)
    }
}

/// The whole economy: goods, recipes, needs, markets and producers.
public struct Economy: Sendable {
    public var goods = GoodTable()
    public var recipes: [Recipe] = []
    public var needs: [NeedGroup] = []
    public var markets = MarketTable()
    public var producers = ProducerTable()
    /// The market each province trades in.
    public var provinceMarket: [MarketID] = []
    /// Pairs of markets that touch by land or sea; surplus flows between them.
    public var marketLinks: [(MarketID, MarketID)] = []
    public var buildingTypes: [BuildingType] = []
    public var buildings = BuildingTable()
    /// Units made last month by each workshop building, `[province * typeCount + type]`.
    public var workshopOutput: [Double] = []
    /// Ducats earned last month by each workshop building.
    public var workshopValue: [Double] = []
    /// Burgher jobs per workshop level, in thousands.
    public static let jobsPerLevel = 2.5
    /// Share of burghers who can work in workshops.
    public static let workshopShare = 0.7

    public init() {}

    public func buildingType(key: String) -> BuildingTypeID? {
        buildingTypes.firstIndex { $0.key == key }.map(BuildingTypeID.init)
    }

    public func provinces(in market: MarketID) -> [ProvinceID] {
        provinceMarket.indices.filter { provinceMarket[$0] == market }.map(ProvinceID.init)
    }
}

extension World {
    /// Joins every province to the market that is cheapest to reach.
    /// Travel cost is distance times terrain difficulty; sea travel is
    /// cheaper, with a fixed cost for loading and unloading at a port.
    public mutating func assignMarkets() {
        let n = provinces.count
        let z = seaZones.count
        let centres = economy.markets.centre
        guard !centres.isEmpty else { return }

        var seaLocation: [GeoPoint] = []
        for k in 0..<z {
            let coast = seaZones.coast[k]
            guard !coast.isEmpty else {
                seaLocation.append(GeoPoint(latitude: 0, longitude: 0))
                continue
            }
            let lat = coast.reduce(0) { $0 + provinces.location[$1.index].latitude } / Double(coast.count)
            let lon = coast.reduce(0) { $0 + provinces.location[$1.index].longitude } / Double(coast.count)
            seaLocation.append(GeoPoint(latitude: lat, longitude: lon))
        }
        func location(_ node: Int) -> GeoPoint { node < n ? provinces.location[node] : seaLocation[node - n] }

        var dist = Array(repeating: Double.infinity, count: n + z)
        var owner = Array(repeating: -1, count: n + z)
        var heap = MinHeap()
        for (m, c) in centres.enumerated() where dist[c.index] > 0 {
            dist[c.index] = 0
            owner[c.index] = m
            heap.push(0, c.index, m)
        }
        while let (d, u, m) = heap.pop() {
            if d > dist[u] { continue }
            func relax(_ v: Int, _ cost: Double) {
                let nd = d + cost
                if nd < dist[v] {
                    dist[v] = nd
                    owner[v] = m
                    heap.push(nd, v, m)
                }
            }
            if u < n {
                let tu = MarketModel.terrainCost(provinces.terrain[u])
                for v in provinces.neighbors[u] {
                    let tv = MarketModel.terrainCost(provinces.terrain[v.index])
                    relax(v.index, MarketModel.km(location(u), location(v.index)) * (tu + tv) / 2)
                }
                if u < provinceSeas.count {
                    for s in provinceSeas[u] {
                        relax(n + s.index, MarketModel.km(location(u), seaLocation[s.index]) * MarketModel.seaCost + MarketModel.portCost)
                    }
                }
            } else {
                let s = u - n
                for w in seaZones.neighbors[s] {
                    relax(n + w.index, MarketModel.km(seaLocation[s], seaLocation[w.index]) * MarketModel.seaCost)
                }
                for p in seaZones.coast[s] {
                    relax(p.index, MarketModel.km(seaLocation[s], location(p.index)) * MarketModel.seaCost + MarketModel.portCost)
                }
            }
        }
        economy.provinceMarket = (0..<n).map { MarketID(max(owner[$0], 0)) }

        var links = Set<Int>()
        let mc = economy.markets.count
        func link(_ a: MarketID, _ b: MarketID) {
            guard a != b else { return }
            links.insert(min(a.index, b.index) * mc + max(a.index, b.index))
        }
        for p in 0..<n {
            for q in provinces.neighbors[p] {
                link(economy.provinceMarket[p], economy.provinceMarket[q.index])
            }
        }
        for s in 0..<z {
            var touching = Set(seaZones.coast[s].map { economy.provinceMarket[$0.index].index })
            for w in seaZones.neighbors[s] {
                touching.formUnion(seaZones.coast[w.index].map { economy.provinceMarket[$0.index].index })
            }
            let list = touching.sorted()
            for i in 0..<list.count {
                for j in (i + 1)..<max(i + 1, list.count) {
                    link(MarketID(list[i]), MarketID(list[j]))
                }
            }
        }
        economy.marketLinks = links.sorted().map { (MarketID($0 / mc), MarketID($0 % mc)) }
    }
}

/// A small binary heap for Dijkstra, ordered by cost then node index so the
/// result never depends on insertion order.
struct MinHeap {
    private var items: [(Double, Int, Int)] = []

    mutating func push(_ cost: Double, _ node: Int, _ tag: Int) {
        items.append((cost, node, tag))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if less(items[i], items[parent]) {
                items.swapAt(i, parent)
                i = parent
            } else { break }
        }
    }

    mutating func pop() -> (Double, Int, Int)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var best = i
                if l < items.count && less(items[l], items[best]) { best = l }
                if r < items.count && less(items[r], items[best]) { best = r }
                if best == i { break }
                items.swapAt(i, best)
                i = best
            }
        }
        return top
    }

    private func less(_ a: (Double, Int, Int), _ b: (Double, Int, Int)) -> Bool {
        a.0 != b.0 ? a.0 < b.0 : (a.1 != b.1 ? a.1 < b.1 : a.2 < b.2)
    }
}
