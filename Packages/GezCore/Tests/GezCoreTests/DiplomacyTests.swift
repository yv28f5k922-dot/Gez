import XCTest
@testable import GezCore

final class DiplomacyTests: XCTestCase {
    let start = Scenario1453.startDate

    func country(_ w: World, _ tag: String) -> CountryID {
        w.countries.id(forTag: tag)!
    }

    func province(_ w: World, _ name: String) -> ProvinceID {
        w.provinces.id(named: name)!
    }

    func testDiplomacy1453LoadsTreatiesAndWars() {
        let w = Scenario1453.makeWorld()
        let d = w.diplomacy

        XCTAssertEqual(d.countryCount, w.countries.count)
        XCTAssertGreaterThanOrEqual(d.treaties.count, 20)
        XCTAssertEqual(d.wars.count, 2)

        let fra = country(w, "FRA")
        let sco = country(w, "SCO")
        let eng = country(w, "ENG")
        let por = country(w, "POR")
        let tur = country(w, "TUR")
        let hun = country(w, "HUN")
        let pol = country(w, "POL")
        let teu = country(w, "TEU")
        let ven = country(w, "VEN")
        let mlo = country(w, "MLO")

        // Alliances
        XCTAssertTrue(d.areAllies(fra, sco), "France and Scotland should have Auld Alliance")
        XCTAssertTrue(d.areAllies(eng, por), "England and Portugal should have alliance")
        XCTAssertTrue(d.areAllies(fra, country(w, "CAS")), "France and Castile should be allied")

        // Truces
        XCTAssertTrue(d.hasTruce(tur, hun), "Ottomans and Hungary should have Truce of Adrianople")
        XCTAssertTrue(d.hasTruce(pol, teu), "Poland and Teutonic Order should have truce")

        // Guarantees
        XCTAssertTrue(d.hasTreaty(.guarantee, between: tur, and: country(w, "SER")), "Ottomans guarantee Serbia")

        // Active 1453 Wars
        XCTAssertTrue(d.isAtWar(fra, eng), "France and England should be at war in Hundred Years' War")
        XCTAssertTrue(d.isAtWar(ven, mlo), "Venice and Milan should be at war in Lombardy War")

        let hyw = d.activeWar(between: fra, and: eng)!
        XCTAssertEqual(hyw.id, "hundred_years_war")
        XCTAssertEqual(hyw.primaryAttacker, fra)
        XCTAssertEqual(hyw.primaryDefender, eng)
        XCTAssertEqual(hyw.casusBelli, CasusBelli.reconquest)
        let bordeaux = province(w, "Bordeaux")
        XCTAssertEqual(hyw.warGoal, WarGoal.conquerProvince(bordeaux))

        // Opinions & Trust
        XCTAssertEqual(d.opinion(of: eng, by: fra), -100, "Enemies at war should have -100 opinion")
        XCTAssertEqual(d.opinion(of: fra, by: eng), -100)
        XCTAssertEqual(d.trust(of: eng, by: fra), 10, "Enemies at war should have 10 trust")
        XCTAssertGreaterThanOrEqual(d.opinion(of: sco, by: fra), 50, "Allies should have positive opinion")
        XCTAssertGreaterThanOrEqual(d.trust(of: sco, by: fra), 70, "Allies should have high trust")
    }

    func testDiplomaticRelationSlotsAndUpkeep() {
        var w = Scenario1453.makeWorld()
        let fra = country(w, "FRA")
        let slots = w.diplomacy.relationSlots(for: fra, world: w)
        XCTAssertGreaterThanOrEqual(slots, 4, "Base relation slots should be at least 4")

        let used = w.diplomacy.usedRelationSlots(for: fra, world: w)
        XCTAssertGreaterThanOrEqual(used, 2, "France has alliances and vassals using slots")

        // Test upkeep when exceeding available slots
        for i in 10..<20 {
            let cid = CountryID(i)
            if cid != fra {
                w.diplomacy.addTreaty(Treaty(first: fra, second: cid, type: .alliance))
            }
        }
        let excessUsed = w.diplomacy.usedRelationSlots(for: fra, world: w)
        XCTAssertGreaterThan(excessUsed, slots)

        let initialTreasury = w.countries.treasury[fra.index]
        DiplomacySystem.runMonthly(&w, date: GameDate(year: 1453, month: 6, day: 1))
        let afterTreasury = w.countries.treasury[fra.index]
        XCTAssertLessThan(afterTreasury, initialTreasury, "Exceeding relation slots should deduct upkeep")
    }

    func testTruceExpiryDaily() {
        var w = Scenario1453.makeWorld()
        let a = country(w, "HAB")
        let b = country(w, "BOH")

        let expiry = GameDate(year: 1453, month: 6, day: 15)
        w.diplomacy.addTreaty(Treaty(first: a, second: b, type: .truce, expiry: expiry))
        XCTAssertTrue(w.diplomacy.hasTruce(a, b))

        // Before expiry
        DiplomacySystem.runDaily(&w, date: GameDate(year: 1453, month: 6, day: 14))
        XCTAssertTrue(w.diplomacy.hasTruce(a, b))

        // On and after expiry
        DiplomacySystem.runDaily(&w, date: GameDate(year: 1453, month: 6, day: 15))
        XCTAssertFalse(w.diplomacy.hasTruce(a, b), "Truce should expire when end date is reached")
    }

    func testAggressiveExpansionAndDecay() {
        var w = Scenario1453.makeWorld()
        let tur = country(w, "TUR")
        let hab = country(w, "HAB")

        XCTAssertEqual(w.diplomacy.aggressiveExpansion(of: tur, by: hab), 0.0)
        w.diplomacy.addAggressiveExpansion(target: tur, observer: hab, amount: 45.0)
        XCTAssertEqual(w.diplomacy.aggressiveExpansion(of: tur, by: hab), 45.0)

        DiplomacySystem.runMonthly(&w, date: GameDate(year: 1453, month: 6, day: 1))
        let decayed = w.diplomacy.aggressiveExpansion(of: tur, by: hab)
        XCTAssertLessThan(decayed, 45.0, "AE should decay over monthly ticks")
        XCTAssertGreaterThan(decayed, 40.0)
    }

    func testTrustDriftsTowardFifty() {
        var w = Scenario1453.makeWorld()
        let a = country(w, "BUR")
        let b = country(w, "HAB")

        w.diplomacy.setTrust(of: b, by: a, value: 30)
        w.diplomacy.setTrust(of: a, by: b, value: 70)

        // Trust drift occurs on month % 5 == 0
        DiplomacySystem.runMonthly(&w, date: GameDate(year: 1453, month: 5, day: 1))
        XCTAssertEqual(w.diplomacy.trust(of: b, by: a), 31, "Low trust should drift up towards 50")
        XCTAssertEqual(w.diplomacy.trust(of: a, by: b), 69, "High trust should drift down towards 50")
    }
}
