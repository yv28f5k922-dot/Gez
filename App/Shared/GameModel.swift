import Foundation
import GezCore
import Observation

/// Bridges the simulation to SwiftUI. Runs a ~60 fps loop on the main actor,
/// turns real elapsed time into daily ticks via `GameClock`, and publishes a
/// `revision` counter so views redraw after each batch of ticks.
@MainActor
@Observable
final class GameModel {
    let simulation: Simulation
    private(set) var date: GameDate
    private(set) var revision: Int = 0

    var speed: GameSpeed = .paused {
        didSet {
            clock.speed = speed
            if speed != .paused { lastRunningSpeed = speed }
        }
    }
    var selectedProvince: ProvinceID?
    var playerCountry: CountryID?

    @ObservationIgnored private var clock = GameClock()
    @ObservationIgnored private var lastRunningSpeed: GameSpeed = .two
    @ObservationIgnored private var lastUpdate: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?

    init() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate)
        simulation = sim
        date = sim.date
        playerCountry = sim.world.countries.id(forTag: Scenario1453.defaultPlayerTag)
        startLoop()
    }

    var world: World { simulation.world }

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
}
