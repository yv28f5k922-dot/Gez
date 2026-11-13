import CoreGraphics
import Foundation
import GezCore
import Observation

/// A town icon at a province's main town, in map-pixel coordinates.
struct TownIcon {
    let province: Int
    let position: CGPoint
    let development: Int
    let fortLevel: Int
    let isCapital: Bool
    /// Coastal town big enough to keep a harbour (development 3 or more).
    let isPort: Bool
}

/// A name to draw on the map, in map-pixel coordinates.
struct MapLabel: Identifiable {
    let id: Int
    let text: String
    let position: CGPoint
    /// Rough size of the thing being labelled, in map pixels.
    let pixelArea: Double
}

/// Bridges the simulation to SwiftUI. Runs a ~60 fps loop on the main actor,
/// turns real elapsed time into daily ticks via `GameClock`, and publishes a
/// `revision` counter so views redraw after each batch of ticks.
@MainActor
@Observable
final class GameModel {
    let simulation: Simulation
    let idMap: ProvinceIDMap
    let seaMap: ProvinceIDMap
    let geometry: MapGeometry
    /// GPU map renderer; nil only if Metal is unavailable (then the CPU
    /// picture in `mapImage` is used instead).
    let metal: MetalMapRenderer?

    private(set) var date: GameDate
    private(set) var revision: Int = 0

    var speed: GameSpeed = .paused {
        didSet {
            clock.speed = speed
            if speed != .paused { lastRunningSpeed = speed }
        }
    }
    var playerCountry: CountryID?

    // Map display
    var mapMode: MapMode = .political {
        didSet { if mapMode != oldValue { renderMap() } }
    }
    private(set) var mapImage: CGImage?
    /// Tests only: a pre-rendered Metal map shown instead of the live view,
    /// because SwiftUI snapshots can't capture Metal views.
    var snapshotMapImage: CGImage?
    private(set) var selectedProvince: ProvinceID?
    private(set) var selectedSea: SeaZoneID?
    /// Market whose prices are shown, if any.
    var openMarket: MarketID?
    var showBudget = false
    var showTrade = false
    /// Map positions of market towns, for drawing trade routes.
    private(set) var marketCentrePoints: [CGPoint] = []
    /// A route being planned in the trade window.
    var draftGood: GoodID?
    var draftFrom: MarketID?
    var draftTo: MarketID?
    var draftVolume: Double = 25
    private(set) var seaLabels: [MapLabel] = []
    private(set) var selectionOverlay: (image: CGImage, box: CGRect)?
    private(set) var countryLabels: [MapLabel] = []
    private(set) var provinceLabels: [MapLabel] = []
    private(set) var townIcons: [TownIcon] = []

    @ObservationIgnored private var clock = GameClock()
    @ObservationIgnored private var lastRunningSpeed: GameSpeed = .two
    @ObservationIgnored private var lastUpdate: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var renderGeneration = 0

