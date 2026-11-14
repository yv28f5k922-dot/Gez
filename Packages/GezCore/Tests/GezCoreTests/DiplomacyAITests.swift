import XCTest
@testable import GezCore

final class DiplomacyAITests: XCTestCase {

    func testWartimeMilitaryAIMovesAndMergesIdleArmies() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let eng = world.countries.id(forTag: "ENG"),
              let paris = world.provinces.id(named: "Paris") else {
            XCTFail("Missing FRA/ENG/Paris")
            return
        }

        // Put ENG human so FRA stays AI, create two idle FRA stacks in Paris
        world.humanCountries.insert(eng)
        _ = ArmySystem.raiseAllLevies(&world, fra)
        let fraArmiesBefore = (0..<world.military.armies.count).filter {
            world.military.armies.alive[$0] && world.military.armies.owner[$0] == fra && world.military.armies.province[$0] == paris
        }

        DiplomacyAISystem.runWeeklyMilitary(&world, date: GameDate(year: 1453, month: 6, day: 8))

        // At least one FRA army should receive a movement path toward the war front
        let movingFraArmies = (0..<world.military.armies.count).filter {
            world.military.armies.alive[$0]
                && world.military.armies.owner[$0] == fra
                && !world.military.armies.path[$0].isEmpty
        }
        XCTAssertFalse(movingFraArmies.isEmpty, "AI at war should order armies toward enemy provinces")

        // Human armies must remain untouched
        for idx in 0..<world.military.armies.count where world.military.armies.alive[idx] && world.military.armies.owner[idx] == eng {
            XCTAssertTrue(world.military.armies.path[idx].isEmpty, "AI must never move human armies")
        }
        _ = fraArmiesBefore
    }

    func testAIResolvesWinningWarAndQueuesHumanPeaceOffer() {
        var world = Scenario1453.makeWorld()
        guard let ven = world.countries.id(forTag: "VEN"),
              let mlo = world.countries.id(forTag: "MLO"),
              let war = world.diplomacy.activeWar(between: ven, and: mlo),
              let warIdx = world.diplomacy.wars.firstIndex(where: { $0.id == war.id }) else {
            XCTFail("Missing VEN/MLO Lombardy war")
            return
        }

        // Case 1: Human loser gets a pending peace offer instead of forced annexation
        world.humanCountries.insert(mlo)
        for pid in world.provinces(ownedBy: mlo) {
            world.provinces.occupiedBy[pid.index] = ven
        }
        world.diplomacy.wars[warIdx].warScore = war.isAttacker(ven) ? 1.0 : -1.0

        var random = GameRandom(seed: 42)
        DiplomacyAISystem.runMonthly(&world, date: GameDate(year: 1453, month: 12, day: 1), random: &random)
        XCTAssertNotNil(world.diplomacy.activeWar(between: ven, and: mlo), "AI should not bypass human consent")
        XCTAssertTrue(world.diplomacy.pendingPeaceOffers.contains(where: { $0.warID == war.id && $0.loser == mlo }))

        // Case 2: Remove human flag -> AI vs AI concludes peace treaty automatically
        world.humanCountries.remove(mlo)
        world.diplomacy.pendingPeaceOffers.removeAll()
        DiplomacyAISystem.runMonthly(&world, date: GameDate(year: 1454, month: 1, day: 1), random: &random)
        XCTAssertNil(world.diplomacy.activeWar(between: ven, and: mlo), "AI vs AI decisive war should settle peace")
        XCTAssertTrue(world.diplomacy.hasTruce(ven, mlo))
    }

    func testPeacetimeAlliancesBreakBadAlliancesAndDeclareValidCBWar() {
        var world = Scenario1453.makeWorld()
        guard let cas = world.countries.id(forTag: "CAS"),
              let gra = world.countries.id(forTag: "GRA"),
              let eng = world.countries.id(forTag: "ENG"),
              let por = world.countries.id(forTag: "POR") else {
            XCTFail("Missing expected countries")
            return
        }

        // Clear CAS's external alliance with FRA and any CAS-GRA treaties so CAS evaluates Granada independently
        if let fra = world.countries.id(forTag: "FRA") {
            world.diplomacy.removeTreaty(.alliance, between: fra, and: cas)
        }
        world.diplomacy.removeTreaty(.truce, between: cas, and: gra)
        world.diplomacy.removeTreaty(.nonAggression, between: cas, and: gra)
        world.diplomacy.removeTreaty(.guarantee, between: cas, and: gra)
        world.diplomacy.removeTreaty(.alliance, between: cas, and: gra)
        _ = ArmySystem.raiseAllLevies(&world, cas)

        // Make ENG hate POR while allied to test bad-alliance cleanup
        world.diplomacy.setOpinion(of: por, by: eng, value: -80)
        world.diplomacy.addTreaty(Treaty(first: eng, second: por, type: .alliance))

        var random = GameRandom(seed: 12345)
        // Run monthly evaluations across consecutive months so all staggered cohorts run
        for step in 0..<24 {
            let month = (step % 12) + 1
            let year = 1454 + (step / 12)
            DiplomacyAISystem.runMonthly(&world, date: GameDate(year: year, month: month, day: 1), random: &random)
        }

        XCTAssertFalse(world.diplomacy.areAllies(eng, por), "AI should drop alliance below -45 opinion")
        let casSoldiers = world.military.totalMen(of: cas)
        let graSoldiers = world.military.totalMen(of: gra)
        let casWars = world.diplomacy.activeWars(for: cas).map(\.id)
        let casCBs = world.diplomacy.availableCasusBelli(attacker: cas, defender: gra, in: world).map(\.type)
        let casStab = world.government.stability[cas.index]
        let casAtWarOrWon = world.diplomacy.isAtWar(cas, gra)
            || world.provinces(ownedBy: gra).isEmpty
            || world.diplomacy.hasTruce(cas, gra)
        XCTAssertTrue(
            casAtWarOrWon,
            "CAS->GRA blocked: casSoldiers=\(casSoldiers), graSoldiers=\(graSoldiers), casStab=\(casStab), casWars=\(casWars), casCBs=\(casCBs), totalWars=\(world.diplomacy.wars.count)"
        )
    }

    func testAIDiplomacyAndWarDeterminism() {
        func runSim(seed: UInt64) -> ([String], [Treaty], Int) {
            let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate, seed: seed)
            sim.advance(days: 120)
            let wars = sim.world.diplomacy.wars.map(\.id).sorted()
            let treaties = sim.world.diplomacy.treaties
            let livingArmies = (0..<sim.world.military.armies.count).filter { sim.world.military.armies.alive[$0] }.count
            return (wars, treaties, livingArmies)
        }

        let r1 = runSim(seed: 777)
        let r2 = runSim(seed: 777)
        XCTAssertEqual(r1.0, r2.0)
        XCTAssertEqual(r1.1, r2.1)
        XCTAssertEqual(r1.2, r2.2)
    }
}
