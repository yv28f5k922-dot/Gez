import XCTest
@testable import GezCore

final class SiegeTests: XCTestCase {

    func testZoneOfControlBlocksMovementPastFortUntilCaptured() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let eng = world.countries.id(forTag: "ENG"),
              let paris = world.provinces.id(named: "Paris") else {
            XCTFail("Missing FRA/ENG/Paris")
            return
        }

        // Find a fortified ENG-controlled province adjacent to an unfortified FRA border (or pick a fortified province + neighbor chain)
        // Use a deterministic graph setup around Bordeaux -> Calais / Normandy, or pick a clean 3-province chain owned by ENG adjacent to FRA:
        let engProvs = world.provinces(ownedBy: eng)
        guard let borderEng = engProvs.first(where: { p in
            world.provinces.neighbors[p.index].contains { world.provinces.owner[$0.index] == fra }
        }) else {
            XCTFail("Expected ENG province bordering FRA")
            return
        }
        guard let fraStart = world.provinces.neighbors[borderEng.index].first(where: { world.provinces.owner[$0.index] == fra }),
              let behindFort = world.provinces.neighbors[borderEng.index].first(where: { nb in
                  nb != fraStart && world.provinces.owner[nb.index] == eng
              }) else {
            // Ensure we have a fort on borderEng
            return
        }

        // Fortify borderEng to level 2 with 2000 garrison, remove other ENG armies so only ZoC governs path
        world.provinces.fortLevel[borderEng.index] = 2
        world.provinces.fortGarrison[borderEng.index] = 2000

        guard let regType = world.military.unitTypes.first?.id else { return }
        let testArmy = world.military.armies.append(
            name: "Siege Host",
            owner: fra,
            province: fraStart,
            regiments: [Regiment(type: regType, origin: .professional, men: 4000, morale: 1.0)]
        )

        // Ensure behindFort isn't directly reachable without going through borderEng (or check direct step from borderEng -> behindFort)
        XCTAssertTrue(
            SiegeSystem.canStep(world, for: fra, from: fraStart, to: borderEng, pathStart: fraStart),
            "Should be able to march from friendly land onto hostile fort"
        )
        XCTAssertFalse(
            SiegeSystem.canStep(world, for: fra, from: borderEng, to: behindFort, pathStart: fraStart),
            "Active hostile fort must block stepping past it deeper into enemy land"
        )

        // Stepping back to friendly start is always permitted
        XCTAssertTrue(SiegeSystem.canStep(world, for: fra, from: borderEng, to: fraStart, pathStart: fraStart))

        // Capturing the fort lifts ZoC immediately
        world.provinces.occupiedBy[borderEng.index] = fra
        XCTAssertTrue(
            SiegeSystem.canStep(world, for: fra, from: borderEng, to: behindFort, pathStart: fraStart),
            "Occupying fort lifts ZoC and allows advancing behind it"
        )
        _ = (paris, testArmy)
    }

    func testMinimumBesiegersAndMonthlySiegeRollToSurrender() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let eng = world.countries.id(forTag: "ENG"),
              let bordeaux = world.provinces.id(named: "Bordeaux") else {
            XCTFail("Missing FRA/ENG/Bordeaux")
            return
        }

        // Clear existing armies in Bordeaux
        for aid in world.military.armies(in: bordeaux) {
            world.military.armies.remove(aid)
        }
        world.provinces.fortLevel[bordeaux.index] = 2
        world.provinces.fortGarrison[bordeaux.index] = 2000
        world.provinces.occupiedBy[bordeaux.index] = nil

        guard let infType = world.military.unitTypes.first(where: { $0.category == .infantry })?.id,
              let artType = world.military.unitTypes.first(where: { $0.category == .artillery })?.id else {
            XCTFail("Missing unit types")
            return
        }

        // 1,200 men is below level 2 requirement (2,000) -> no siege starts
        let smallHost = world.military.armies.append(
            name: "Understrength Host",
            owner: fra,
            province: bordeaux,
            regiments: [Regiment(type: infType, origin: .professional, men: 1200, morale: 1.0)]
        )
        var random = GameRandom(seed: 101)
        SiegeSystem.runDaily(&world, date: GameDate(year: 1453, month: 6, day: 1), random: &random)
        XCTAssertNil(world.military.siege(in: bordeaux), "Need at least fortLevel * 1000 men to besiege")

        // Reinforce with infantry + artillery bombards to surpass 2,000 and add artillery bonus
        world.military.armies.remove(smallHost)
        _ = world.military.armies.append(
            name: "Royal Siege Train",
            owner: fra,
            province: bordeaux,
            regiments: [
                Regiment(type: infType, origin: .professional, men: 3000, morale: 1.0),
                Regiment(type: artType, origin: .professional, men: 500, morale: 1.0),
                Regiment(type: artType, origin: .professional, men: 500, morale: 1.0),
                Regiment(type: artType, origin: .professional, men: 500, morale: 1.0)
            ]
        )

        var day = 0
        while world.provinces.occupiedBy[bordeaux.index] == nil && day < 500 {
            day += 1
            SiegeSystem.runDaily(&world, date: GameDate(year: 1453, month: 6, day: 1), random: &random)
        }

        XCTAssertEqual(world.provinces.occupiedBy[bordeaux.index], fra, "Besieged fort with artillery must eventually surrender")
        XCTAssertNil(world.military.siege(in: bordeaux))
        XCTAssertLessThan(day, 500)
        _ = eng
    }

    func testStormAssaultRequiresBreachAndCapturesWithCasualties() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let eng = world.countries.id(forTag: "ENG"),
              let bordeaux = world.provinces.id(named: "Bordeaux") else {
            XCTFail("Missing FRA/ENG/Bordeaux")
            return
        }

        for aid in world.military.armies(in: bordeaux) {
            world.military.armies.remove(aid)
        }
        world.provinces.fortLevel[bordeaux.index] = 1
        world.provinces.fortGarrison[bordeaux.index] = 1000
        world.provinces.occupiedBy[bordeaux.index] = nil

        guard let infType = world.military.unitTypes.first(where: { $0.category == .infantry })?.id else { return }
        let host = world.military.armies.append(
            name: "Assault Force",
            owner: fra,
            province: bordeaux,
            regiments: [Regiment(type: infType, origin: .professional, men: 6000, morale: 1.0)]
        )

        var random = GameRandom(seed: 2026)
        SiegeSystem.runDaily(&world, date: GameDate(year: 1453, month: 6, day: 1), random: &random)
        XCTAssertNotNil(world.military.siege(in: bordeaux))

        // Unbreached assault must be refused
        let refused = SiegeSystem.assaultFort(&world, province: bordeaux, attacker: fra, random: &random)
        XCTAssertFalse(refused.captured)
        XCTAssertNotNil(refused.refusalReason)

        // Breach the walls -> storm succeeds with real casualties on both sides
        world.military.sieges[0].breached = true
        let assault = SiegeSystem.assaultFort(&world, province: bordeaux, attacker: fra, random: &random)
        XCTAssertNil(assault.refusalReason)
        XCTAssertTrue(assault.captured)
        XCTAssertGreaterThan(assault.attackerLosses, 0)
        XCTAssertGreaterThan(assault.garrisonLosses, 0)
        XCTAssertEqual(world.provinces.occupiedBy[bordeaux.index], fra)
        XCTAssertLessThan(world.military.armies.totalMen(of: host), 6000)
        _ = eng
    }
}
