import XCTest
@testable import GezCore

final class WarDeclarationTests: XCTestCase {

    func testAvailableCasusBelliReconquestAndClaims() {
        let world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let eng = world.countries.id(forTag: "ENG"),
              let cas = world.countries.id(forTag: "CAS"),
              let gra = world.countries.id(forTag: "GRA"),
              let pol = world.countries.id(forTag: "POL"),
              let teu = world.countries.id(forTag: "TEU"),
              let tur = world.countries.id(forTag: "TUR"),
              let ser = world.countries.id(forTag: "SER") else {
            XCTFail("Missing expected countries")
            return
        }

        // France vs England: Reconquest of Bordeaux
        let fraCbs = world.diplomacy.availableCasusBelli(attacker: fra, defender: eng, in: world)
        XCTAssertTrue(fraCbs.contains(where: { $0.type == .reconquest && $0.name.contains("Bordeaux") }))

        // Castile vs Granada: Conquest of Granada / Malaga and Holy War
        let casCbs = world.diplomacy.availableCasusBelli(attacker: cas, defender: gra, in: world)
        XCTAssertTrue(casCbs.contains(where: { $0.type == .claim && $0.name.contains("Granada") }))
        XCTAssertTrue(casCbs.contains(where: { $0.type == .holyWar }))

        // Poland vs Teutonic Order: Conquest of Danzig / Marienburg
        let polCbs = world.diplomacy.availableCasusBelli(attacker: pol, defender: teu, in: world)
        XCTAssertTrue(polCbs.contains(where: { $0.type == .claim && $0.name.contains("Danzig") }))

        // Ottomans vs Serbia: Holy war and claims
        let turCbs = world.diplomacy.availableCasusBelli(attacker: tur, defender: ser, in: world)
        XCTAssertTrue(turCbs.contains(where: { $0.type == .holyWar }))
        XCTAssertTrue(turCbs.contains(where: { $0.type == .noCB }))
    }

    func testDeclareWarNoCBAppliesStabilityAndAEPenalties() {
        var world = Scenario1453.makeWorld()
        guard let cas = world.countries.id(forTag: "CAS"),
              let nav = world.countries.id(forTag: "NAV") else {
            XCTFail("Missing CAS or NAV")
            return
        }

        let initialStab = world.government.stability[cas.index]
        let date = GameDate(year: 1453, month: 6, day: 1)

        let result = world.declareWar(
            attacker: cas,
            defender: nav,
            casusBelli: .noCB,
            warGoal: .superiority,
            breakTruce: false,
            date: date
        )

        switch result {
        case .success(let war):
            XCTAssertEqual(war.primaryAttacker, cas)
            XCTAssertEqual(war.primaryDefender, nav)
            XCTAssertEqual(war.casusBelli, .noCB)
            XCTAssertEqual(world.government.stability[cas.index], initialStab - 2)
            XCTAssertGreaterThan(world.diplomacy.aggressiveExpansion(of: cas, by: nav), 0)
            XCTAssertEqual(world.diplomacy.opinion(of: nav, by: cas), -100)
            XCTAssertEqual(world.diplomacy.opinion(of: cas, by: nav), -100)
            XCTAssertTrue(world.diplomacy.isAtWar(cas, nav))
        case .failure(let err):
            XCTFail("Expected war declaration to succeed, got: \(err)")
        }
    }

    func testDeclareWarTruceBreakRequiresConfirmationAndPenalizes() {
        var world = Scenario1453.makeWorld()
        guard let cas = world.countries.id(forTag: "CAS"),
              let por = world.countries.id(forTag: "POR") else {
            XCTFail("Missing CAS or POR")
            return
        }

        // Add a truce until 1458
        world.diplomacy.addTreaty(Treaty(
            first: cas,
            second: por,
            type: .truce,
            expiry: GameDate(year: 1458, month: 1, day: 1)
        ))

        let date = GameDate(year: 1453, month: 6, day: 1)

        // Declaring without breakTruce flag must fail
        let failResult = world.declareWar(
            attacker: cas,
            defender: por,
            casusBelli: .noCB,
            warGoal: .superiority,
            breakTruce: false,
            date: date
        )
        if case .success = failResult {
            XCTFail("Expected failure due to active truce")
        }

        // Declaring with breakTruce = true must succeed with -5 stability penalty
        let startStab = world.government.stability[cas.index]
        let successResult = world.declareWar(
            attacker: cas,
            defender: por,
            casusBelli: .noCB,
            warGoal: .superiority,
            breakTruce: true,
            date: date
        )

        switch successResult {
        case .success(let war):
            XCTAssertEqual(war.primaryAttacker, cas)
            // -5 from truce break + -2 from No-CB, clamped at -3
            XCTAssertEqual(world.government.stability[cas.index], max(-3, startStab - 7))
            XCTAssertFalse(world.diplomacy.hasTruce(cas, por))
        case .failure(let err):
            XCTFail("Expected war declaration with breakTruce to succeed: \(err)")
        }
    }

