import XCTest
import Foundation
@testable import GezCore

/// Times each system of the daily tick separately. Runs only when
/// GEZ_PROFILE=1 (the "Profile the daily tick" CI job, by hand), so normal
/// test runs are unaffected. Keep the call order in step with
/// `Simulation.tick()`.
final class ProfileTests: XCTestCase {
    func testSystemTimings() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GEZ_PROFILE"] == "1",
                          "profiling: runs in the Profile job only")
        var world = Scenario1453.makeWorld()
        var random = GameRandom(seed: 1453)
        var date = Scenario1453.startDate
        var totals: [String: Double] = [:]
        var calls: [String: Int] = [:]

        func time(_ name: String, _ body: () -> Void) {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            let end = DispatchTime.now().uptimeNanoseconds
            totals[name, default: 0] += Double(end - start) / 1e9
            calls[name, default: 0] += 1
        }

        let days = Int(ProcessInfo.processInfo.environment["GEZ_PROFILE_DAYS"] ?? "120") ?? 120
        let overall = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<days {
            date.advanceOneDay()
            time("ArmySystem.runDaily") { ArmySystem.runDaily(&world, date: date, random: &random) }
            time("BattleSystem.runDaily") { BattleSystem.runDaily(&world, date: date, random: &random) }
            time("SiegeSystem.runDaily") { SiegeSystem.runDaily(&world, date: date, random: &random) }
            time("DiplomacySystem.runDaily") { DiplomacySystem.runDaily(&world, date: date) }
            if date.day % 7 == 1 {
                time("DiplomacyAISystem.runWeeklyMilitary") { DiplomacyAISystem.runWeeklyMilitary(&world, date: date) }
            }
            if date.isFirstOfMonth {
                time("TradeSystem.refreshPaths") { TradeSystem.refreshPaths(&world) }
                time("EconomySystem.runMonthly") { EconomySystem.runMonthly(&world) }
                time("BuildingSystem.runMonthly") { BuildingSystem.runMonthly(&world) }
                time("ArmySystem.runMonthly") { ArmySystem.runMonthly(&world, date: date, random: &random) }
                time("SiegeSystem.runMonthly") { SiegeSystem.runMonthly(&world) }
                time("FinanceSystem.runMonthly") { FinanceSystem.runMonthly(&world) }
                time("FinanceSystem.runAI") { FinanceSystem.runAI(&world) }
                time("TradeSystem.runAI") { TradeSystem.runAI(&world, month: date.month) }
                time("BuildingSystem.runAI") { BuildingSystem.runAI(&world, month: date.month) }
                time("ArmySystem.runAI") { ArmySystem.runAI(&world, month: date.month, date: date) }
                time("PopulationSystem.runMonthly") { PopulationSystem.runMonthly(&world) }
                time("CharacterSystem.runMonthly") { CharacterSystem.runMonthly(&world, date: date, random: &random) }
                time("VassalSystem.runMonthly") { VassalSystem.runMonthly(&world, date: date, random: &random) }
                time("GovernmentSystem.runMonthly") { GovernmentSystem.runMonthly(&world, date: date, random: &random) }
                time("DiplomacySystem.runMonthly") { DiplomacySystem.runMonthly(&world, date: date) }
                time("DiplomacyAISystem.runMonthly") { DiplomacyAISystem.runMonthly(&world, date: date, random: &random) }
            }
            if date.isFirstOfYear {
                time("CharacterSystem.runYearly") { CharacterSystem.runYearly(&world, date: date, random: &random) }
                time("VassalSystem.runYearly") { VassalSystem.runYearly(&world, date: date, random: &random) }
            }
        }
        let wall = Double(DispatchTime.now().uptimeNanoseconds - overall) / 1e9
        print("PROFILE total \(days) days: \(wall)s (\(wall / Double(days) * 1000) ms/day)")
        print("PROFILE armies=\(world.military.armies.count) battles=\(world.military.battles.count) sieges=\(world.military.sieges.count) wars=\(world.diplomacy.wars.count)")
        for (name, secs) in totals.sorted(by: { $0.value > $1.value }) {
            let n = calls[name] ?? 1
            print("PROFILE \(name): \(secs)s total, \(secs / Double(n) * 1000) ms/call, \(n) calls")
        }
    }
}
