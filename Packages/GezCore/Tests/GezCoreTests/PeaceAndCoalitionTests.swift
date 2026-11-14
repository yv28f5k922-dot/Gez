import XCTest
@testable import GezCore

final class PeaceAndCoalitionTests: XCTestCase {

    func testWarScoreAccumulationTickingAndTotalOccupation() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let eng = world.countries.id(forTag: "ENG"),
              let war = world.diplomacy.activeWar(between: fra, and: eng),
              let warIndex = world.diplomacy.wars.firstIndex(where: { $0.id == war.id }) else {
            XCTFail("Missing FRA/ENG Hundred Years War")
            return
        }

        world.diplomacy.wars[warIndex].battleWarScore = 0.0
        world.diplomacy.wars[warIndex].tickingWarScore = 0.0
        world.diplomacy.wars[warIndex].warScore = 0.0

        let bordeaux = world.provinces.id(named: "Bordeaux")
        if case .conquerProvince(let goalProv) = war.warGoal {
            world.provinces.occupiedBy[goalProv.index] = fra
            for _ in 0..<20 {
                DiplomacySystem.runDaily(&world, date: GameDate(year: 1453, month: 6, day: 15))
            }
            let updatedWar = world.diplomacy.wars[warIndex]
            XCTAssertEqual(updatedWar.tickingWarScore, 0.02, accuracy: 0.0001)
            XCTAssertGreaterThan(updatedWar.warScore, 0.02)
        } else if let bdx = bordeaux {
            world.provinces.occupiedBy[bdx.index] = fra
            DiplomacySystem.runDaily(&world, date: GameDate(year: 1453, month: 6, day: 15))
        }

