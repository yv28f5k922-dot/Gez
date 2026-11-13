import CoreGraphics
import Foundation
import GezCore
import Observation

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
    let geometry: MapGeometry

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
    private(set) var selectedProvince: ProvinceID?
    private(set) var selectionOverlay: (image: CGImage, box: CGRect)?
    private(set) var countryLabels: [MapLabel] = []
    private(set) var provinceLabels: [MapLabel] = []

    @ObservationIgnored private var clock = GameClock()
    @ObservationIgnored private var lastRunningSpeed: GameSpeed = .two
    @ObservationIgnored private var lastUpdate: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var renderGeneration = 0

    init() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate)
        let map: ProvinceIDMap
        do {
            map = try ProvinceIDMap.loadBundled()
        } catch {
            preconditionFailure("Could not load province map: \(error)")
        }
        simulation = sim
        idMap = map
        geometry = MapGeometry(map: map, provinceCount: sim.world.provinces.count)
        date = sim.date
        playerCountry = sim.world.countries.id(forTag: Scenario1453.defaultPlayerTag)
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

    func select(province: ProvinceID?) {
        selectedProvince = province
        if let province {
            selectionOverlay = MapRenderer.selectionOverlay(province: province, map: idMap, geometry: geometry)
                .map { (image: $0.0, box: $0.1) }
        } else {
            selectionOverlay = nil
        }
    }

    func select(mapX x: Int, y: Int) {
        let hit = idMap.province(x: x, y: y)
        select(province: hit == selectedProvince ? nil : hit)
    }

    /// Redraws the whole map image in the background. Call after a map mode
    /// change or when provinces change owner.
    func renderMap() {
        renderGeneration += 1
        let generation = renderGeneration
        let keys = MapRenderer.keys(world: world)
        let input = MapRenderer.Input(
            map: idMap,
            colors: MapPalette.colors(for: mapMode, world: world),
            ownerKey: keys.owner,
            stateKey: keys.state
        )
        Task.detached(priority: .userInitiated) {
            let image = MapRenderer.render(input)
            await MainActor.run { [weak self] in
                guard let self, generation == self.renderGeneration else { return }
                self.mapImage = image
            }
        }
    }

    private func rebuildLabels() {
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
        self.provinceLabels = provinceLabels

        // Country names sit at the area-weighted middle of their land, pulled
        // to the nearest of their own provinces so they never float at sea.
        let c = world.countries
        var sumX = [Double](repeating: 0, count: c.count)
        var sumY = [Double](repeating: 0, count: c.count)
        var area = [Double](repeating: 0, count: c.count)
        for i in 0..<p.count {
            guard let owner = p.owner[i]?.index else { continue }
            let a = Double(geometry.pixelCount[i])
            sumX[owner] += Double(p.labelPoint[i].x) * a
            sumY[owner] += Double(p.labelPoint[i].y) * a
            area[owner] += a
        }
        var countryLabels: [MapLabel] = []
        for k in 0..<c.count where area[k] > 0 {
            let center = CGPoint(x: sumX[k] / area[k], y: sumY[k] / area[k])
            var best = center
            var bestDistance = Double.infinity
            for i in 0..<p.count where p.owner[i]?.index == k {
                let lp = CGPoint(x: p.labelPoint[i].x, y: p.labelPoint[i].y)
                let d = hypot(lp.x - center.x, lp.y - center.y)
                if d < bestDistance {
                    bestDistance = d
                    best = lp
                }
            }
            // Keep the centre if it lies on the country's own land.
            if let hit = idMap.province(x: Int(center.x), y: Int(center.y)), p.owner[hit.index]?.index == k {
                best = center
            }
            countryLabels.append(MapLabel(id: k, text: c.name[k], position: best, pixelArea: area[k]))
        }
        self.countryLabels = countryLabels
    }
}
