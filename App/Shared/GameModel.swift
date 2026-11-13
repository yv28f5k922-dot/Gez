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

        // Country names sit in the middle of the country's largest connected
        // block of land, pulled onto one of its provinces if the middle falls
        // outside it (a bay, or another country's enclave).
        let c = world.countries
        var countryLabels: [MapLabel] = []
        var visited = [Bool](repeating: false, count: p.count)
        var bestBlock = [[Int]](repeating: [], count: c.count)
        var bestArea = [Double](repeating: 0, count: c.count)
        for start in 0..<p.count {
            guard !visited[start], let owner = p.owner[start]?.index else { continue }
            var block: [Int] = []
            var area = 0.0
            var stack = [start]
            visited[start] = true
            while let i = stack.popLast() {
                block.append(i)
                area += Double(geometry.pixelCount[i])
                for n in p.neighbors[i] where !visited[n.index] && p.owner[n.index]?.index == owner {
                    visited[n.index] = true
                    stack.append(n.index)
                }
            }
            if area > bestArea[owner] {
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
        // Biggest first, so they win when labels would overlap.
        countryLabels.sort { $0.pixelArea > $1.pixelArea }
        provinceLabels.sort { $0.pixelArea > $1.pixelArea }
        self.provinceLabels = provinceLabels
        self.countryLabels = countryLabels
    }
}