        // Now occupy all ENG provinces by FRA -> total occupation yields +1.00 (100% war score)
        for pid in world.provinces(ownedBy: eng) {
            world.provinces.occupiedBy[pid.index] = fra
        }
        DiplomacySystem.runDaily(&world, date: GameDate(year: 1453, month: 6, day: 16))
        XCTAssertEqual(world.diplomacy.wars[warIndex].warScore, 1.0, accuracy: 0.0001)
    }

    func testPeaceCostTruceScalingAndZeroAEReconquest() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA"),
              let eng = world.countries.id(forTag: "ENG"),
              let war = world.diplomacy.activeWar(between: fra, and: eng) else {
            XCTFail("Missing FRA/ENG war")
            return
        }

        XCTAssertEqual(world.diplomacy.truceDurationYears(forPeaceCost: 0), 5)
        XCTAssertEqual(world.diplomacy.truceDurationYears(forPeaceCost: 50), 10)
        XCTAssertEqual(world.diplomacy.truceDurationYears(forPeaceCost: 100), 15)

        let engProvs = world.provinces(ownedBy: eng)
        guard let coreProv = engProvs.first(where: { world.provinces.cores[$0.index].contains(fra) }) else {
            XCTFail("Expected FRA core in ENG territory")
            return
        }
        world.provinces.occupiedBy[coreProv.index] = fra

        let reconquestOffer = PeaceOffer(
            warID: war.id,
            winner: fra,
            loser: eng,
            demands: [.cedeProvince(province: coreProv, to: fra)]
        )
        let aeReconquest = world.diplomacy.aggressiveExpansionForPeace(reconquestOffer, war: war, in: world)
        XCTAssertEqual(aeReconquest, 0.0, accuracy: 0.001, "Reconquest of own core generates zero AE")
    }

    func testExecutePeaceDemandsCedeReturnCoreIndemnityAndReparations() {
        var world = Scenario1453.makeWorld()
        guard let mlo = world.countries.id(forTag: "MLO"),
              let ven = world.countries.id(forTag: "VEN"),
              let war = world.diplomacy.activeWar(between: ven, and: mlo) else {
            XCTFail("Missing VEN/MLO Lombardy war")
            return
        }

        let mloProvs = world.provinces(ownedBy: mlo)
        XCTAssertFalse(mloProvs.isEmpty)
        let targetProv = mloProvs[0]

        for pid in mloProvs {
            world.provinces.occupiedBy[pid.index] = ven
        }
        if let idx = world.diplomacy.wars.firstIndex(where: { $0.id == war.id }) {
            world.diplomacy.wars[idx].warScore = war.isAttacker(ven) ? 1.0 : -1.0
        }

        let venInitialTreasury = world.countries.treasury[ven.index]
        world.countries.treasury[mlo.index] = 500.0
        world.countries.lastMonthlyIncome[mlo.index] = 100.0

        let offer = PeaceOffer(
            warID: war.id,
            winner: ven,
            loser: mlo,
            demands: [
                .cedeProvince(province: targetProv, to: ven),
                .ducatIndemnity(amount: 50.0),
                .warReparations
            ]
        )

        let peaceDate = GameDate(year: 1454, month: 4, day: 9)
        let result = world.executePeaceTreaty(offer, date: peaceDate, forceAccept: true)
        switch result {
        case .failure(let err):
            XCTFail("Peace failed: \(err)")
        case .success(let truceYears):
            XCTAssertGreaterThanOrEqual(truceYears, 5)
            XCTAssertLessThanOrEqual(truceYears, 15)
        }

        XCTAssertNil(world.diplomacy.activeWar(between: ven, and: mlo))
        XCTAssertTrue(world.diplomacy.hasTruce(ven, mlo))
        XCTAssertEqual(world.provinces.owner[targetProv.index], ven)
        XCTAssertNil(world.provinces.occupiedBy[targetProv.index])
        XCTAssertGreaterThan(world.countries.treasury[ven.index], venInitialTreasury)
        XCTAssertEqual(world.diplomacy.warReparations.count, 1)

        // Monthly tick transfers 10% of MLO's monthly income (10.0) to VEN
        let venBeforeRep = world.countries.treasury[ven.index]
        let mloBeforeRep = world.countries.treasury[mlo.index]
        DiplomacySystem.runMonthly(&world, date: GameDate(year: 1454, month: 5, day: 1))
        XCTAssertEqual(world.countries.treasury[ven.index] - venBeforeRep, 10.0, accuracy: 0.01)
        XCTAssertEqual(mloBeforeRep - world.countries.treasury[mlo.index], 10.0, accuracy: 0.01)
    }

    func testVassalizeAnnulTreatyReturnCoreAndSeparatePeace() {
        var world = Scenario1453.makeWorld()
        guard let cas = world.countries.id(forTag: "CAS"),
              let nav = world.countries.id(forTag: "NAV"),
              let por = world.countries.id(forTag: "POR") else {
            XCTFail("Missing CAS/NAV/POR")
            return
        }

        // Clear truce between CAS and POR for clean test, ally NAV & POR
        world.diplomacy.removeTreaty(.truce, between: cas, and: por)
        world.diplomacy.addTreaty(Treaty(first: nav, second: por, type: .alliance))

        let warRes = world.declareWar(
            attacker: cas,
            defender: nav,
            casusBelli: .noCB,
            warGoal: .superiority,
            breakTruce: false,
            date: GameDate(year: 1453, month: 6, day: 1)
        )
        guard case .success(let war) = warRes else {
            XCTFail("Expected war declaration success")
            return
        }

        // Call POR into defender side
        _ = world.callToArms(caller: nav, ally: por, warID: war.id)
        XCTAssertNotNil(world.diplomacy.activeWar(between: cas, and: por))

        // Separate peace with POR demanding annulTreaty with NAV & warReparations
        let sepOffer = PeaceOffer(
            warID: war.id,
            winner: cas,
            loser: por,
            demands: [.annulTreaty(with: nav), .warReparations]
        )
        let sepRes = world.executePeaceTreaty(sepOffer, date: GameDate(year: 1453, month: 7, day: 1), forceAccept: true)
        if case .failure(let err) = sepRes { XCTFail("Separate peace failed: \(err)") }

        // War against NAV still active, POR exited, alliance between NAV & POR annulled
        XCTAssertNil(world.diplomacy.activeWar(between: cas, and: por))
        XCTAssertNotNil(world.diplomacy.activeWar(between: cas, and: nav))
        XCTAssertFalse(world.diplomacy.hasTreaty(.alliance, between: nav, and: por))

        // Now vassalize NAV in main peace
        let navOffer = PeaceOffer(
            warID: war.id,
            winner: cas,
            loser: nav,
            demands: [.makeVassal]
        )
        let navRes = world.executePeaceTreaty(navOffer, date: GameDate(year: 1453, month: 8, day: 1), forceAccept: true)
        if case .failure(let err) = navRes { XCTFail("Vassal peace failed: \(err)") }

        XCTAssertNil(world.diplomacy.activeWar(between: cas, and: nav))
        XCTAssertEqual(world.countries.overlord[nav.index], cas)
        XCTAssertEqual(world.countries.subjectType[nav.index], .vassal)

        // Test Return Core in a war (VEN vs TUR returning a SER core)
        guard let tur = world.countries.id(forTag: "TUR"),
              let ven = world.countries.id(forTag: "VEN"),
              let ser = world.countries.id(forTag: "SER") else {
            return
        }
        let turProvs = world.provinces(ownedBy: tur)
        if let provToReturn = turProvs.first {
            world.provinces.cores[provToReturn.index].insert(ser)
            let wRes = world.declareWar(
                attacker: ven,
                defender: tur,
                casusBelli: .noCB,
                warGoal: .superiority,
                breakTruce: false,
                date: GameDate(year: 1454, month: 1, day: 1)
            )
            if case .success(let turWar) = wRes {
                let rcOffer = PeaceOffer(
                    warID: turWar.id,
                    winner: ven,
                    loser: tur,
                    demands: [.returnCore(province: provToReturn, to: ser)]
                )
                let rcRes = world.executePeaceTreaty(rcOffer, date: GameDate(year: 1454, month: 2, day: 1), forceAccept: true)
                if case .success = rcRes {
                    XCTAssertEqual(world.provinces.owner[provToReturn.index], ser)
                } else {
                    XCTFail("returnCore failed: \(rcRes)")
                }
            }
        }
    }

    func testCoalitionFormationCallInAndDissolution() {
        var world = Scenario1453.makeWorld()
        guard let fra = world.countries.id(forTag: "FRA") else {
            XCTFail("Missing FRA")
            return
        }

        let candidates = ["BUR", "PRO", "SAV", "LOR", "BRB", "MNT"]
            .compactMap { world.countries.id(forTag: $0) }
            .filter { !world.diplomacy.hasTruce($0, fra) && !world.diplomacy.isAtWar($0, fra) && world.countries.overlord[$0.index] == nil }
        XCTAssertGreaterThanOrEqual(candidates.count, 4)
        let coalitionMembers = Array(candidates.prefix(4))

        for member in coalitionMembers {
            world.diplomacy.addAggressiveExpansion(target: fra, observer: member, amount: 55.0)
            world.diplomacy.setOpinion(of: fra, by: member, value: -60)
        }

        DiplomacySystem.updateCoalitions(&world)
        let activeCoalition = world.diplomacy.coalitions[fra]
        XCTAssertNotNil(activeCoalition)
        for member in coalitionMembers {
            XCTAssertTrue(activeCoalition?.contains(member) ?? false)
        }

        let firstMember = coalitionMembers[0]
        let cbs = world.diplomacy.availableCasusBelli(attacker: firstMember, defender: fra, in: world)
        XCTAssertTrue(cbs.contains(where: { $0.type == .coalition }))

        let warRes = world.declareWar(
            attacker: fra,
            defender: firstMember,
            casusBelli: .noCB,
            warGoal: .superiority,
            breakTruce: false,
            date: GameDate(year: 1453, month: 9, day: 1)
        )
        switch warRes {
        case .failure(let err):
            XCTFail("War failed: \(err)")
        case .success(let war):
            for member in coalitionMembers {
                XCTAssertTrue(war.isDefender(member), "Coalition member \(member) should be called in defensively")
            }
        }

        let n = world.countries.count
        for member in coalitionMembers.dropFirst() {
            world.diplomacy.aggressiveExpansion[member.index * n + fra.index] = 10.0
        }
        DiplomacySystem.updateCoalitions(&world)
        XCTAssertNil(world.diplomacy.coalitions[fra], "Coalition must dissolve when fewer than 2 members remain >=30 AE")
    }
}
