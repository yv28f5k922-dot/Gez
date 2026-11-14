import Testing
import Foundation
@testable import GezCore

@Suite("SaveLoad")
struct SaveLoadTests {
    @Test("Saving, loading, and running N days matches uninterrupted simulation exactly")
    func exactDeterminismAfterReload() throws {
        let baseA = Scenario1453.makeWorld()
        let simA = Simulation(world: baseA, startDate: Scenario1453.startDate, seed: 1453)
        simA.advance(days: 90)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GezSaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let saveURL = try SaveStorage.save(simA, name: "Day90", playerTag: "TUR", in: tempDir)
        let (simB, metadata) = try SaveStorage.load(from: saveURL)

        #expect(metadata.name == "Day90")
        #expect(metadata.playerTag == "TUR")
        #expect(metadata.gameDate == simA.date)
        #expect(!metadata.isAutosave)

        // Run both simulations 180 more days after reload.
        simA.advance(days: 180)
        simB.advance(days: 180)

        #expect(simA.date == simB.date)
        #expect(simA.ticksRun == simB.ticksRun)
        #expect(simA.random.rawState == simB.random.rawState)

        let wA = simA.world
        let wB = simB.world

        #expect(wA.provinces.owner == wB.provinces.owner)
        #expect(wA.provinces.fortGarrison == wB.provinces.fortGarrison)
        #expect(wA.provinces.occupiedBy == wB.provinces.occupiedBy)
        #expect(wA.provinces.development == wB.provinces.development)
        #expect(wA.provinces.population == wB.provinces.population)

        #expect(wA.countries.treasury == wB.countries.treasury)
        #expect(wA.countries.inflation == wB.countries.inflation)
        #expect(wA.countries.capital == wB.countries.capital)
        #expect(wA.countries.ruler == wB.countries.ruler)
        #expect(wA.countries.heir == wB.countries.heir)

        #expect(wA.pops.size == wB.pops.size)
        #expect(wA.pops.satisfaction == wB.pops.satisfaction)

        #expect(wA.economy.markets.price == wB.economy.markets.price)
        #expect(wA.economy.markets.supply == wB.economy.markets.supply)
        #expect(wA.economy.routes == wB.economy.routes)
        #expect(wA.economy.buildings.level == wB.economy.buildings.level)
        #expect(wA.economy.buildings.constructions == wB.economy.buildings.constructions)

        #expect(wA.finance.banks.capital == wB.finance.banks.capital)
        #expect(wA.finance.loans == wB.finance.loans)

        #expect(wA.people.characters.count == wB.people.characters.count)
        #expect(wA.people.chronicle == wB.people.chronicle)

        #expect(wA.government.stability == wB.government.stability)
        #expect(wA.government.reformProgress == wB.government.reformProgress)

        #expect(wA.military.armies.province == wB.military.armies.province)
        #expect(wA.military.armies.regiments == wB.military.armies.regiments)
        #expect(wA.military.manpower == wB.military.manpower)
        #expect(wA.military.battles == wB.military.battles)
        #expect(wA.military.sieges == wB.military.sieges)

        #expect(wA.diplomacy.wars == wB.diplomacy.wars)
        #expect(wA.diplomacy.treaties == wB.diplomacy.treaties)
        #expect(wA.diplomacy.opinions == wB.diplomacy.opinions)
        #expect(wA.diplomacy.aggressiveExpansion == wB.diplomacy.aggressiveExpansion)
        #expect(wA.diplomacy.pendingPeaceOffers == wB.diplomacy.pendingPeaceOffers)
    }

    @Test("Autosave overwrites single file and schedule respects cadence")
    func autosaveSingleFileAndCadence() throws {
        #expect(AutosaveFrequency.monthly.shouldAutosave(on: GameDate(year: 1453, month: 6, day: 1)))
        #expect(!AutosaveFrequency.monthly.shouldAutosave(on: GameDate(year: 1453, month: 6, day: 2)))

        #expect(AutosaveFrequency.everyThreeMonths.shouldAutosave(on: GameDate(year: 1453, month: 7, day: 1)))
        #expect(!AutosaveFrequency.everyThreeMonths.shouldAutosave(on: GameDate(year: 1453, month: 6, day: 1)))

        #expect(AutosaveFrequency.everySixMonths.shouldAutosave(on: GameDate(year: 1453, month: 7, day: 1)))
        #expect(!AutosaveFrequency.everySixMonths.shouldAutosave(on: GameDate(year: 1453, month: 4, day: 1)))

        #expect(AutosaveFrequency.yearly.shouldAutosave(on: GameDate(year: 1454, month: 1, day: 1)))
        #expect(!AutosaveFrequency.yearly.shouldAutosave(on: GameDate(year: 1453, month: 7, day: 1)))

        #expect(!AutosaveFrequency.never.shouldAutosave(on: GameDate(year: 1454, month: 1, day: 1)))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GezAutosaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let world = Scenario1453.makeWorld()
        let sim = Simulation(world: world, startDate: Scenario1453.startDate, seed: 42)
        sim.advance(days: 5)
        try SaveStorage.autosave(sim, playerTag: "FRA", in: tempDir, savedAt: Date(timeIntervalSince1970: 100))

        sim.advance(days: 30)
        try SaveStorage.autosave(sim, playerTag: "FRA", in: tempDir, savedAt: Date(timeIntervalSince1970: 200))

        let entries = SaveStorage.listSaves(in: tempDir)
        #expect(entries.count == 1)
        #expect(entries[0].metadata.isAutosave)
        #expect(entries[0].metadata.gameDate == sim.date)
        #expect(entries[0].url.lastPathComponent == "autosave.gezsave")
    }

    @Test("Corrupt or future-version saves throw typed errors")
    func invalidSavesThrowTypedError() throws {
        do {
            _ = try SaveStorage.decodeArchive(from: Data("not json".utf8))
            Issue.record("Expected corruptSaveData")
        } catch let error as SaveGameError {
            #expect(error == .corruptSaveData)
        }

        let world = Scenario1453.makeWorld()
        let sim = Simulation(world: world, startDate: Scenario1453.startDate, seed: 1)
        var snapshot = SaveSnapshot(capturing: sim)
        snapshot.formatVersion = 99
        let archive = SaveArchive(
            metadata: SaveMetadata(
                formatVersion: 99,
                name: "Future",
                gameDate: sim.date,
                playerTag: "TUR",
                playerName: "Ottomans"
            ),
            snapshot: snapshot
        )
        let data = try JSONEncoder().encode(archive)
        do {
            _ = try SaveStorage.decodeArchive(from: data)
            Issue.record("Expected unsupportedFormatVersion")
        } catch let error as SaveGameError {
            #expect(error == .unsupportedFormatVersion(99))
        }
    }
}
