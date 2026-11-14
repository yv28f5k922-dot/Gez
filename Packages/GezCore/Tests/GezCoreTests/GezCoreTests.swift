import XCTest
@testable import GezCore

final class GameDateTests: XCTestCase {
    func testStartDateDescription() {
        XCTAssertEqual(Scenario1453.startDate.description, "30 May 1453")
    }

    func testAdvancesAcrossMonthEnd() {
        var date = GameDate(year: 1453, month: 2, day: 28)
        date.advanceOneDay()
        XCTAssertEqual(date, GameDate(year: 1453, month: 3, day: 1))
        XCTAssertTrue(date.isFirstOfMonth)
    }

    func testAdvancesAcrossYearEnd() {
        var date = GameDate(year: 1453, month: 12, day: 31)
        date.advanceOneDay()
        XCTAssertEqual(date, GameDate(year: 1454, month: 1, day: 1))
        XCTAssertTrue(date.isFirstOfYear)
    }

    func testYearIs365Days() {
        let start = GameDate(year: 1453, month: 5, day: 30)
        XCTAssertEqual(start.adding(days: 365), GameDate(year: 1454, month: 5, day: 30))
        XCTAssertEqual(start.adding(days: 365).ordinal - start.ordinal, 365)
    }

    func testOrdering() {
        XCTAssertLessThan(GameDate(year: 1453, month: 5, day: 30), GameDate(year: 1453, month: 6, day: 1))
        XCTAssertLessThan(GameDate(year: 1453, month: 12, day: 31), GameDate(year: 1454, month: 1, day: 1))
    }
}

final class GameClockTests: XCTestCase {
    func testPausedNeverAdvances() {
        var clock = GameClock(speed: .paused)
        XCTAssertEqual(clock.daysToAdvance(elapsedSeconds: 100), 0)
    }

    func testFractionsCarryOver() {
        var clock = GameClock(speed: .two) // 1 day per second
        XCTAssertEqual(clock.daysToAdvance(elapsedSeconds: 0.5), 0)
        XCTAssertEqual(clock.daysToAdvance(elapsedSeconds: 0.6), 1)
        XCTAssertEqual(clock.daysToAdvance(elapsedSeconds: 0.9), 1)
    }

    func testLongHitchIsCapped() {
        var clock = GameClock(speed: .five)
        XCTAssertEqual(clock.daysToAdvance(elapsedSeconds: 60), clock.maxDaysPerUpdate)
    }
}

final class ScenarioTests: XCTestCase {
    func testEveryCountryHasOwnedCapital() {
        let world = Scenario1453.makeWorld()
        for country in world.countries.ids {
            let tag = world.countries.tag[country.index]
            guard let capital = world.countries.capital[country.index] else {
                XCTFail("\(tag) has no capital")
                continue
            }
            XCTAssertEqual(world.provinces.owner[capital.index], country, "\(tag) does not own its capital")
        }
    }

    func testConstantinopleIsOttoman() {
        let world = Scenario1453.makeWorld()
        let tur = world.countries.id(forTag: "TUR")
        XCTAssertNotNil(tur)
        let index = world.provinces.name.firstIndex(of: "Konstantiniyye")
        XCTAssertNotNil(index)
        if let index {
            XCTAssertEqual(world.provinces.owner[index], tur)
            XCTAssertEqual(world.countries.capital[tur!.index], ProvinceID(index))
        }
    }

    func testCoordinatesAreInsideMap() {
        let world = Scenario1453.makeWorld()
        for i in 0..<world.provinces.count {
            let point = world.provinces.labelPoint[i]
            XCTAssertTrue((0..<world.map.width).contains(point.x), world.provinces.name[i])
            XCTAssertTrue((0..<world.map.height).contains(point.y), world.provinces.name[i])
        }
    }

    func testMapIsLarge() {
        let world = Scenario1453.makeWorld()
        XCTAssertGreaterThan(world.provinces.count, 1000)
        XCTAssertGreaterThan(world.states.count, 200)
        XCTAssertGreaterThan(world.countries.count, 150)
        XCTAssertGreaterThan(world.regions.count, 20)
    }

    func testEveryStateHasProvincesAndValidRegion() {
        let world = Scenario1453.makeWorld()
        for s in 0..<world.states.count {
            XCTAssertFalse(world.states.provinces[s].isEmpty, world.states.name[s])
            XCTAssertTrue(world.regions.indices.contains(world.states.region[s].index), world.states.name[s])
        }
    }

    func testStateAndRegionLookups() {
        let world = Scenario1453.makeWorld()
        let paris = world.provinces.id(named: "Paris")!
        XCTAssertEqual(world.stateName(of: paris), "Ile-de-France")
        XCTAssertEqual(world.regionName(of: paris), "France")
        let konya = world.provinces.id(named: "Konya")!
        XCTAssertEqual(world.stateName(of: konya), "Karaman")
        XCTAssertEqual(world.regionName(of: konya), "Anatolia")
    }

    func testNeighborsAreTwoWay() {
        let world = Scenario1453.makeWorld()
        for i in 0..<world.provinces.count {
            for n in world.provinces.neighbors[i] {
                XCTAssertTrue(world.provinces.neighbors[n.index].contains(ProvinceID(i)),
                              "\(world.provinces.name[i]) -> \(world.provinces.name[n.index])")
            }
        }
    }

    func testRiversAndRiverBorders() {
        let world = Scenario1453.makeWorld()
        XCTAssertGreaterThan(world.rivers.count, 50)
        XCTAssertTrue(world.rivers.contains { $0.name == "Danube" })
        XCTAssertGreaterThan(world.riverBorders.count, 150)
        for pair in world.riverBorders {
            XCTAssertTrue(world.provinces.neighbors[pair.low].contains(ProvinceID(pair.high)),
                          "\(world.provinces.name[pair.low]) / \(world.provinces.name[pair.high]) are not neighbours")
        }
    }

    func testDanubeSeparatesWallachiaFromBulgaria() {
        let world = Scenario1453.makeWorld()
        let wal = world.countries.id(forTag: "WAL")!
        let tur = world.countries.id(forTag: "TUR")!
        var crossings = 0
        var riverCrossings = 0
        for a in world.provinces(ownedBy: wal) {
            for b in world.provinces.neighbors[a.index] where world.provinces.owner[b.index] == tur {
                crossings += 1
                if world.isRiverBorder(a, b) { riverCrossings += 1 }
            }
        }
        XCTAssertGreaterThan(crossings, 0)
        XCTAssertGreaterThanOrEqual(Double(riverCrossings) / Double(crossings), 0.5)
    }

    func testBosporusCrossing() {
        let world = Scenario1453.makeWorld()
        let constantinople = world.provinces.id(named: "Konstantiniyye")!
        let izmit = world.provinces.id(named: "Izmit")!
        XCTAssertTrue(world.provinces.neighbors[constantinople.index].contains(izmit))
    }

    func testMostProvincesHaveNeighbors() {
        let world = Scenario1453.makeWorld()
        let isolated = world.provinces.ids.filter { world.provinces.neighbors[$0.index].isEmpty }
        XCTAssertLessThan(isolated.count, 15)
    }

    func testPeopleCanFollowADifferentReligionThanTheirRuler() {
        let world = Scenario1453.makeWorld()
        let sofia = world.provinces.id(named: "Sofia")!.index
        XCTAssertEqual(world.countries.tag[world.provinces.owner[sofia]!.index], "TUR")
        XCTAssertEqual(world.provinces.religion[sofia], .orthodox)
        let delhi = world.provinces.id(named: "Delhi")!.index
        XCTAssertEqual(world.provinces.religion[delhi], .hindu)
        let lapland = world.provinces.id(named: "Lapland")!.index
        XCTAssertEqual(world.provinces.religion[lapland], .folk)
        XCTAssertEqual(world.cultures.key[world.provinces.majorityCulture[lapland].index], "sami")
        let paris = world.provinces.id(named: "Paris")!.index
        XCTAssertEqual(world.provinces.religion[paris], .catholic)
    }

