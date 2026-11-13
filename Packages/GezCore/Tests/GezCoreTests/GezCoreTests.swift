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

    func testTenYearsRunsQuickly() {
        let sim = Simulation(world: Scenario1453.makeWorld(), startDate: Scenario1453.startDate)
        measure {
            sim.advance(days: 3650)
        }
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
