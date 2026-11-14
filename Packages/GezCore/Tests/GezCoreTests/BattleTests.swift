import XCTest
@testable import GezCore

final class BattleTests: XCTestCase {

    func testMultiDayAlternatingFireAndShockPhases() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let eng = world.countries.id(forTag: "ENG"),
              let bordeaux = world.provinces.id(named: "Bordeaux") else {
            XCTFail("Missing FRA, ENG, or Bordeaux")
            return
        }
        // FRA and ENG are already at war in 1453!
        // Remove existing armies in Bordeaux and spawn two matched armies for clean phase observation.
        for aid in world.military.armies(in: bordeaux) {
            world.military.armies.remove(aid)
        }

        let inf = world.military.unit("infantry")!
        let arc = world.military.unit("archers")!

        var attRegs: [Regiment] = []
        var defRegs: [Regiment] = []
        for _ in 0..<5 {
            attRegs.append(Regiment(type: inf.id, origin: .professional, men: 1_000, morale: 3.0))
            attRegs.append(Regiment(type: arc.id, origin: .professional, men: 1_000, morale: 2.8))
            defRegs.append(Regiment(type: inf.id, origin: .professional, men: 1_000, morale: 3.0))
            defRegs.append(Regiment(type: arc.id, origin: .professional, men: 1_000, morale: 2.8))
        }

        let attArmy = world.military.armies.append(name: "French Host", owner: fra, province: bordeaux, regiments: attRegs)
        let defArmy = world.military.armies.append(name: "English Host", owner: eng, province: bordeaux, regiments: defRegs)

        let sim = Simulation(world: world, startDate: Scenario1453.startDate, seed: 42)

        // Day 1: Fire phase starts
        sim.tick()
        guard let b1 = sim.world.military.battle(in: bordeaux) else {
            XCTFail("Expected battle to start on day 1")
            return
        }
        XCTAssertEqual(b1.dayCount, 1)
        XCTAssertEqual(b1.currentPhase, .fire)
        XCTAssertEqual(b1.phaseDay, 1)
        XCTAssertTrue(sim.world.military.isInBattle(attArmy))
        XCTAssertTrue(sim.world.military.isInBattle(defArmy))

        // Day 3: still Fire phase, phaseDay 3
        sim.advance(days: 2)
        guard let b3 = sim.world.military.battle(in: bordeaux) else {
            XCTFail("Battle ended unexpectedly early on day 3")
            return
        }
        XCTAssertEqual(b3.dayCount, 3)
        XCTAssertEqual(b3.currentPhase, .fire)
        XCTAssertEqual(b3.phaseDay, 3)

        // Day 4: switches to Shock phase, phaseDay 1
        sim.tick()
        guard let b4 = sim.world.military.battle(in: bordeaux) else {
            XCTFail("Battle ended unexpectedly early on day 4")
            return
        }
        XCTAssertEqual(b4.dayCount, 4)
        XCTAssertEqual(b4.currentPhase, .shock)
        XCTAssertEqual(b4.phaseDay, 1)