    func testStartingValuesScaleWithDevelopment() {
        let world = Scenario1453.makeWorld()
        let paris = world.provinces.id(named: "Paris")!.index
        let lapland = world.provinces.id(named: "Lapland")!.index
        XCTAssertGreaterThan(world.provinces.population[paris], world.provinces.population[lapland] * 10)
        XCTAssertEqual(world.provinces.owner[lapland], world.countries.id(forTag: "SMI"))
        XCTAssertGreaterThanOrEqual(world.provinces.fortLevel[world.provinces.id(named: "Konstantiniyye")!.index], 4)
    }
}

final class PopTests: XCTestCase {
    private func share<K: Hashable>(_ pairs: [(K, Double)], _ key: K) -> Double {
        pairs.first { $0.0 == key }?.1 ?? 0
    }

    func testEveryProvinceHasPopsMatchingItsPopulation() {
        let world = Scenario1453.makeWorld()
        for p in world.provinces.ids {
            let range = world.pops.range(for: p)
            XCTAssertFalse(range.isEmpty, world.provinces.name[p.index])
            let sum = range.reduce(0.0) { $0 + world.pops.size[$1] }
            XCTAssertEqual(sum, world.provinces.population[p.index], accuracy: 1, world.provinces.name[p.index])
        }
    }

    func testConstantinopleMix() {
        let world = Scenario1453.makeWorld()
        let b = world.breakdown(of: world.provinces.id(named: "Konstantiniyye")!)
        let greek = world.cultures.id(forKey: "greek")!
        let turkish = world.cultures.id(forKey: "turkish")!
        XCTAssertGreaterThan(share(b.cultureShares(), greek), share(b.cultureShares(), turkish))
        XCTAssertGreaterThan(share(b.religionShares(), .jewish), 0.01)
        XCTAssertGreaterThan(share(b.religionShares(), .sunni), 0.2)
    }

    func testSocialClassesAddUp() {
        let world = Scenario1453.makeWorld()
        let b = world.breakdown(of: world.provinces.id(named: "Paris")!)
        let classes = b.classShares()
        XCTAssertEqual(classes.reduce(0) { $0 + $1.1 }, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(share(classes, .peasants), 0.6)
        XCTAssertGreaterThan(share(classes, .burghers), 0.1)
        XCTAssertGreaterThan(share(classes, .nobles), 0)
        XCTAssertEqual(share(classes, .slaves), 0)
        // Crimea keeps slaves.
        let crimea = world.breakdown(ofCountry: world.countries.id(forTag: "CRI")!)
        XCTAssertGreaterThan(share(crimea.classShares(), .slaves), 0.03)
    }

    func testOttomanEmpireIsMixed() {
        let world = Scenario1453.makeWorld()
        let b = world.breakdown(ofCountry: world.countries.id(forTag: "TUR")!)
        XCTAssertGreaterThan(share(b.religionShares(), .orthodox), 0.3)
        XCTAssertGreaterThan(share(b.religionShares(), .sunni), 0.3)
    }

    func testReligionsFromTheNewList() {
        let world = Scenario1453.makeWorld()
        func majority(_ name: String) -> Religion { world.provinces.religion[world.provinces.id(named: name)!.index] }
        XCTAssertEqual(majority("Prague"), .hussite)
        XCTAssertEqual(majority("Nizwa"), .ibadi)
        XCTAssertEqual(majority("Sanaa"), .zaydi)
        XCTAssertEqual(majority("Sinjar"), .yazidi)
        XCTAssertEqual(majority("Semien"), .jewish)
        XCTAssertEqual(majority("Kotte"), .theravada)
        XCTAssertEqual(majority("Ladakh"), .tibetan)
        XCTAssertEqual(majority("Aksum"), .ethiopian)
        XCTAssertEqual(world.countries.religion[world.countries.id(forTag: "OMN")!.index], .ibadi)
    }

    func testStateBreakdownAndSects() {
        let world = Scenario1453.makeWorld()
        let state = world.provinces.state[world.provinces.id(named: "Sofia")!.index]
        let b = world.breakdown(ofState: state)
        let bulgarian = world.cultures.id(forKey: "bulgarian")!
        XCTAssertGreaterThan(share(b.cultureShares(), bulgarian), 0.6)
        XCTAssertGreaterThan(b.bySect[.hanafi] ?? 0, 0)
    }

    func testSafaviyyaInArdabil() {
        let world = Scenario1453.makeWorld()
        let orders = world.provinces.sufiOrders[world.provinces.id(named: "Ardabil")!.index]
        XCTAssertTrue(orders.contains { $0.order == .safaviyya && $0.strength > 0.5 })
    }

    func testPopsGrowWithTime() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate)
        let before = sim.world.pops.size.reduce(0, +)
        sim.advance(days: 365)
        XCTAssertGreaterThan(sim.world.pops.size.reduce(0, +), before)
    }
}

final class OwnerDecisionTests: XCTestCase {
    private func owner(_ world: World, _ province: String) -> String? {
        world.provinces.owner[world.provinces.id(named: province)!.index].map { world.countries.tag[$0.index] }
    }

    func testOwnerChoicesFor1453() {
        let world = Scenario1453.makeWorld()
        XCTAssertEqual(owner(world, "Bordeaux"), "ENG")
        XCTAssertEqual(owner(world, "Balkh"), "TIM")
        XCTAssertEqual(owner(world, "Kayseri"), "DUL")
        XCTAssertEqual(owner(world, "Kirsehir"), "KAR")
        XCTAssertEqual(owner(world, "Nis"), "SER")
        XCTAssertEqual(owner(world, "Kassa"), "JIS")
        XCTAssertEqual(owner(world, "Kilia"), "HUN")
        XCTAssertEqual(owner(world, "Ochakiv"), "CRI")
        XCTAssertEqual(owner(world, "Marrakesh"), "HIN")
        XCTAssertEqual(owner(world, "Aden"), "TAH")
        XCTAssertEqual(owner(world, "Sanaa"), "ZAY")
        XCTAssertEqual(owner(world, "Bahrain"), "JAB")
        XCTAssertEqual(owner(world, "Dongola"), "DOT")
        XCTAssertEqual(owner(world, "Kalat"), "BLC")
    }

    func testTribalLandFillsTheBlanks() {
        let world = Scenario1453.makeWorld()
        let unowned = world.provinces.ids.filter { world.provinces.owner[$0.index] == nil }
        XCTAssertTrue(unowned.isEmpty, unowned.map { world.provinces.name[$0.index] }.joined(separator: ", "))
        let baloch = world.countries.id(forTag: "BLC")!
        XCTAssertEqual(world.countries.government[baloch.index], .tribal)
    }

    func testSubjects() {
        let world = Scenario1453.makeWorld()
        let c = world.countries
        let hun = c.id(forTag: "HUN")!
        XCTAssertEqual(c.overlord[c.id(forTag: "AUS")!.index], hun)
        XCTAssertEqual(c.subjectType[c.id(forTag: "BOH")!.index], .personalUnion)
        XCTAssertEqual(c.subjectType[c.id(forTag: "HIN")!.index], .vassal)
        XCTAssertEqual(c.overlord[c.id(forTag: "HIN")!.index], c.id(forTag: "MOR"))
        XCTAssertEqual(c.subjects(of: c.id(forTag: "ETH")!).count, 6)
        XCTAssertNil(c.overlord[c.id(forTag: "FRA")!.index])
    }

    func testArmenianMajority() {
        let world = Scenario1453.makeWorld()
        XCTAssertEqual(world.provinces.religion[world.provinces.id(named: "Yerevan")!.index], .armenian)
    }
}