    /// `useMetal: false` forces the CPU-drawn map (tests use it).
    init(useMetal: Bool = true) {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate)
        let map: ProvinceIDMap
        let seas: ProvinceIDMap
        do {
            map = try ProvinceIDMap.loadBundled()
            seas = try ProvinceIDMap.loadBundledSeas()
        } catch {
            preconditionFailure("Could not load province map: \(error)")
        }
        simulation = sim
        idMap = map
        seaMap = seas
        geometry = MapGeometry(map: map, provinceCount: sim.world.provinces.count)
        metal = useMetal ? MetalMapRenderer.makeDevice().flatMap { MetalMapRenderer(device: $0, idMap: map, seaMap: seas) } : nil
        date = sim.date
        playerCountry = sim.world.countries.id(forTag: Scenario1453.defaultPlayerTag)
        if let player = playerCountry {
            sim.world.humanCountries = [player]
        }
        rebuildLabels()
        renderMap()
        startLoop()
    }

    var world: World { simulation.world }

    // MARK: - Time

    func togglePause() {
        speed = (speed == .paused) ? lastRunningSpeed : .paused
    }

    func faster() {
        if let next = GameSpeed(rawValue: min(speed.rawValue + 1, GameSpeed.five.rawValue)) {
            speed = next
        }
    }

    func slower() {
        if let next = GameSpeed(rawValue: max(speed.rawValue - 1, GameSpeed.one.rawValue)) {
            speed = next
        }
    }

    private func startLoop() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000)
                self?.update()
            }
        }
    }

    private func update() {
        let now = Date()
        defer { lastUpdate = now }
        guard let last = lastUpdate else { return }
        let days = clock.daysToAdvance(elapsedSeconds: now.timeIntervalSince(last))
        guard days > 0 else { return }
        simulation.advance(days: days)
        date = simulation.date
        revision &+= 1
    }

    // MARK: - Map

    func select(sea: SeaZoneID?) {
        selectedSea = sea
        metal?.selectedSeaValue = sea.map { UInt32($0.index + 1) } ?? 0
        if sea != nil { select(province: nil, keepSea: true) }
    }

    /// Orders a building for the player. Returns why not, if it can't.
    @discardableResult
    func build(_ type: BuildingTypeID, in province: ProvinceID) -> BuildingSystem.Refusal? {
        guard let player = playerCountry else { return .notOwner }
        let result = BuildingSystem.start(&simulation.world, player, province, type)
        revision &+= 1
        return result
    }

    // MARK: Budget actions (player only)

    func setTax(_ c: TaxClass, level: Double) {
        guard let p = playerCountry else { return }
        simulation.world.countries.taxLevel[p.index][c.rawValue] = min(Finance.maxTaxLevel, max(0, level))
        revision &+= 1
    }

    func borrow(from bank: BankID, amount: Double) {
        guard let p = playerCountry else { return }
        FinanceSystem.borrow(&simulation.world, p, from: bank, amount: amount)
        revision &+= 1
    }

    func repay(loan index: Int) {
        FinanceSystem.repay(&simulation.world, loan: index)
        revision &+= 1
    }

    func debaseOnce() {
        guard let p = playerCountry else { return }
        FinanceSystem.debaseOnce(&simulation.world, p)
        revision &+= 1
    }

    func setDebasing(_ on: Bool) {
        guard let p = playerCountry, simulation.world.countries.bankruptMonthsLeft[p.index] == 0 || !on else { return }
        simulation.world.countries.debasing[p.index] = on
        revision &+= 1
    }

    // MARK: Trade actions (player only)

    @discardableResult
    func createRoute() -> TradeSystem.Refusal? {
        guard let p = playerCountry, let g = draftGood, let a = draftFrom, let b = draftTo else { return .noPath }
        let r = TradeSystem.create(&simulation.world, owner: p, good: g, from: a, to: b, volume: draftVolume)
        revision &+= 1
        return r
    }

    func cancelRoute(_ index: Int) {
        TradeSystem.cancel(&simulation.world, route: index)
        revision &+= 1
    }

    func setTollPolicy(_ policy: TollPolicy) {
        guard let p = playerCountry else { return }
        simulation.world.countries.tollPolicy[p.index] = policy
        TradeSystem.refreshPaths(&simulation.world)
        revision &+= 1
    }

    func toggleEmbargo(_ c: CountryID) {
        guard let p = playerCountry, c != p else { return }
        if simulation.world.countries.embargoes[p.index].contains(c) {
            simulation.world.countries.embargoes[p.index].remove(c)
        } else {
            simulation.world.countries.embargoes[p.index].insert(c)
        }
        TradeSystem.refreshPaths(&simulation.world)
        revision &+= 1
    }

    /// Opens the trade window with a route into this market planned.
    func planImport(_ good: GoodID, into market: MarketID) {
        draftGood = good
        draftTo = market
        draftFrom = nil
        showTrade = true
    }

    func select(province: ProvinceID?, keepSea: Bool = false) {
        if !keepSea && selectedSea != nil {
            selectedSea = nil
            metal?.selectedSeaValue = 0
        }
        selectedProvince = province
        metal?.selectedValue = province.map { UInt32($0.index + 2) } ?? 0
        if let province {
            selectionOverlay = MapRenderer.selectionOverlay(province: province, map: idMap, geometry: geometry)
                .map { (image: $0.0, box: $0.1) }
        } else {
            selectionOverlay = nil
        }
    }

    func select(mapX x: Int, y: Int) {
        if let hit = idMap.province(x: x, y: y) {
            select(province: hit == selectedProvince ? nil : hit)
        } else if let sea = seaMap.seaZone(x: x, y: y) {
            select(sea: sea == selectedSea ? nil : sea)
        } else {
            select(province: nil)
        }
    }

    /// Redraws the whole map image in the background. Call after a map mode
    /// change or when provinces change owner.
    func renderMap() {
        if let metal {
            metal.updateStyles(world: world, mode: mapMode)
            return
        }
        renderGeneration += 1
        let generation = renderGeneration
        let keys = MapRenderer.keys(world: world)
        let input = MapRenderer.Input(
            map: idMap,
            colors: MapPalette.colors(for: mapMode, world: world),
            ownerKey: keys.owner,
            stateKey: keys.state,
            rivers: world.rivers.map { river in river.points.map { CGPoint(x: $0.x, y: $0.y) } }
        )
        Task.detached(priority: .userInitiated) {
            let image = MapRenderer.render(input)
            await MainActor.run { [weak self] in
                guard let self, generation == self.renderGeneration else { return }
                self.mapImage = image
            }
        }
    }

    /// Rebuild town icons (call when development, forts or owners change).
    func rebuildTownIcons() {
        let p = world.provinces
        let capitals = Set(world.countries.capital.compactMap { $0?.index })
        var icons: [TownIcon] = []
        icons.reserveCapacity(p.count)
        for i in 0..<p.count {
            var point = world.map.point(for: p.location[i])
            // Towns placed in water (snapped seeds) fall back to the label point.
            if idMap.province(x: point.x, y: point.y)?.index != i { point = p.labelPoint[i] }
            icons.append(TownIcon(
                province: i,
                position: CGPoint(x: point.x, y: point.y),
                development: p.development[i],
                fortLevel: p.fortLevel[i],
                isCapital: capitals.contains(i),
                isPort: p.isCoastal[i] && p.development[i] >= 3 && !world.provinceSeas[i].isEmpty
            ))
        }
        // Big towns last so they draw on top.
        marketCentrePoints = world.economy.markets.centre.map { icons[$0.index].position }
        townIcons = icons.sorted { $0.development < $1.development }
    }

    private func rebuildLabels() {
        rebuildTownIcons()
        let p = world.provinces
        var provinceLabels: [MapLabel] = []
        provinceLabels.reserveCapacity(p.count)
        for i in 0..<p.count {
            let point = p.labelPoint[i]
            provinceLabels.append(MapLabel(
                id: i,
                text: p.name[i],
                position: CGPoint(x: point.x, y: point.y),
                pixelArea: Double(geometry.pixelCount[i])
            ))
        }

        // Country names sit in the middle of the country's most developed
        // connected block of land (its heartland, not a big empty outpost), pulled onto one of its provinces if the middle falls
        // outside it (a bay, or another country's enclave).
        let c = world.countries
        var countryLabels: [MapLabel] = []
        var visited = [Bool](repeating: false, count: p.count)
        var bestBlock = [[Int]](repeating: [], count: c.count)
        var bestArea = [Double](repeating: 0, count: c.count)
        var bestScore = [Double](repeating: -1, count: c.count)
        for start in 0..<p.count {
            guard !visited[start], let owner = p.owner[start]?.index else { continue }
            var block: [Int] = []
            var area = 0.0
            var score = 0.0
            var stack = [start]
            visited[start] = true
            while let i = stack.popLast() {
                block.append(i)
                area += Double(geometry.pixelCount[i])
                score += Double(p.development[i])
                for n in p.neighbors[i] where !visited[n.index] && p.owner[n.index]?.index == owner {
                    visited[n.index] = true
                    stack.append(n.index)
                }
            }
            if score > bestScore[owner] {
                bestScore[owner] = score
                bestArea[owner] = area
                bestBlock[owner] = block
            }
        }
        for k in 0..<c.count where !bestBlock[k].isEmpty {
            var sx = 0.0, sy = 0.0
            for i in bestBlock[k] {
                let a = Double(geometry.pixelCount[i])
                sx += Double(p.labelPoint[i].x) * a
                sy += Double(p.labelPoint[i].y) * a
            }
            let center = CGPoint(x: sx / bestArea[k], y: sy / bestArea[k])
            var best = center
            if idMap.province(x: Int(center.x), y: Int(center.y)).flatMap({ p.owner[$0.index]?.index }) != k {
                var bestDistance = Double.infinity
                for i in bestBlock[k] {
                    let lp = CGPoint(x: p.labelPoint[i].x, y: p.labelPoint[i].y)
                    let d = hypot(lp.x - center.x, lp.y - center.y)
                    if d < bestDistance {
                        bestDistance = d
                        best = lp
                    }
                }
            }
            countryLabels.append(MapLabel(id: k, text: c.name[k], position: best, pixelArea: bestArea[k]))
        }
        // Sea names sit at the middle of each zone's water.
        var sx = [Double](repeating: 0, count: world.seaZones.count)
        var sy = [Double](repeating: 0, count: world.seaZones.count)
        var sn = [Double](repeating: 0, count: world.seaZones.count)
        seaMap.values.withUnsafeBufferPointer { values in
            let w = seaMap.width
            for y in stride(from: 0, to: seaMap.height, by: 4) {
                for x in stride(from: 0, to: w, by: 4) {
                    let v = Int(values[y * w + x])
                    guard v > 0, v - 1 < sx.count else { continue }
                    sx[v - 1] += Double(x); sy[v - 1] += Double(y); sn[v - 1] += 1
                }
            }
        }
        var seaLabels: [MapLabel] = []
        for k in 0..<world.seaZones.count where sn[k] > 0 {
            var center = CGPoint(x: sx[k] / sn[k], y: sy[k] / sn[k])
            // If the middle is on land (a curved sea), use the nearest water of the zone.
            if seaMap.seaZone(x: Int(center.x), y: Int(center.y))?.index != k {
                var best = center, bestD = Double.infinity
                for y in stride(from: 0, to: seaMap.height, by: 8) {
                    for x in stride(from: 0, to: seaMap.width, by: 8) where seaMap.seaZone(x: x, y: y)?.index == k {
                        let d = hypot(Double(x) - center.x, Double(y) - center.y)
                        if d < bestD { bestD = d; best = CGPoint(x: x, y: y) }
                    }
                }
                center = best
            }
            seaLabels.append(MapLabel(id: k, text: world.seaZones.name[k], position: center, pixelArea: sn[k] * 16))
        }
        self.seaLabels = seaLabels.sorted { $0.pixelArea > $1.pixelArea }

        // Biggest first, so they win when labels would overlap.
        countryLabels.sort { $0.pixelArea > $1.pixelArea }
        provinceLabels.sort { $0.pixelArea > $1.pixelArea }
        self.provinceLabels = provinceLabels
        self.countryLabels = countryLabels
    }
}