    func testCallToArmsAcceptedInDefensiveWar() {
        var world = Scenario1453.makeWorld()
        guard let cas = world.countries.id(forTag: "CAS"),
              let nav = world.countries.id(forTag: "NAV"),
              let ara = world.countries.id(forTag: "ARA") else {
            XCTFail("Missing countries")
            return
        }

        // Form alliance between NAV and ARA
        world.diplomacy.addTreaty(Treaty(first: nav, second: ara, type: .alliance))
        world.diplomacy.setTrust(of: nav, by: ara, value: 75)
        world.diplomacy.setOpinion(of: nav, by: ara, value: 80)
        world.diplomacy.setOpinion(of: cas, by: ara, value: -30)

        // CAS declares war on NAV
        let date = GameDate(year: 1453, month: 6, day: 1)
        let warResult = world.declareWar(
            attacker: cas,
            defender: nav,
            casusBelli: .noCB,
            warGoal: .superiority,
            breakTruce: false,
            date: date
        )

        guard case .success(let war) = warResult else {
            XCTFail("War declaration failed")
            return
        }

        // NAV calls ARA into defensive war
        let cta = world.callToArms(caller: nav, ally: ara, warID: war.id)
        XCTAssertEqual(cta, .accepted)

        // ARA is now a defender in the war
        guard let updatedWar = world.diplomacy.wars.first(where: { $0.id == war.id }) else {
            XCTFail("War missing")
            return
        }
        XCTAssertTrue(updatedWar.isDefender(ara))
        XCTAssertTrue(world.diplomacy.isAtWar(ara, cas))
    }

    func testCallToArmsDeclinedBreaksAlliance() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let sco = world.countries.id(forTag: "SCO"),
              let hab = world.countries.id(forTag: "HAB") else {
            XCTFail("Missing countries")
            return
        }

        // Alliance between FRA and SCO
        world.diplomacy.addTreaty(Treaty(first: fra, second: sco, type: .alliance))
        // SCO has active truce with HAB and very low trust in FRA
        world.diplomacy.addTreaty(Treaty(first: sco, second: hab, type: .truce))
        world.diplomacy.setTrust(of: fra, by: sco, value: 20)
        world.diplomacy.setOpinion(of: fra, by: sco, value: -20)

        // FRA declares offensive war on HAB
        let date = GameDate(year: 1453, month: 6, day: 1)
        let warResult = world.declareWar(
            attacker: fra,
            defender: hab,
            casusBelli: .noCB,
            warGoal: .superiority,
            breakTruce: false,
            date: date
        )

        guard case .success(let war) = warResult else {
            XCTFail("War declaration failed")
            return
        }

        // FRA calls SCO into offensive war against HAB
        let initialTrust = world.diplomacy.trust(of: sco, by: fra)
        let initialOpinion = world.diplomacy.opinion(of: sco, by: fra)
        let cta = world.callToArms(caller: fra, ally: sco, warID: war.id)

        if case .declined(let reasons) = cta {
            XCTAssertFalse(reasons.isEmpty)
            // Alliance should be broken
            XCTAssertFalse(world.diplomacy.areAllies(fra, sco))
            // Trust drops by 25
            XCTAssertEqual(world.diplomacy.trust(of: sco, by: fra), max(0, initialTrust - 25))
            // Dishonored alliance opinion penalty (-50)
            XCTAssertEqual(world.diplomacy.opinion(of: sco, by: fra), initialOpinion - 50)
        } else {
            XCTFail("Expected call to arms to be declined")
        }
    }

    func testSubjectAutomaticCallIns() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let cas = world.countries.id(forTag: "CAS") else {
            XCTFail("Missing FRA or CAS")
            return
        }

        let date = GameDate(year: 1453, month: 6, day: 1)
        let result = world.declareWar(
            attacker: fra,
            defender: cas,
            casusBelli: .noCB,
            warGoal: .superiority,
            breakTruce: false,
            date: date
        )

        guard case .success(let war) = result else {
            XCTFail("War failed")
            return
        }

        // France's subjects (e.g. Foix, etc.) should be in attackers
        let fraSubjects = world.countries.subjects(of: fra)
        for s in fraSubjects {
            XCTAssertTrue(war.isAttacker(s), "Subject \(world.countries.tag[s.index]) should join overlord FRA")
        }
    }
}