final class SeaZoneTests: XCTestCase {
    func testSeaZonesLoad() {
        let world = Scenario1453.makeWorld()
        XCTAssertGreaterThan(world.seaZones.count, 70)
        let marmara = world.seaZones.id(named: "Sea of Marmara")!
        let aegean = world.seaZones.id(named: "Northern Aegean")!
        let blackSea = world.seaZones.id(named: "Western Black Sea")!
        XCTAssertTrue(world.seaZones.neighbors[marmara.index].contains(aegean))
        XCTAssertTrue(world.seaZones.neighbors[marmara.index].contains(blackSea))
        let constantinople = world.provinces.id(named: "Konstantiniyye")!
        XCTAssertTrue(world.provinceSeas[constantinople.index].contains(marmara))
    }

    func testCoastAgreesWithCoastalFlag() {
        let world = Scenario1453.makeWorld()
        let inland = world.provinces.id(named: "Vienna")!
        XCTAssertTrue(world.provinceSeas[inland.index].isEmpty)
        let calicut = world.provinces.id(named: "Calicut")!
        XCTAssertTrue(world.provinceSeas[calicut.index].contains(world.seaZones.id(named: "Malabar Coast")!))
    }

    func testSeaNeighboursAreTwoWay() {
        let world = Scenario1453.makeWorld()
        for z in 0..<world.seaZones.count {
            for n in world.seaZones.neighbors[z] {
                XCTAssertTrue(world.seaZones.neighbors[n.index].contains(SeaZoneID(z)), world.seaZones.name[z])
            }
        }
    }

    func testSeaMapMatches() throws {
        let world = Scenario1453.makeWorld()
        let seas = try ProvinceIDMap.loadBundledSeas()
        XCTAssertEqual(seas.width, world.map.width)
        let p = world.map.point(for: GeoPoint(latitude: 40.7, longitude: 28.2))
        XCTAssertEqual(seas.seaZone(x: p.x, y: p.y), world.seaZones.id(named: "Sea of Marmara"))
    }
}

final class HeraldryTests: XCTestCase {
    /// data/heraldry/choices.txt lists the real arms/banner for each country.
    /// Every tag must be a real country, listed once.
    func testChoicesMatchCountries() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: repo.appendingPathComponent("data/heraldry/choices.txt"), encoding: .utf8)
        let world = Scenario1453.makeWorld()
        var seen = Set<String>()
        for line in text.split(separator: "\n") where !line.hasPrefix("#") && !line.isEmpty {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertGreaterThanOrEqual(parts.count, 2, String(line))
            let tag = parts[0]
            XCTAssertNotNil(world.countries.id(forTag: tag), "unknown tag \(tag)")
            XCTAssertTrue(seen.insert(tag).inserted, "duplicate tag \(tag)")
            XCTAssertTrue(parts[1].hasPrefix("File:"), "\(tag) needs a Commons File: title")
        }
        XCTAssertGreaterThan(seen.count, 150)
    }
}

final class ProvinceIDMapTests: XCTestCase {
    func testMapMatchesScenario() throws {
        let world = Scenario1453.makeWorld()
        let map = try ProvinceIDMap.loadBundled()
        XCTAssertEqual(map.width, world.map.width)
        XCTAssertEqual(map.height, world.map.height)
    }

    func testEveryLabelPointIsInsideItsProvince() throws {
        let world = Scenario1453.makeWorld()
        let map = try ProvinceIDMap.loadBundled()
        for i in 0..<world.provinces.count {
            let p = world.provinces.labelPoint[i]
            XCTAssertEqual(map.province(x: p.x, y: p.y), ProvinceID(i), world.provinces.name[i])
        }
    }

    func testOpenSeaIsWater() throws {
        let world = Scenario1453.makeWorld()
        let map = try ProvinceIDMap.loadBundled()
        // Middle of the Black Sea and the Arabian Sea.
        for geo in [GeoPoint(latitude: 43.5, longitude: 34.0), GeoPoint(latitude: 15.0, longitude: 63.0)] {
            let p = world.map.point(for: geo)
            XCTAssertEqual(map.value(x: p.x, y: p.y), ProvinceIDMap.water)
        }
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try ProvinceIDMap(data: Data([1, 2, 3])))
    }
}

final class SimulationTests: XCTestCase {
    func testMonthlyIncomeArrivesOnFirstOfMonth() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate)
        let tur = sim.world.countries.id(forTag: "TUR")!.index
        sim.world.humanCountries = [CountryID(tur)]
        let before = sim.world.countries.treasury[tur]

        sim.advance(days: 1) // 31 May: no income yet
        XCTAssertEqual(sim.world.countries.treasury[tur], before)

        sim.advance(days: 1) // 1 June: monthly tick
        XCTAssertEqual(sim.date, GameDate(year: 1453, month: 6, day: 1))
        XCTAssertGreaterThan(sim.world.countries.treasury[tur], before)
        XCTAssertGreaterThan(sim.world.countries.lastMonthlyIncome[tur], 0)
    }

    func testPopulationGrowsOverAYear() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate)
        let before = sim.world.provinces.population.reduce(0, +)
        sim.advance(days: 365)
        XCTAssertGreaterThan(sim.world.provinces.population.reduce(0, +), before)
    }

    func testDeterministicForSameSeed() {
        let a = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate, seed: 7)
        let b = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate, seed: 7)
        a.advance(days: 400)
        b.advance(days: 400)
        XCTAssertEqual(a.date, b.date)
        XCTAssertEqual(a.world.countries.treasury, b.world.countries.treasury)
        XCTAssertEqual(a.world.provinces.population, b.world.provinces.population)
    }

    func testTenYearsStaysBounded() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate)
        let routes = sim.world.economy.routes.count
        sim.advance(days: 3650)
        let w = sim.world
        XCTAssertLessThanOrEqual(w.economy.routes.count, routes + w.countries.count * TradeModel.maxAIRoutes)
        XCTAssertLessThan(w.economy.buildings.constructions.count, w.countries.count * 2)
        for c in w.countries.ids { XCTAssertTrue(w.countries.treasury[c.index].isFinite) }
        for p in w.economy.markets.price { XCTAssertTrue(p.isFinite && p > 0) }
        let peasants = w.satisfaction(of: .peasants, in: w.provinces.ids)!
        XCTAssertGreaterThan(peasants, 0.4)
    }
}

final class RandomTests: XCTestCase {
    func testSameSeedSameSequence() {
        var a = GameRandom(seed: 1453)
        var b = GameRandom(seed: 1453)
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next())
        }
    }
}

final class EconomyTests: XCTestCase {
    func testEconomyLoads() {
        let world = Scenario1453.makeWorld()
        let eco = world.economy
        XCTAssertEqual(eco.goods.count, 62)
        XCTAssertEqual(eco.markets.count, 42)
        XCTAssertEqual(eco.provinceMarket.count, world.provinces.count)
        XCTAssertFalse(eco.marketLinks.isEmpty)
        for p in world.provinces.ids {
            let r = eco.producers.range(for: p)
            XCTAssertFalse(r.isEmpty, world.provinces.name[p.index])
            XCTAssertTrue(eco.producers.isStaple[r.lowerBound])
            XCTAssertEqual(eco.producers.kind[r.lowerBound], .raw)
        }
        XCTAssertTrue((0..<eco.producers.count).allSatisfy { eco.producers.kind[$0] == .raw })
    }

    func testMarketCentresBelongToTheirOwnMarket() {
        let world = Scenario1453.makeWorld()
        let eco = world.economy
        for m in eco.markets.ids {
            XCTAssertEqual(eco.provinceMarket[eco.markets.centre[m.index].index], m, eco.markets.name[m.index])
        }
        func market(of province: String) -> String {
            eco.markets.name[eco.provinceMarket[world.provinces.id(named: province)!.index].index]
        }
        XCTAssertEqual(market(of: "Konstantiniyye"), "Constantinople")
        XCTAssertEqual(market(of: "Calicut"), "Calicut")
        XCTAssertEqual(market(of: "Padua"), "Venice")
    }