        // Run until battle concludes (within 25 days)
        for _ in 0..<25 {
            if sim.world.military.battle(in: bordeaux) == nil { break }
            sim.tick()
        }
        XCTAssertNil(sim.world.military.battle(in: bordeaux), "Battle should finish within 25 days")
        guard let report = sim.world.military.recentBattles.last else {
            XCTFail("Expected battle report after conclusion")
            return
        }
        XCTAssertEqual(report.province, bordeaux)
        XCTAssertGreaterThan(report.attackerLosses, 0)
        XCTAssertGreaterThan(report.defenderLosses, 0)
        XCTAssertGreaterThanOrEqual(report.daysFought, 4)
    }

    func testLevyCasualtiesPermanentlyReduceHomeProvincePops() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let eng = world.countries.id(forTag: "ENG"),
              let chartres = world.provinces.id(named: "Chartres"),
              let bordeaux = world.provinces.id(named: "Bordeaux") else {
            XCTFail("Missing entities")
            return
        }

        // Clear pre-existing armies in Bordeaux so only our test clash runs
        for aid in world.military.armies(in: bordeaux) { world.military.armies.remove(aid) }

        guard case .success(let levyArmy) = ArmySystem.raiseLevies(&world, fra, in: chartres) else {
            XCTFail("Expected raising levies to succeed")
            return
        }
        let raisedMen = world.military.armies.totalMen(of: levyArmy)
        XCTAssertGreaterThan(raisedMen, 500)

        // Move FRA levy army to Bordeaux to fight an ENG force
        world.military.armies.province[Int(levyArmy.rawValue)] = bordeaux
        let inf = world.military.unit("infantry")!
        let engRegs = (0..<3).map { _ in Regiment(type: inf.id, origin: .professional, men: 1_000, morale: 3.0) }
        world.military.armies.append(name: "English Defence", owner: eng, province: bordeaux, regiments: engRegs)

        let sim = Simulation(world: world, startDate: Scenario1453.startDate, seed: 777)
        // Tick until battle starts and finishes
        for _ in 0..<25 {
            sim.tick()
            if sim.world.military.battle(in: bordeaux) == nil && sim.world.military.recentBattles.contains(where: { $0.province == bordeaux }) {
                break
            }
        }

        guard let report = sim.world.military.recentBattles.last(where: { $0.province == bordeaux }) else {
            XCTFail("Expected Battle of Bordeaux report to complete")
            return
        }
        XCTAssertGreaterThan(report.attackerLosses, 0, "Levies should sustain real battle casualties")

        // Verify surviving levy count matches raised - attackerLosses
        let survivingMen = sim.world.military.armies.totalMen(of: levyArmy)
        XCTAssertEqual(raisedMen - survivingMen, report.attackerLosses)

        // Disband remaining levies back to home province Chartres and verify only survivors return to pops
        var w2 = sim.world
        let popRightBeforeDisband = w2.provinces.population[chartres.index]
        ArmySystem.disband(&w2, army: levyArmy)
        let popRightAfterDisband = w2.provinces.population[chartres.index]

        let returnedPops = popRightAfterDisband - popRightBeforeDisband
        XCTAssertEqual(returnedPops, Double(survivingMen), accuracy: 15.0, "Only surviving levies may return; casualties permanently reduce pops")
        XCTAssertLessThan(returnedPops, Double(raisedMen), "Casualties must reduce returned pop below raised count")
    }

    func testShatteredRetreatAndUnfortifiedTakeoverOccupation() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let eng = world.countries.id(forTag: "ENG") else {
            XCTFail("Missing FRA or ENG")
            return
        }

        // Find an unfortified English province neighbouring France, or make an English province unfortified.
        let engProvs = world.provinces(ownedBy: eng)
        guard let targetProv = engProvs.first else {
            XCTFail("No English provinces found")
            return
        }
        world.provinces.fortLevel[targetProv.index] = 0

        // Clear all armies in targetProv
        for aid in world.military.armies(in: targetProv) { world.military.armies.remove(aid) }

        let inf = world.military.unit("infantry")!
        // Large French force (12 regiments) vs moderate English force (5 regiments -> loses battle after ~5 days without instant overrun)
        let attRegs = (0..<12).map { _ in Regiment(type: inf.id, origin: .professional, men: 1_000, morale: 3.0) }
        let defRegs = (0..<5).map { _ in Regiment(type: inf.id, origin: .professional, men: 1_000, morale: 3.0) }

        world.military.armies.append(name: "Grand Armee", owner: fra, province: targetProv, regiments: attRegs)
        let engArmy = world.military.armies.append(name: "English Garrison", owner: eng, province: targetProv, regiments: defRegs)

        // France is player-controlled here, so the war AI does not march the
        // victorious army away before it can occupy the province.
        world.humanCountries.insert(fra)
        let sim = Simulation(world: world, startDate: Scenario1453.startDate, seed: 999)

        // Advance until battle finishes
        for _ in 0..<25 {
            sim.tick()
            if sim.world.military.battle(in: targetProv) == nil { break }
        }
        XCTAssertNil(sim.world.military.battle(in: targetProv))
        XCTAssertEqual(sim.world.military.recentBattles.last?.winner, fra)

        // Defeated English army should either shatter-retreat away (if alive) or be wiped; check if alive
        let engIdx = Int(engArmy.rawValue)
        if sim.world.military.armies.alive[engIdx] {
            XCTAssertTrue(sim.world.military.armies.isRetreating[engIdx] || sim.world.military.armies.province[engIdx] != targetProv)
        }

        // Now French army stands unopposed in unfortified English province -> should occupy in 10 days!
        XCTAssertNil(sim.world.provinces.occupiedBy[targetProv.index])
        sim.advance(days: 10)
        XCTAssertEqual(sim.world.provinces.occupiedBy[targetProv.index], fra, "Unfortified province should be occupied by France after 10 days")
        XCTAssertEqual(sim.world.provinces.controller(of: targetProv), fra)

        // Now move an English army back onto the occupied unfortified province (move French out first)
        for aid in sim.world.military.armies(in: targetProv) where sim.world.military.armies.owner[Int(aid.rawValue)] == fra {
            sim.world.military.armies.remove(aid)
        }
        let liberatorRegs = (0..<3).map { _ in Regiment(type: inf.id, origin: .professional, men: 1_000, morale: 3.0) }
        sim.world.military.armies.append(name: "Relief Force", owner: eng, province: targetProv, regiments: liberatorRegs)

        // Liberate in 5 days!
        sim.advance(days: 5)
        XCTAssertNil(sim.world.provinces.occupiedBy[targetProv.index], "Friendly force should liberate unfortified province in 5 days")
        XCTAssertEqual(sim.world.provinces.controller(of: targetProv), eng)
    }

    func testRiverCrossingAndMountainTerrainFavorDefender() {
        XCTAssertEqual(BattleModel.terrainAttackerPenalty(.plains), 0)
        XCTAssertEqual(BattleModel.terrainAttackerPenalty(.hills), -1)
        XCTAssertEqual(BattleModel.terrainAttackerPenalty(.mountains), -2)

        func runSample(province: ProvinceID, prevProvince: ProvinceID, riverBorder: Bool) -> (attLoss: Int, defLoss: Int) {
            var world = Scenario1453.makeWorld()
            let fra = world.countries.id(forTag: "FRA")!
            let eng = world.countries.id(forTag: "ENG")!
            world.provinces.owner[province.index] = eng
            if riverBorder {
                world.riverBorders.insert(ProvincePair(prevProvince, province))
            } else {
                world.riverBorders.remove(ProvincePair(prevProvince, province))
            }

            for aid in world.military.armies(in: province) { world.military.armies.remove(aid) }

            let inf = world.military.unit("infantry")!
            let attRegs = (0..<6).map { _ in Regiment(type: inf.id, origin: .professional, men: 1_000, morale: 3.0) }
            let defRegs = (0..<6).map { _ in Regiment(type: inf.id, origin: .professional, men: 1_000, morale: 3.0) }

            let attArmy = world.military.armies.append(name: "Attackers", owner: fra, province: province, regiments: attRegs)
            world.military.armies.previousProvince[Int(attArmy.rawValue)] = prevProvince
            world.military.armies.append(name: "Defenders", owner: eng, province: province, regiments: defRegs)

            let sim = Simulation(world: world, startDate: Scenario1453.startDate, seed: 12345)
            for _ in 0..<25 {
                sim.tick()
                if sim.world.military.battle(in: province) == nil { break }
            }
            let r = sim.world.military.recentBattles.last!
            return (r.attackerLosses, r.defenderLosses)
        }

        let baseWorld = Scenario1453.makeWorld()
        let plainsProv = baseWorld.provinces.ids.first(where: { baseWorld.provinces.terrain[$0.index] == .plains })!
        let plainsPrev = baseWorld.provinces.neighbors[plainsProv.index].first!
        let mtnProv = baseWorld.provinces.ids.first(where: { baseWorld.provinces.terrain[$0.index] == .mountains })!
        let mtnPrev = baseWorld.provinces.neighbors[mtnProv.index].first!

        let openPlains = runSample(province: plainsProv, prevProvince: plainsPrev, riverBorder: false)
        let mountainAndRiver = runSample(province: mtnProv, prevProvince: mtnPrev, riverBorder: true)

        XCTAssertLessThan(mountainAndRiver.defLoss, openPlains.defLoss, "Defender in mountains across a river should take fewer casualties than on open plains")
    }
}
