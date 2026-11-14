import Testing
import Foundation
@testable import GezCore

@Suite("TenYearBalance")
struct TenYearBalanceTests {
    @Test("10-year headless simulation remains stable and balanced")
    func tenYearHeadlessRun() throws {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate, seed: 1453)

        let initialProvinces = sim.world.provinces.count
        let initialCountries = (0..<sim.world.countries.count).filter { !sim.world.provinces(ownedBy: CountryID($0)).isEmpty }.count
        let initialPop = sim.world.provinces.population.reduce(0, +)

        let t0 = Date()
        var dailySec = 0.0
        var monthlySec = 0.0

        // Run 10 years (3,650 days)
        for dayIndex in 0..<3650 {
            let s0 = Date()
            sim.tick()
            let dt = Date().timeIntervalSince(s0)
            if sim.date.isFirstOfMonth {
                monthlySec += dt
            } else {
                dailySec += dt
            }
            if dayIndex % 365 == 364 {
                let elapsed = Date().timeIntervalSince(t0)
                print(String(format: "[year %d] elapsed=%.2fs wars=%d aliveArmies=%d",
                             dayIndex / 365 + 1, elapsed,
                             sim.world.diplomacy.wars.count,
                             sim.world.military.armies.alive.filter { $0 }.count))
            }
        }
        let totalSec = Date().timeIntervalSince(t0)
        print(String(format: "[10y complete] total=%.2fs dailySum=%.2fs monthlySum=%.2fs wars=%d treaties=%d",
                     totalSec, dailySec, monthlySec, sim.world.diplomacy.wars.count, sim.world.diplomacy.treaties.count))

        let w = sim.world
        #expect(sim.date == GameDate(year: 1463, month: 5, day: 30))
        #expect(sim.ticksRun == 3650)

        // 1. No NaNs or non-finite values in economy/treasuries/pops
        for p in 0..<w.provinces.count {
            #expect(w.provinces.population[p].isFinite && w.provinces.population[p] >= 0)
            #expect(w.provinces.fortGarrison[p] >= 0 && w.provinces.fortGarrison[p] <= w.provinces.maxGarrison(of: ProvinceID(p)))
        }
        for c in 0..<w.countries.count {
            #expect(w.countries.treasury[c].isFinite)
            #expect(w.countries.inflation[c].isFinite && w.countries.inflation[c] >= 0)
            #expect(w.military.manpower[c].isFinite && w.military.manpower[c] >= 0)
        }
        for m in 0..<w.economy.markets.price.count {
            #expect(w.economy.markets.price[m].isFinite && w.economy.markets.price[m] > 0)
        }

        // 2. World population and inflation stay within sane 10-year bounds
        let finalPop = w.provinces.population.reduce(0, +)
        #expect(finalPop > initialPop * 0.70 && finalPop < initialPop * 1.60)

        let aliveCountries = (0..<w.countries.count).filter { idx in
            w.provinces.owner.contains(CountryID(idx))
        }
        let bankruptCount = aliveCountries.filter { w.countries.bankruptMonthsLeft[$0] > 0 }.count
        let hyperInflationCount = aliveCountries.filter { w.countries.inflation[$0] > 0.50 }.count
        #expect(bankruptCount < aliveCountries.count / 4)
        #expect(hyperInflationCount < aliveCountries.count / 5)

        // 3. Political dynamism without instant total map collapse
        #expect(aliveCountries.count >= initialCountries / 2)
        let largestCountryProvs = aliveCountries.map { cid in
            w.provinces.owner.filter { $0 == CountryID(cid) }.count
        }.max() ?? 0
        #expect(largestCountryProvs < initialProvinces / 3)

        // 4. Starting 1453 wars should not linger unclosed forever and war count stays bounded
        #expect(w.diplomacy.wars.count < 40)
        #expect(!w.diplomacy.treaties.isEmpty)
        #expect(!w.military.recentBattles.isEmpty)
    }
}