    func testScarceGoodsGetDearer() {
        var world = Scenario1453.makeWorld()
        let eco = world.economy
        let london = eco.markets.id(named: "London")!
        let spices = eco.goods.id(forKey: "fine_spices")!
        let base = eco.goods.basePrice[spices.index]
        for _ in 0..<6 { MarketSystem.runMonthly(&world) }
        let i = world.economy.markets.slot(london, spices)
        XCTAssertGreaterThan(world.economy.markets.demand[i], 0)
        XCTAssertGreaterThan(world.economy.markets.price[i], base)
    }

    func testSatisfactionStaysInRangeAndPeasantsAreMostlyFed() {
        var world = Scenario1453.makeWorld()
        for _ in 0..<12 { MarketSystem.runMonthly(&world) }
        var sum = 0.0, weight = 0.0
        for i in 0..<world.pops.count {
            let s = world.pops.satisfaction[i]
            XCTAssertTrue((0...1).contains(s))
            if world.pops.socialClass[i] == .peasants {
                sum += s * world.pops.size[i]
                weight += world.pops.size[i]
            }
        }
        XCTAssertGreaterThan(sum / weight, 0.6)
        for p in world.economy.markets.price { XCTAssertTrue(p.isFinite && p > 0) }
    }

    func testOttomanIncomeIsSensible() {
        var world = Scenario1453.makeWorld()
        for _ in 0..<3 { MarketSystem.runMonthly(&world) }
        let tur = world.countries.id(forTag: "TUR")!.index
        XCTAssertGreaterThan(world.countries.lastMonthlyIncome[tur], 5)
        XCTAssertLessThan(world.countries.lastMonthlyIncome[tur], 80)
    }
}

final class BuildingTests: XCTestCase {
    func type(_ world: World, _ key: String) -> BuildingTypeID { world.economy.buildingType(key: key)! }
    func province(_ world: World, _ name: String) -> ProvinceID { world.provinces.id(named: name)! }

    func testStartingBuildings() {
        let world = Scenario1453.makeWorld()
        let b = world.economy.buildings
        XCTAssertEqual(b.level(province(world, "Paris"), type(world, "college")), 3)
        XCTAssertEqual(b.level(province(world, "Venice"), type(world, "shipyard")), 4)
        XCTAssertEqual(b.level(province(world, "Konstantiniyye"), type(world, "market_hall")), 2)
        let fort = type(world, "fort")
        for p in world.provinces.ids {
            XCTAssertEqual(b.level(p, fort), world.provinces.fortLevel[p.index])
        }
        // Every province with burghers has at least one workshop.
        var withWorkshops = 0
        for p in world.provinces.ids {
            let has = world.economy.buildingTypes.indices.contains { t in
                if case .workshop = world.economy.buildingTypes[t].effect { return b.level(p, BuildingTypeID(t)) > 0 }
                return false
            }
            if has { withWorkshops += 1 }
        }
        XCTAssertEqual(withWorkshops, world.provinces.count)
    }

    func testBuildingTakesMoneyAndTime() {
        var world = Scenario1453.makeWorld()
        let tur = world.countries.id(forTag: "TUR")!
        let edirne = province(world, "Edirne")
        let hall = type(world, "market_hall")
        world.countries.treasury[tur.index] = 1000
        let before = world.economy.buildings.level(edirne, hall)
        let cost = BuildingSystem.cost(world, edirne, hall)
        XCTAssertNil(BuildingSystem.start(&world, tur, edirne, hall))
        XCTAssertEqual(world.countries.treasury[tur.index], 1000 - cost, accuracy: 0.001)
        XCTAssertEqual(BuildingSystem.refusal(world, tur, edirne, hall), .alreadyBuilding)
        let months = world.economy.buildingTypes[hall.index].months(forLevel: before + 1)
        for _ in 0..<(months - 1) { BuildingSystem.runMonthly(&world) }
        XCTAssertEqual(world.economy.buildings.level(edirne, hall), before)
        BuildingSystem.runMonthly(&world)
        XCTAssertEqual(world.economy.buildings.level(edirne, hall), before + 1)
    }

    func testRefusals() {
        var world = Scenario1453.makeWorld()
        let tur = world.countries.id(forTag: "TUR")!
        XCTAssertEqual(BuildingSystem.refusal(world, tur, province(world, "Paris"), type(world, "temple")), .notOwner)
        let ankara = world.provinces.ids.first { world.provinces.owner[$0.index] == tur && !world.provinces.isCoastal[$0.index] }!
        XCTAssertEqual(BuildingSystem.refusal(world, tur, ankara, type(world, "port"), checkMoney: false), .needsCoast)
        world.countries.treasury[tur.index] = 0
        let edirne = province(world, "Edirne")
        XCTAssertEqual(BuildingSystem.refusal(world, tur, edirne, type(world, "temple")), .cannotAfford)
    }

    func testFortBuildingRaisesFortLevel() {
        var world = Scenario1453.makeWorld()
        let tur = world.countries.id(forTag: "TUR")!
        let edirne = province(world, "Edirne")
        let fort = type(world, "fort")
        world.countries.treasury[tur.index] = 10_000
        let before = world.provinces.fortLevel[edirne.index]
        guard before < BuildingType.maxLevel else { return }
        XCTAssertNil(BuildingSystem.start(&world, tur, edirne, fort))
        for _ in 0..<60 { BuildingSystem.runMonthly(&world) }
        XCTAssertEqual(world.provinces.fortLevel[edirne.index], before + 1)
    }

    func testMoreWorkshopLevelsMakeMoreGoods() {
        var world = Scenario1453.makeWorld()
        let p = province(world, "Florence")
        let brewery = type(world, "brewery")
        XCTAssertEqual(world.economy.buildings.level(p, brewery), 0)
        MarketSystem.runMonthly(&world)
        let slot = p.index * world.economy.buildings.typeCount + brewery.index
        XCTAssertEqual(world.economy.workshopOutput[slot], 0)
        world.economy.buildings.setLevel(p, brewery, 1)
        MarketSystem.runMonthly(&world)
        XCTAssertGreaterThan(world.economy.workshopOutput[slot], 0)
    }

    func testComputerCountriesBuild() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate)
        sim.world.humanCountries = [sim.world.countries.id(forTag: "TUR")!]
        let levels = sim.world.economy.buildings.level.reduce(0, +)
        sim.advance(days: 730)
        XCTAssertGreaterThan(sim.world.economy.buildings.level.reduce(0, +), levels)
        let tur = sim.world.countries.id(forTag: "TUR")!
        XCTAssertFalse(sim.world.economy.buildings.constructions.contains { sim.world.provinces.owner[$0.province.index] == tur })
    }
}

final class FinanceTests: XCTestCase {
    func country(_ world: World, _ tag: String) -> CountryID { world.countries.id(forTag: tag)! }
    func bank(_ world: World, _ name: String) -> BankID {
        BankID(world.finance.banks.name.firstIndex(of: name)!)
    }

    func testBanksLoad() {
        let world = Scenario1453.makeWorld()
        XCTAssertEqual(world.finance.banks.count, 15)
        XCTAssertTrue(world.finance.loans.isEmpty)
    }

    func testHigherTaxMoreMoneyLessHappy() {
        var world = Scenario1453.makeWorld()
        let tur = country(world, "TUR")
        MarketSystem.runMonthly(&world)
        let normal = world.countries.lastMonthlyIncome[tur.index]
        let mood = world.satisfaction(of: .peasants, in: world.provinces(ownedBy: tur))!
        world.countries.taxLevel[tur.index][TaxClass.peasants.rawValue] = 2
        for _ in 0..<6 { MarketSystem.runMonthly(&world) }
        XCTAssertGreaterThan(world.countries.lastMonthlyIncome[tur.index], normal * 1.2)
        XCTAssertLessThan(world.satisfaction(of: .peasants, in: world.provinces(ownedBy: tur))!, mood - 0.05)
    }

    func testBorrowPayInterestRepay() {
        var world = Scenario1453.makeWorld()
        let tur = country(world, "TUR")
        let galata = bank(world, "Galata Merchants")
        let capital = world.finance.banks.capital[galata.index]
        let treasury = world.countries.treasury[tur.index]
        XCTAssertNotNil(world.loanRate(galata, for: tur))
        XCTAssertTrue(FinanceSystem.borrow(&world, tur, from: galata, amount: 100))
        XCTAssertEqual(world.countries.treasury[tur.index], treasury + 100, accuracy: 0.001)
        XCTAssertEqual(world.finance.banks.capital[galata.index], capital - 100, accuracy: 0.001)
        FinanceSystem.runMonthly(&world)
        XCTAssertGreaterThan(world.countries.lastInterest[tur.index], 0)
        XCTAssertTrue(FinanceSystem.repay(&world, loan: 0))
        XCTAssertGreaterThan(world.finance.banks.capital[galata.index], capital)
        XCTAssertTrue(world.finance.loans.isEmpty)
    }

    func testBanksStopLendingToTheOverIndebted() {
        var world = Scenario1453.makeWorld()
        let fra = country(world, "FRA")
        let medici = bank(world, "Medici Bank")
        world.countries.lastMonthlyIncome[fra.index] = 1
        world.finance.loans.append(Loan(country: fra, bank: medici, principal: 100, rate: 0.1, monthsLeft: 10))
        XCTAssertNil(world.loanRate(medici, for: fra))
        world.finance.loans.removeAll()
        XCTAssertLessThanOrEqual(world.loanRate(medici, for: fra)!, Finance.maxRate)
    }

    func testFarAwayBankWontLend() {
        let world = Scenario1453.makeWorld()
        XCTAssertNil(world.loanRate(bank(world, "Chetti Merchants"), for: country(world, "FRA")))
    }

    func testMoreDebtCostsMore() {
        var world = Scenario1453.makeWorld()
        MarketSystem.runMonthly(&world)
        let fra = country(world, "FRA")
        let medici = bank(world, "Medici Bank")
        let first = world.loanRate(medici, for: fra)!
        FinanceSystem.borrow(&world, fra, from: medici, amount: 500)
        XCTAssertGreaterThan(world.loanRate(medici, for: fra)!, first)
    }

    func testBankruptcyWhenNobodyLends() {
        var world = Scenario1453.makeWorld()
        let fra = country(world, "FRA")
        FinanceSystem.borrow(&world, fra, from: bank(world, "Medici Bank"), amount: 100)
        for b in world.finance.banks.ids { world.finance.banks.capital[b.index] = 0 }
        world.countries.treasury[fra.index] = -5000
        FinanceSystem.runMonthly(&world)
        XCTAssertEqual(world.countries.treasury[fra.index], 0)
        XCTAssertEqual(world.countries.bankruptMonthsLeft[fra.index], Finance.bankruptcyMonths)
        XCTAssertFalse(world.finance.loans.contains { $0.country == fra })
        XCTAssertNil(world.loanRate(bank(world, "Medici Bank"), for: fra))
    }

    func testDebasementRaisesInflationAndCosts() {
        var world = Scenario1453.makeWorld()
        let tur = country(world, "TUR")
        let edirne = world.provinces.id(named: "Edirne")!
        let hall = world.economy.buildingType(key: "market_hall")!
        let cost = BuildingSystem.cost(world, edirne, hall)
        let treasury = world.countries.treasury[tur.index]
        let gain = FinanceSystem.debaseOnce(&world, tur)
        XCTAssertEqual(world.countries.treasury[tur.index], treasury + gain, accuracy: 0.001)
        XCTAssertEqual(world.countries.inflation[tur.index], Finance.debaseOnceInflation, accuracy: 1e-9)
        XCTAssertGreaterThan(BuildingSystem.cost(world, edirne, hall), cost)
        FinanceSystem.runMonthly(&world)
        XCTAssertLessThan(world.countries.inflation[tur.index], Finance.debaseOnceInflation)
    }
}

final class TradeTests: XCTestCase {
    func market(_ w: World, _ n: String) -> MarketID { w.economy.markets.id(named: n)! }
    func country(_ w: World, _ t: String) -> CountryID { w.countries.id(forTag: t)! }

    func testStartingRoutesHavePaths() {
        let world = Scenario1453.makeWorld()
        XCTAssertGreaterThan(world.economy.routes.count, 40)
        let withPath = world.economy.routes.filter { $0.path.count >= 2 }.count
        XCTAssertEqual(withPath, world.economy.routes.count)
        XCTAssertFalse(world.economy.marketLinkIsSea.allSatisfy { !$0 })
    }

    func testSpicesReachVenice() {
        let world = Scenario1453.makeWorld()
        let pepper = world.economy.goods.id(forKey: "pepper")!
        let i = world.economy.markets.slot(market(world, "Venice"), pepper)
        XCTAssertGreaterThan(world.economy.markets.supply[i], 0)
        let venetian = world.economy.routes.filter { $0.owner == self.country(world, "VEN") }
        XCTAssertTrue(venetian.contains { $0.moved > 0 })
    }

    func testEmbargoBlocksRoute() {
        var world = Scenario1453.makeWorld()
        let mam = country(world, "MAM"), ven = country(world, "VEN")
        XCTAssertNotNil(world.tradePath(for: ven, from: market(world, "Cairo"), to: market(world, "Venice")))
        world.countries.embargoes[mam.index].insert(ven)
        XCTAssertNil(world.tradePath(for: ven, from: market(world, "Cairo"), to: market(world, "Venice")))
        TradeSystem.refreshPaths(&world)
        XCTAssertTrue(world.economy.routes.filter { $0.owner == ven && $0.from == self.market(world, "Cairo") }
            .allSatisfy { $0.path.isEmpty })
    }

    func testClosedMarketBlocksForeignersOnly() {
        var world = Scenario1453.makeWorld()
        let mam = country(world, "MAM")
        world.countries.tollPolicy[mam.index] = .closed
        XCTAssertFalse(world.canTrade(country(world, "VEN"), in: market(world, "Cairo")))
        XCTAssertTrue(world.canTrade(mam, in: market(world, "Cairo")))
    }

    func testCapacityLimitsNewRoutes() {
        var world = Scenario1453.makeWorld()
        let tur = country(world, "TUR")
        let gold = world.economy.goods.id(forKey: "gold")!
        let r = TradeSystem.create(&world, owner: tur, good: gold, from: market(world, "Fez"),
                                   to: market(world, "Constantinople"), volume: 10_000)
        XCTAssertEqual(r, .noCapacity)
        XCTAssertGreaterThan(world.tradeCapacity(tur), TradeModel.baseCapacity)
    }

    func testRoutesEarnAndTollsPay() {
        var world = Scenario1453.makeWorld()
        for _ in 0..<3 { MarketSystem.runMonthly(&world) }
        let total = world.countries.lastTrade.reduce(0, +)
        XCTAssertNotEqual(total, 0)
        XCTAssertGreaterThan(world.countries.lastTolls.reduce(0, +), 0)
    }

    func testComputerCountriesOpenRoutes() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate)
        let start = sim.world.economy.routes.count
        sim.advance(days: 400)
        let started = sim.world.economy.routes.count - start
        // Routes are opened and dropped; at least some new ones appear.
        XCTAssertNotEqual(started, 0)
    }
}

final class CharacterTests: XCTestCase {
    let start = Scenario1453.startDate
    func person(_ w: World, _ key: String) -> CharacterID { w.people.characters.id(forKey: key)! }
    func country(_ w: World, _ t: String) -> CountryID { w.countries.id(forTag: t)! }

    func testRealPeopleOf1453() {
        let w = Scenario1453.makeWorld()
        let ch = w.people.characters
        let mehmed = person(w, "mehmed2")
        XCTAssertEqual(w.countries.ruler[country(w, "TUR").index], mehmed)
        XCTAssertEqual(ch.age(mehmed, on: start), 21)
        XCTAssertEqual(w.countries.heir[country(w, "TUR").index], person(w, "bayezid2"))
        let ladislaus = person(w, "ladislaus5")
        for t in ["HUN", "AUS", "BOH"] { XCTAssertEqual(w.countries.ruler[country(w, t).index], ladislaus) }
        XCTAssertGreaterThan(ch.ids.filter { !ch.invented[$0.index] }.count, 300)
        for c in w.countries.ids {
            let r = w.countries.ruler[c.index]
            XCTAssertNotNil(r, w.countries.tag[c.index])
            XCTAssertTrue(ch.isAlive(r!))
            XCTAssertEqual(w.countries.council[c.index].compactMap { $0 }.count, CouncilSeat.allCases.count, w.countries.tag[c.index])
        }
    }

    func testInventedRulerHasInventedSiblingHeir() {
        let w = Scenario1453.makeWorld()
        let ch = w.people.characters
        let gil = country(w, "GIL")
        let r = w.countries.ruler[gil.index]!, h = w.countries.heir[gil.index]!
        XCTAssertTrue(ch.invented[r.index])
        XCTAssertTrue(ch.invented[h.index])
        XCTAssertEqual(ch.dynasty[r.index], ch.dynasty[h.index])
    }

    func testOttomanSuccession() {
        var w = Scenario1453.makeWorld()
        var rng = GameRandom(seed: 1)
        CharacterSystem.kill(&w, person(w, "mehmed2"), date: start, random: &rng)
        XCTAssertEqual(w.countries.ruler[country(w, "TUR").index], person(w, "bayezid2"))
    }

    func testFranceIsSalic() {
        var w = Scenario1453.makeWorld()
        var rng = GameRandom(seed: 1)
        for k in ["louis11", "charles_b"] {
            CharacterSystem.kill(&w, person(w, k), date: start, random: &rng)
        }
        let heir = w.countries.heir[country(w, "FRA").index]
        if let h = heir { XCTAssertFalse(w.people.characters.female[h.index]) }
    }

    func testElectiveHungaryPicksAnAdultMan() {
        var w = Scenario1453.makeWorld()
        var rng = GameRandom(seed: 1)
        CharacterSystem.kill(&w, person(w, "ladislaus5"), date: start, random: &rng)
        let hun = country(w, "HUN")
        let king = w.countries.ruler[hun.index]!
        XCTAssertNotEqual(king, person(w, "ladislaus5"))
        XCTAssertFalse(w.people.characters.female[king.index])
        XCTAssertGreaterThanOrEqual(w.people.characters.age(king, on: start), 16)
    }

    func testMarriageRules() {
        let w = Scenario1453.makeWorld()
        XCTAssertEqual(CharacterSystem.marriageRefusal(w, person(w, "bayezid2"), person(w, "zoe_p"), date: start), .tooYoung)
        XCTAssertEqual(CharacterSystem.marriageRefusal(w, person(w, "casimir4"), person(w, "catherine_p"), date: start), nil)
        XCTAssertEqual(CharacterSystem.marriageRefusal(w, person(w, "henry4_c"), person(w, "ladislaus5"), date: start), .sameSex)
    }

    func testAGoodStewardRaisesTaxes() {
        var w = Scenario1453.makeWorld()
        let tur = country(w, "TUR")
        let before = CharacterSystem.taxBonus(w, tur)
        let steward = w.countries.council[tur.index][CouncilSeat.steward.rawValue]!
        w.people.characters.skills[steward.index][Skill.stewardship.rawValue] = 20
        XCTAssertGreaterThan(CharacterSystem.taxBonus(w, tur), before)
    }

    func testLifeGoesOn() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: start)
        let people = sim.world.people.characters.count
        sim.advance(days: 3650)
        let ch = sim.world.people.characters
        XCTAssertGreaterThan(ch.count, people, "births")
        XCTAssertGreaterThan(ch.death.compactMap { $0 }.count, 50, "deaths")
        for c in sim.world.countries.ids {
            XCTAssertTrue(ch.isAlive(sim.world.countries.ruler[c.index]!))
        }
        let married = ch.ids.filter { ch.isAlive($0) && !ch.spouses[$0.index].isEmpty }.count
        XCTAssertGreaterThan(married, 100)
    }
}

final class VassalTests: XCTestCase {
    let start = Scenario1453.startDate
    func person(_ w: World, _ key: String) -> CharacterID { w.people.characters.id(forKey: key)! }
    func country(_ w: World, _ t: String) -> CountryID { w.countries.id(forTag: t)! }
    func province(_ w: World, _ name: String) -> ProvinceID { ProvinceID(w.provinces.name.firstIndex(of: name)!) }

    func testRealFamiliesAndAncestors() {
        let w = Scenario1453.makeWorld()
        let ch = w.people.characters
        let mehmed = person(w, "mehmed2"), murad = person(w, "murad2")
        XCTAssertEqual(ch.father[mehmed.index], murad)
        XCTAssertFalse(ch.isAlive(murad))
        XCTAssertFalse(ch.isAlive(person(w, "constantine11")))
        XCTAssertEqual(ch.father[person(w, "frederick3").index], person(w, "ernest_iron"))
        XCTAssertTrue(ch.children[person(w, "jodha").index].contains(person(w, "bika")))
        XCTAssertTrue(ch.illegitimate[person(w, "vuk_grg").index])
        // The dead never sit on councils or rule.
        for c in w.countries.ids {
            for x in w.countries.council[c.index].compactMap({ $0 }) { XCTAssertTrue(ch.isAlive(x)) }
        }
    }

    func testHunyadiHoldsHisLands() {
        let w = Scenario1453.makeWorld()
        let hunyadi = person(w, "hunyadi")
        XCTAssertEqual(w.provinces.holder[province(w, "Temesvar").index], hunyadi)
        XCTAssertTrue(VassalSystem.vassals(w, of: country(w, "HUN")).contains(hunyadi))
        XCTAssertGreaterThan(VassalSystem.holdings(w, of: hunyadi).count, 1)
    }

    func testLandPassesToEldestSon() {
        var w = Scenario1453.makeWorld()
        var rng = GameRandom(seed: 3)
        CharacterSystem.kill(&w, person(w, "hunyadi"), date: start, random: &rng)
        XCTAssertEqual(w.provinces.holder[province(w, "Temesvar").index], person(w, "ladislaus_h"))
        XCTAssertTrue(w.people.chronicle.contains { $0.text.contains("inherits") })
    }

    func testBrothersComeBeforeBastards() {
        let w = Scenario1453.makeWorld()
        let heir = VassalSystem.landHeir(w, of: person(w, "grgur_b"), realm: country(w, "SER"))
        XCTAssertEqual(heir, person(w, "stefan_b"))
    }

    func testVassalsKeepTheirShare() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: start)
        sim.advance(days: 40)
        let hun = sim.world.countries.id(forTag: "HUN")!
        XCTAssertGreaterThan(sim.world.countries.lastVassalTax[hun.index], 0)
        XCTAssertGreaterThan(sim.world.people.characters.gold[sim.world.people.characters.id(forKey: "hunyadi")!.index], 0)
    }

    func testGrantAndRevoke() {
        var w = Scenario1453.makeWorld()
        let hun = country(w, "HUN")
        let buda = province(w, "Buda")
        let vitez = person(w, "vitez"), hunyadi = person(w, "hunyadi"), ujlaki = person(w, "ujlaki")
        XCTAssertNil(w.provinces.holder[buda.index])
        let before = VassalSystem.opinionOfLiege(w, vitez, hun)
        XCTAssertTrue(VassalSystem.grant(&w, buda, to: vitez, date: start))
        XCTAssertEqual(w.provinces.holder[buda.index], vitez)
        XCTAssertGreaterThan(VassalSystem.opinionOfLiege(w, vitez, hun), before)
        let ujlakiBefore = w.people.characters.favour[ujlaki.index]
        XCTAssertTrue(VassalSystem.revoke(&w, province(w, "Temesvar"), date: start))
        XCTAssertNil(w.provinces.holder[province(w, "Temesvar").index])
        XCTAssertEqual(w.people.characters.favour[hunyadi.index], VassalModel.revokeFavour)
        XCTAssertEqual(w.people.characters.favour[ujlaki.index], ujlakiBefore + VassalModel.revokeOthersFavour)
    }

    func testAngryVassalsWithholdTaxes() {
        var w = Scenario1453.makeWorld()
        var rng = GameRandom(seed: 5)
        let hun = country(w, "HUN"), garai = person(w, "garai")
        w.countries.taxLevel[hun.index][TaxClass.nobles.rawValue] = 2
        w.people.characters.favour[garai.index] = -60
        XCTAssertNotEqual(VassalSystem.stance(w, garai, hun), .loyal)
        VassalSystem.runMonthly(&w, date: start, random: &rng)
        XCTAssertTrue(w.people.refusing.contains(garai) || !w.people.characters.isAlive(w.countries.ruler[hun.index]!))
    }

    func testVassalLinesGoOn() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: start)
        sim.advance(days: 365 * 30)
        let w = sim.world
        let held = (0..<w.provinces.count).filter { w.provinces.holder[$0] != nil }.count
        XCTAssertGreaterThan(held, 20, "most vassal lines should survive 30 years")
        for p in 0..<w.provinces.count {
            if let h = w.provinces.holder[p] { XCTAssertTrue(w.people.characters.isAlive(h)) }
        }
    }
}

final class GovernmentTests: XCTestCase {
    let start = Scenario1453.startDate
    func country(_ w: World, _ t: String) -> CountryID { w.countries.id(forTag: t)! }
    func area(_ w: World, _ key: String) -> Int { w.government.rules.lawArea(forKey: key)! }
    func option(_ w: World, _ a: Int, _ key: String) -> Int { w.government.rules.lawAreas[a].options.firstIndex { $0.key == key }! }
    func lawKey(_ w: World, _ c: CountryID, _ areaKey: String) -> String {
        let a = area(w, areaKey)
        return w.government.rules.lawAreas[a].options[w.government.laws[c.index][a]].key
    }

    func testRulesAnd1453Laws() {
        let w = Scenario1453.makeWorld()
        let g = w.government
        XCTAssertEqual(g.count, w.countries.count)
        XCTAssertEqual(g.rules.lawAreas.count, 11)
        let tur = country(w, "TUR"), mam = country(w, "MAM"), fra = country(w, "FRA"), ven = country(w, "VEN")
        XCTAssertTrue(g.has(tur, estate: g.rules.estate(forKey: "janissaries")!))
        XCTAssertTrue(g.has(tur, estate: g.rules.estate(forKey: "dhimmi")!))
        XCTAssertTrue(g.has(mam, estate: g.rules.estate(forKey: "mamluks")!))
        XCTAssertFalse(g.has(fra, estate: g.rules.estate(forKey: "janissaries")!))
        XCTAssertEqual(lawKey(w, tur, "crown"), "centralised")
        XCTAssertEqual(lawKey(w, fra, "succession"), "salic")
        XCTAssertEqual(lawKey(w, ven, "coinage"), "sound")
        XCTAssertEqual(g.reforms[ven.index].count, 3)
        XCTAssertEqual(g.stability[tur.index], 2)
        XCTAssertEqual(g.stability[country(w, "MOE").index], -2)
    }

    func testPowerSharesAddUp() {
        let w = Scenario1453.makeWorld()
        for t in ["TUR", "FRA", "VEN", "MAM", "DEL", "MEW", "POL"] {
            let c = country(w, t)
            let g = w.government
            let total = g.crownPower[c.index] + g.estates[c.index].reduce(0) { $0 + g.power[c.index][$1.index] }
            XCTAssertEqual(total, 1, accuracy: 0.001, t)
            for e in g.estates[c.index] {
                XCTAssertGreaterThanOrEqual(g.power[c.index][e.index], 0)
                XCTAssertTrue((0...100).contains(g.loyalty[c.index][e.index]), t)
            }
        }
        // Rajput nobles count as Rajputs in Mewar.
        let mew = country(w, "MEW")
        let rajputs = w.government.rules.estate(forKey: "rajputs")!
        XCTAssertTrue(w.government.has(mew, estate: rajputs))
        XCTAssertGreaterThan(w.government.power[mew.index][rajputs.index], 0.05)
    }

    func testChristiansOfConstantinopleAreDhimmi() {
        let w = Scenario1453.makeWorld()
        let tur = country(w, "TUR")
        let city = w.provinces.id(named: "Konstantiniyye")!
        let dhimmi = w.government.rules.estate(forKey: "dhimmi")!
        let christians = w.pops.range(for: city).filter { w.pops.religion[$0].family == .christian && w.pops.socialClass[$0] != .slaves }
        XCTAssertFalse(christians.isEmpty)
        for i in christians { XCTAssertEqual(GovernmentSystem.estate(of: i, in: tur, w), dhimmi) }
    }

    func testLawChangeTakesSixMonths() {
        var w = Scenario1453.makeWorld()
        var rng = GameRandom(seed: 1)
        let tur = country(w, "TUR")
        w.humanCountries = [tur]
        let a = area(w, "trade"), free = option(w, a, "free")
        w.countries.treasury[tur.index] = 10_000
        XCTAssertNil(GovernmentSystem.changeLaw(&w, tur, area: a, option: free, date: start))
        XCTAssertLessThan(w.countries.treasury[tur.index], 10_000)
        XCTAssertEqual(GovernmentSystem.lawRefusal(w, tur, area: a, option: option(w, a, "guilds")), .alreadyChanging)
        for _ in 0..<5 { GovernmentSystem.runMonthly(&w, date: start, random: &rng) }
        XCTAssertNotEqual(lawKey(w, tur, "trade"), "free")
        GovernmentSystem.runMonthly(&w, date: start, random: &rng)
        XCTAssertEqual(lawKey(w, tur, "trade"), "free")
        XCTAssertGreaterThan(w.government.modifier(tur, .trade), 0.05)
    }

    func testSuccessionLawChange() {
        var w = Scenario1453.makeWorld()
        var rng = GameRandom(seed: 1)
        let fra = country(w, "FRA")
        w.humanCountries = [fra]
        w.countries.treasury[fra.index] = 10_000
        let a = area(w, "succession")
        let before = w.government.stability[fra.index]
        XCTAssertNil(GovernmentSystem.changeLaw(&w, fra, area: a, option: option(w, a, "primogeniture"), date: start))
        XCTAssertEqual(GovernmentSystem.lawRefusal(w, fra, area: a, option: option(w, a, "seniority")), .alreadyChanging)
        for _ in 0..<6 { GovernmentSystem.runMonthly(&w, date: start, random: &rng) }
        XCTAssertEqual(w.countries.succession[fra.index], .primogeniture)
        XCTAssertEqual(w.government.stability[fra.index], max(-3, before - 1))
        // Republics cannot have primogeniture.
        let ven = country(w, "VEN")
        XCTAssertEqual(GovernmentSystem.lawRefusal(w, ven, area: a, option: option(w, a, "primogeniture")), .notAllowed)
    }

    func testPrivilegesGrantAndRevoke() {
        var w = Scenario1453.makeWorld()
        let fra = country(w, "FRA")
        let nobles = w.government.rules.estate(forKey: "nobles")!
        let p = w.government.rules.privileges.firstIndex { $0.key == "tax_exemption" }!
        let before = GovernmentSystem.loyaltyTarget(w, fra, nobles)
        XCTAssertTrue(GovernmentSystem.grantPrivilege(&w, fra, p, date: start))
        XCTAssertFalse(GovernmentSystem.grantPrivilege(&w, fra, p, date: start))
        XCTAssertGreaterThan(GovernmentSystem.loyaltyTarget(w, fra, nobles), before)
        XCTAssertLessThan(GovernmentSystem.classTaxModifier(w, fra, .nobles), -0.5)
        let stability = w.government.stability[fra.index]
        XCTAssertTrue(GovernmentSystem.revokePrivilege(&w, fra, p, date: start))
        XCTAssertEqual(w.government.stability[fra.index], stability - 1)
        XCTAssertLessThan(GovernmentSystem.loyaltyTarget(w, fra, nobles), before)
        // Privileges only for estates the country has.
        let jan = w.government.rules.privileges.firstIndex { $0.estate == w.government.rules.estate(forKey: "janissaries")! }!
        XCTAssertFalse(GovernmentSystem.grantPrivilege(&w, fra, jan, date: start))
    }

    func testSoundMoneyForbidsDebasing() {
        var w = Scenario1453.makeWorld()
        let ven = country(w, "VEN")
        XCTAssertFalse(GovernmentSystem.canDebase(w, ven))
        let before = w.countries.treasury[ven.index]
        XCTAssertEqual(FinanceSystem.debaseOnce(&w, ven), 0)
        XCTAssertEqual(w.countries.treasury[ven.index], before)
    }

    func testStabilityRaiseCostsMoney() {
        var w = Scenario1453.makeWorld()
        let moe = country(w, "MOE")
        w.countries.treasury[moe.index] = 0
        XCTAssertFalse(GovernmentSystem.raiseStability(&w, moe))
        w.countries.treasury[moe.index] = 100_000
        XCTAssertTrue(GovernmentSystem.raiseStability(&w, moe))
        XCTAssertEqual(w.government.stability[moe.index], -1)
        XCTAssertGreaterThan(GovernmentSystem.taxModifier(w, moe) - w.government.modifier(moe, .tax), -0.04)
    }

    func testReformsAndChangingGovernment() {
        var w = Scenario1453.makeWorld()
        let tur = country(w, "TUR")
        let taken = w.government.reforms[tur.index].count
        w.government.reformProgress[tur.index] = 0
        XCTAssertFalse(GovernmentSystem.adoptReform(&w, tur, option: 0, date: start))
        w.government.reformProgress[tur.index] = 1000
        XCTAssertTrue(GovernmentSystem.adoptReform(&w, tur, option: 0, date: start))
        XCTAssertEqual(w.government.reforms[tur.index].count, taken + 1)

        // A prince-bishop can secularise into a monarchy.
        let theocracy = w.countries.ids.first { w.countries.government[$0.index] == .theocracy && w.countries.religion[$0.index].family == .christian }!
        let tree = w.government.rules.reforms[.theocracy]!
        w.government.reforms[theocracy.index] = [0, 0, 0]
        w.government.reformProgress[theocracy.index] = 1000
        let secularise = tree[3].options.firstIndex { $0.key == "secularise" }!
        XCTAssertTrue(GovernmentSystem.adoptReform(&w, theocracy, option: secularise, date: start))
        XCTAssertEqual(w.countries.government[theocracy.index], .monarchy)
        XCTAssertEqual(w.government.reforms[theocracy.index], [0])
        let a = area(w, "succession")
        XCTAssertTrue(w.government.rules.lawAreas[a].options[w.government.laws[theocracy.index][a]].allowed(for: .monarchy))
    }

    func testTwentyYearsStayInBounds() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: start)
        sim.advance(days: 365 * 20)
        let g = sim.world.government
        for c in sim.world.countries.ids where !sim.world.provinces(ownedBy: c).isEmpty {
            XCTAssertTrue((-3...3).contains(g.stability[c.index]))
            var total = g.crownPower[c.index]
            for e in g.estates[c.index] {
                XCTAssertTrue((0...100).contains(g.loyalty[c.index][e.index]))
                total += g.power[c.index][e.index]
            }
            XCTAssertEqual(total, 1, accuracy: 0.001)
        }
        XCTAssertTrue(sim.world.countries.ids.contains { g.reforms[$0.index].count > 1 }, "some AI countries should reform")
    }
}

final class MilitaryDataTests: XCTestCase {
    func testUnitTypesAndSpecialRegionalUnitsLoad() {
        let w = Scenario1453.makeWorld()
        XCTAssertEqual(w.military.unitTypes.count, 15)

        let coreKeys = ["infantry", "cavalry", "archers", "handgunners", "artillery"]
        for key in coreKeys {
            guard let u = w.military.unit(key) else {
                return XCTFail("Missing core unit \(key)")
            }
            XCTAssertTrue(u.requires.isEmpty, "Core unit \(key) should have no unlock restriction")
            XCTAssertFalse(u.goods.isEmpty, "Core unit \(key) should consume market goods when recruited")
        }

        let specialKeys = [
            "janissaries", "mamluk_cavalry", "rajput_cavalry", "war_elephants",
            "horse_archers", "camel_riders", "gendarmes", "longbowmen",
            "swiss_pikemen", "war_wagons",
        ]
        for key in specialKeys {
            guard let u = w.military.unit(key) else {
                return XCTFail("Missing special unit \(key)")
            }
            XCTAssertFalse(u.requires.isEmpty, "Special unit \(key) should have unlock requirements")
        }

        let artillery = w.military.unit("artillery")!
        let horseArchers = w.military.unit("horse_archers")!
        XCTAssertLessThan(artillery.speed, 1.0)
        XCTAssertGreaterThan(horseArchers.speed, 1.0)
    }

    func testStartingStandingArmiesOf1453() {
        let w = Scenario1453.makeWorld()
        XCTAssertEqual(w.military.armies.count, 39)

        let tur = w.countries.id(forTag: "TUR")!
        let konst = w.provinces.id(named: "Konstantiniyye")!
        let mehmed = w.people.characters.id(forKey: "mehmed2")!
        let turArmies = w.military.armies(of: tur)
        XCTAssertEqual(turArmies.count, 2)

        let imperial = turArmies.first { w.military.armies.province[Int($0.rawValue)] == konst }
        XCTAssertNotNil(imperial)
        if let aid = imperial {
            let i = Int(aid.rawValue)
            XCTAssertEqual(w.military.armies.commander[i], mehmed)
            let jan = w.military.unit("janissaries")!.id
            let art = w.military.unit("artillery")!.id
            XCTAssertTrue(w.military.armies.regiments[i].contains { $0.type == jan })
            XCTAssertTrue(w.military.armies.regiments[i].contains { $0.type == art })
            XCTAssertGreaterThan(w.military.armies.totalMen(of: aid), 10_000)
        }

        // Every starting army sits in an owned province with a living commander of that realm.
        for i in 0..<w.military.armies.count where w.military.armies.alive[i] {
            let owner = w.military.armies.owner[i]
            let prov = w.military.armies.province[i]
            XCTAssertEqual(w.provinces.owner[prov.index], owner)
            if let cmd = w.military.armies.commander[i] {
                XCTAssertTrue(w.people.characters.isAlive(cmd))
                XCTAssertEqual(w.people.characters.court[cmd.index], owner)
            }
            XCTAssertFalse(w.military.armies.regiments[i].isEmpty)
        }

        // Starting manpower pools are seeded and positive.
        XCTAssertGreaterThan(w.military.maxManpower[tur.index], 10_000)
        XCTAssertGreaterThan(w.military.manpower[tur.index], 5_000)
    }

    func testSulphurSourcesSupportGunpowder() {
        let w = Scenario1453.makeWorld()
        let sulphur = w.economy.goods.id(forKey: "sulphur")!
        let sulphurProducers = w.economy.producers.good.filter { $0 == sulphur }
        XCTAssertGreaterThanOrEqual(sulphurProducers.count, 5)
    }
}
