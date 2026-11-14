import Foundation

/// How often an automatic save overwrites `autosave.gezsave`.
public enum AutosaveFrequency: String, CaseIterable, Sendable, Codable {
    case monthly
    case everyThreeMonths = "every_three_months"
    case everySixMonths = "every_six_months"
    case yearly
    case never

    public var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .everyThreeMonths: return "Every 3 months"
        case .everySixMonths: return "Every 6 months"
        case .yearly: return "Yearly"
        case .never: return "Never"
        }
    }

    /// True when the daily tick just landed on an autosave boundary.
    public func shouldAutosave(on date: GameDate) -> Bool {
        guard date.isFirstOfMonth else { return false }
        switch self {
        case .monthly:
            return true
        case .everyThreeMonths:
            return (date.month - 1) % 3 == 0
        case .everySixMonths:
            return date.month == 1 || date.month == 7
        case .yearly:
            return date.isFirstOfYear
        case .never:
            return false
        }
    }
}

public enum SaveGameError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedFormatVersion(Int)
    case incompatibleWorldData(String)
    case corruptSaveData

    public var description: String {
        switch self {
        case .unsupportedFormatVersion(let version):
            return "Unsupported save format version \(version)."
        case .incompatibleWorldData(let detail):
            return "Save file does not match the current world data: \(detail)"
        case .corruptSaveData:
            return "Save file is corrupted or unreadable."
        }
    }
}

/// Summary information displayed in the Load Game menu.
public struct SaveMetadata: Equatable, Sendable, Codable {
    public var formatVersion: Int
    public var name: String
    public var gameDate: GameDate
    public var playerTag: String?
    public var playerName: String?
    public var savedAt: Date
    public var isAutosave: Bool

    public init(
        formatVersion: Int = SaveSnapshot.currentFormatVersion,
        name: String,
        gameDate: GameDate,
        playerTag: String?,
        playerName: String?,
        savedAt: Date = Date(),
        isAutosave: Bool = false
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.gameDate = gameDate
        self.playerTag = playerTag
        self.playerName = playerName
        self.savedAt = savedAt
        self.isAutosave = isAutosave
    }
}

public struct SaveEntry: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var metadata: SaveMetadata

    public init(url: URL, metadata: SaveMetadata) {
        self.url = url
        self.metadata = metadata
    }
}

/// Envelope written to `.gezsave` files on disk.
public struct SaveArchive: Sendable, Codable {
    public var metadata: SaveMetadata
    public var snapshot: SaveSnapshot

    public init(metadata: SaveMetadata, snapshot: SaveSnapshot) {
        self.metadata = metadata
        self.snapshot = snapshot
    }
}

/// Complete deterministic snapshot of every mutable field in a running simulation.
public struct SaveSnapshot: Sendable, Codable {
    public static let currentFormatVersion = 1

    public struct ProvincesSnapshot: Sendable, Codable {
        public var owner: [CountryID?]
        public var development: [Int]
        public var population: [Double]
        public var baseTax: [Double]
        public var production: [Double]
        public var religion: [Religion]
        public var majorityCulture: [CultureID]
        public var sufiOrders: [[SufiPresence]]
        public var fortLevel: [Int]
        public var fortGarrison: [Int]
        public var holder: [CharacterID?]
        public var cores: [Set<CountryID>]
        public var claims: [Set<CountryID>]
        public var occupiedBy: [CountryID?]
        public var occupationTarget: [CountryID?]
        public var occupationProgressDays: [Int]
    }

    public struct CountriesSnapshot: Sendable, Codable {
        public var color: [RGB]
        public var government: [GovernmentType]
        public var religion: [Religion]
        public var capital: [ProvinceID?]
        public var slavery: [Double]
        public var overlord: [CountryID?]
        public var subjectType: [SubjectType?]
        public var treasury: [Double]
        public var lastMonthlyIncome: [Double]
        public var lastMonthlyExpenses: [Double]
        public var learning: [Double]
        public var taxLevel: [[Double]]
        public var lastTax: [[Double]]
        public var lastUpkeep: [Double]
        public var lastInterest: [Double]
        public var inflation: [Double]
        public var debasing: [Bool]
        public var bankruptMonthsLeft: [Int]
        public var embargoes: [Set<CountryID>]
        public var tollPolicy: [TollPolicy]
        public var ruler: [CharacterID?]
        public var heir: [CharacterID?]
        public var council: [[CharacterID?]]
        public var succession: [SuccessionLaw]
        public var lastTrade: [Double]
        public var lastTolls: [Double]
        public var lastVassalTax: [Double]
    }

    public struct PopsSnapshot: Sendable, Codable {
        public var size: [Double]
        public var satisfaction: [Double]
    }

    public struct EconomySnapshot: Sendable, Codable {
        public var marketPrice: [Double]
        public var marketSupply: [Double]
        public var marketDemand: [Double]
        public var marketMet: [Double]
        public var marketImports: [Double]
        public var marketPendingDemand: [Double]
        public var provinceMarket: [MarketID]
        public var routes: [TradeRoute]
        public var producerShare: [Double]
        public var producerOutput: [Double]
        public var producerValue: [Double]
        public var buildingLevel: [Int]
        public var constructions: [Construction]
        public var workshopOutput: [Double]
        public var workshopValue: [Double]
    }

    public struct FinanceSnapshot: Sendable, Codable {
        public var bankCapital: [Double]
        public var loans: [Loan]
    }

    public struct PeopleSnapshot: Sendable, Codable {
        public var characters: CharacterTable
        public var chronicle: [ChronicleEntry]
        public var refusing: Set<CharacterID>
    }

    public struct GovernmentSnapshot: Sendable, Codable {
        public var stability: [Int]
        public var laws: [[Int]]
        public var pending: [[PendingLaw]]
        public var reforms: [[Int]]
        public var reformProgress: [Double]
        public var estates: [[EstateID]]
        public var loyalty: [[Double]]
        public var power: [[Double]]
        public var crownPower: [Double]
        public var contentment: [[Double]]
        public var privileges: [Set<Int>]
        public var grudge: [[Double]]
        public var effects: [Effects]
    }

    public struct MilitarySnapshot: Sendable, Codable {
        public var armies: ArmyTable
        public var manpower: [Double]
        public var maxManpower: [Double]
        public var lastArmyUpkeep: [Double]
        public var lastAttritionLosses: [Int]
        public var battles: [Battle]
        public var recentBattles: [BattleReport]
        public var sieges: [Siege]
    }

    public var formatVersion: Int
    public var date: GameDate
    public var ticksRun: Int
    public var randomState: UInt64
    public var humanCountries: Set<CountryID>
    public var provinces: ProvincesSnapshot
    public var countries: CountriesSnapshot
    public var pops: PopsSnapshot
    public var economy: EconomySnapshot
    public var finance: FinanceSnapshot
    public var people: PeopleSnapshot
    public var government: GovernmentSnapshot
    public var military: MilitarySnapshot
    public var diplomacy: Diplomacy

    public init(capturing simulation: Simulation) {
        let w = simulation.world
        self.formatVersion = Self.currentFormatVersion
        self.date = simulation.date
        self.ticksRun = simulation.ticksRun
        self.randomState = simulation.random.rawState
        self.humanCountries = w.humanCountries

        self.provinces = ProvincesSnapshot(
            owner: w.provinces.owner,
            development: w.provinces.development,
            population: w.provinces.population,
            baseTax: w.provinces.baseTax,
            production: w.provinces.production,
            religion: w.provinces.religion,
            majorityCulture: w.provinces.majorityCulture,
            sufiOrders: w.provinces.sufiOrders,
            fortLevel: w.provinces.fortLevel,
            fortGarrison: w.provinces.fortGarrison,
            holder: w.provinces.holder,
            cores: w.provinces.cores,
            claims: w.provinces.claims,
            occupiedBy: w.provinces.occupiedBy,
            occupationTarget: w.provinces.occupationTarget,
            occupationProgressDays: w.provinces.occupationProgressDays
        )

        self.countries = CountriesSnapshot(
            color: w.countries.color,
            government: w.countries.government,
            religion: w.countries.religion,
            capital: w.countries.capital,
            slavery: w.countries.slavery,
            overlord: w.countries.overlord,
            subjectType: w.countries.subjectType,
            treasury: w.countries.treasury,
            lastMonthlyIncome: w.countries.lastMonthlyIncome,
            lastMonthlyExpenses: w.countries.lastMonthlyExpenses,
            learning: w.countries.learning,
            taxLevel: w.countries.taxLevel,
            lastTax: w.countries.lastTax,
            lastUpkeep: w.countries.lastUpkeep,
            lastInterest: w.countries.lastInterest,
            inflation: w.countries.inflation,
            debasing: w.countries.debasing,
            bankruptMonthsLeft: w.countries.bankruptMonthsLeft,
            embargoes: w.countries.embargoes,
            tollPolicy: w.countries.tollPolicy,
            ruler: w.countries.ruler,
            heir: w.countries.heir,
            council: w.countries.council,
            succession: w.countries.succession,
            lastTrade: w.countries.lastTrade,
            lastTolls: w.countries.lastTolls,
            lastVassalTax: w.countries.lastVassalTax
        )

        self.pops = PopsSnapshot(
            size: w.pops.size,
            satisfaction: w.pops.satisfaction
        )

        self.economy = EconomySnapshot(
            marketPrice: w.economy.markets.price,
            marketSupply: w.economy.markets.supply,
            marketDemand: w.economy.markets.demand,
            marketMet: w.economy.markets.met,
            marketImports: w.economy.markets.imports,
            marketPendingDemand: w.economy.markets.pendingDemand,
            provinceMarket: w.economy.provinceMarket,
            routes: w.economy.routes,
            producerShare: w.economy.producers.share,
            producerOutput: w.economy.producers.output,
            producerValue: w.economy.producers.value,
            buildingLevel: w.economy.buildings.level,
            constructions: w.economy.buildings.constructions,
            workshopOutput: w.economy.workshopOutput,
            workshopValue: w.economy.workshopValue
        )

        self.finance = FinanceSnapshot(
            bankCapital: w.finance.banks.capital,
            loans: w.finance.loans
        )

        self.people = PeopleSnapshot(
            characters: w.people.characters,
            chronicle: w.people.chronicle,
            refusing: w.people.refusing
        )

        self.government = GovernmentSnapshot(
            stability: w.government.stability,
            laws: w.government.laws,
            pending: w.government.pending,
            reforms: w.government.reforms,
            reformProgress: w.government.reformProgress,
            estates: w.government.estates,
            loyalty: w.government.loyalty,
            power: w.government.power,
            crownPower: w.government.crownPower,
            contentment: w.government.contentment,
            privileges: w.government.privileges,
            grudge: w.government.grudge,
            effects: w.government.effects
        )

        self.military = MilitarySnapshot(
            armies: w.military.armies,
            manpower: w.military.manpower,
            maxManpower: w.military.maxManpower,
            lastArmyUpkeep: w.military.lastArmyUpkeep,
            lastAttritionLosses: w.military.lastAttritionLosses,
            battles: w.military.battles,
            recentBattles: w.military.recentBattles,
            sieges: w.military.sieges
        )

        self.diplomacy = w.diplomacy
    }

    /// Rebuilds an identical `Simulation` using a freshly created static base `World`.
    public func restore(onto baseWorldFactory: () throws -> World = { Scenario1453.makeWorld() }) throws -> Simulation {
        guard formatVersion == Self.currentFormatVersion else {
            throw SaveGameError.unsupportedFormatVersion(formatVersion)
        }
        var w = try baseWorldFactory()

        guard provinces.owner.count == w.provinces.count else {
            throw SaveGameError.incompatibleWorldData("province count mismatch (\(provinces.owner.count) vs \(w.provinces.count))")
        }
        guard countries.treasury.count == w.countries.count else {
            throw SaveGameError.incompatibleWorldData("country count mismatch (\(countries.treasury.count) vs \(w.countries.count))")
        }
        guard pops.size.count == w.pops.count else {
            throw SaveGameError.incompatibleWorldData("pop row count mismatch (\(pops.size.count) vs \(w.pops.count))")
        }
        guard economy.producerOutput.count == w.economy.producers.count else {
            throw SaveGameError.incompatibleWorldData("producer row count mismatch")
        }
        guard economy.buildingLevel.count == w.economy.buildings.level.count else {
            throw SaveGameError.incompatibleWorldData("building slot count mismatch")
        }
        guard finance.bankCapital.count == w.finance.banks.count else {
            throw SaveGameError.incompatibleWorldData("bank count mismatch")
        }

        w.humanCountries = humanCountries

        w.provinces.owner = provinces.owner
        w.provinces.development = provinces.development
        w.provinces.population = provinces.population
        w.provinces.baseTax = provinces.baseTax
        w.provinces.production = provinces.production
        w.provinces.religion = provinces.religion
        w.provinces.majorityCulture = provinces.majorityCulture
        w.provinces.sufiOrders = provinces.sufiOrders
        w.provinces.fortLevel = provinces.fortLevel
        w.provinces.fortGarrison = provinces.fortGarrison
        w.provinces.holder = provinces.holder
        w.provinces.cores = provinces.cores
        w.provinces.claims = provinces.claims
        w.provinces.occupiedBy = provinces.occupiedBy
        w.provinces.occupationTarget = provinces.occupationTarget
        w.provinces.occupationProgressDays = provinces.occupationProgressDays

        w.countries.color = countries.color
        w.countries.government = countries.government
        w.countries.religion = countries.religion
        w.countries.capital = countries.capital
        w.countries.slavery = countries.slavery
        w.countries.overlord = countries.overlord
        w.countries.subjectType = countries.subjectType
        w.countries.treasury = countries.treasury
        w.countries.lastMonthlyIncome = countries.lastMonthlyIncome
        w.countries.lastMonthlyExpenses = countries.lastMonthlyExpenses
        w.countries.learning = countries.learning
        w.countries.taxLevel = countries.taxLevel
        w.countries.lastTax = countries.lastTax
        w.countries.lastUpkeep = countries.lastUpkeep
        w.countries.lastInterest = countries.lastInterest
        w.countries.inflation = countries.inflation
        w.countries.debasing = countries.debasing
        w.countries.bankruptMonthsLeft = countries.bankruptMonthsLeft
        w.countries.embargoes = countries.embargoes
        w.countries.tollPolicy = countries.tollPolicy
        w.countries.ruler = countries.ruler
        w.countries.heir = countries.heir
        w.countries.council = countries.council
        w.countries.succession = countries.succession
        w.countries.lastTrade = countries.lastTrade
        w.countries.lastTolls = countries.lastTolls
        w.countries.lastVassalTax = countries.lastVassalTax

        w.pops.size = pops.size
        w.pops.satisfaction = pops.satisfaction

        w.economy.markets.price = economy.marketPrice
        w.economy.markets.supply = economy.marketSupply
        w.economy.markets.demand = economy.marketDemand
        w.economy.markets.met = economy.marketMet
        w.economy.markets.imports = economy.marketImports
        w.economy.markets.pendingDemand = economy.marketPendingDemand
        w.economy.provinceMarket = economy.provinceMarket
        w.economy.routes = economy.routes
        w.economy.producers.share = economy.producerShare
        w.economy.producers.output = economy.producerOutput
        w.economy.producers.value = economy.producerValue
        w.economy.buildings.level = economy.buildingLevel
        w.economy.buildings.constructions = economy.constructions
        w.economy.workshopOutput = economy.workshopOutput
        w.economy.workshopValue = economy.workshopValue

        w.finance.banks.capital = finance.bankCapital
        w.finance.loans = finance.loans

        w.people.characters = people.characters
        w.people.chronicle = people.chronicle
        w.people.refusing = people.refusing

        w.government.stability = government.stability
        w.government.laws = government.laws
        w.government.pending = government.pending
        w.government.reforms = government.reforms
        w.government.reformProgress = government.reformProgress
        w.government.estates = government.estates
        w.government.loyalty = government.loyalty
        w.government.power = government.power
        w.government.crownPower = government.crownPower
        w.government.contentment = government.contentment
        w.government.privileges = government.privileges
        w.government.grudge = government.grudge
        w.government.effects = government.effects

        w.military.armies = military.armies
        w.military.manpower = military.manpower
        w.military.maxManpower = military.maxManpower
        w.military.lastArmyUpkeep = military.lastArmyUpkeep
        w.military.lastAttritionLosses = military.lastAttritionLosses
        w.military.battles = military.battles
        w.military.recentBattles = military.recentBattles
        w.military.sieges = military.sieges

        w.diplomacy = diplomacy

        return Simulation(
            restoringWorld: w,
            date: date,
            random: GameRandom(seed: randomState),
            ticksRun: ticksRun
        )
    }
}

/// Manages local save files (`*.gezsave`) and single-file autosaves via `FileManager`.
public enum SaveStorage {
    public static let fileExtension = "gezsave"
    public static let autosaveFileName = "autosave"

    public static func defaultDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Gez", isDirectory: true)
            .appendingPathComponent("Saves", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func sanitizedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let parts = trimmed.components(separatedBy: forbidden).filter { !$0.isEmpty }
        let joined = parts.joined(separator: "_")
        return joined.isEmpty ? "save" : joined
    }

    public static func encodeArchive(
        _ simulation: Simulation,
        name: String,
        playerTag: String?,
        isAutosave: Bool = false,
        savedAt: Date = Date()
    ) throws -> Data {
        let playerID = playerTag.flatMap { simulation.world.countries.id(forTag: $0) }
        let playerName = playerID.map { simulation.world.countries.name[$0.index] }
        let metadata = SaveMetadata(
            formatVersion: SaveSnapshot.currentFormatVersion,
            name: name,
            gameDate: simulation.date,
            playerTag: playerTag,
            playerName: playerName,
            savedAt: savedAt,
            isAutosave: isAutosave
        )
        let archive = SaveArchive(
            metadata: metadata,
            snapshot: SaveSnapshot(capturing: simulation)
        )
        let encoder = JSONEncoder()
        return try encoder.encode(archive)
    }

    public static func decodeArchive(
        from data: Data,
        baseWorldFactory: () throws -> World = { Scenario1453.makeWorld() }
    ) throws -> (simulation: Simulation, metadata: SaveMetadata) {
        let archive: SaveArchive
        do {
            archive = try JSONDecoder().decode(SaveArchive.self, from: data)
        } catch {
            throw SaveGameError.corruptSaveData
        }
        guard archive.metadata.formatVersion == SaveSnapshot.currentFormatVersion else {
            throw SaveGameError.unsupportedFormatVersion(archive.metadata.formatVersion)
        }
        let sim = try archive.snapshot.restore(onto: baseWorldFactory)
        return (sim, archive.metadata)
    }

    @discardableResult
    public static func save(
        _ simulation: Simulation,
        name: String,
        playerTag: String?,
        isAutosave: Bool = false,
        in directory: URL? = nil,
        savedAt: Date = Date()
    ) throws -> URL {
        let dir = try directory ?? defaultDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = isAutosave ? autosaveFileName : sanitizedName(name)
        let url = dir.appendingPathComponent("\(safe).\(fileExtension)")
        let data = try encodeArchive(
            simulation,
            name: name,
            playerTag: playerTag,
            isAutosave: isAutosave,
            savedAt: savedAt
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    public static func autosave(
        _ simulation: Simulation,
        playerTag: String?,
        in directory: URL? = nil,
        savedAt: Date = Date()
    ) throws -> URL {
        try save(
            simulation,
            name: "Autosave",
            playerTag: playerTag,
            isAutosave: true,
            in: directory,
            savedAt: savedAt
        )
    }

    public static func load(
        from url: URL,
        baseWorldFactory: () throws -> World = { Scenario1453.makeWorld() }
    ) throws -> (simulation: Simulation, metadata: SaveMetadata) {
        let data = try Data(contentsOf: url)
        return try decodeArchive(from: data, baseWorldFactory: baseWorldFactory)
    }

    public static func listSaves(in directory: URL? = nil) -> [SaveEntry] {
        guard let dir = try? (directory ?? defaultDirectory()),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        var entries: [SaveEntry] = []
        let decoder = JSONDecoder()
        for url in files where url.pathExtension == fileExtension {
            guard let data = try? Data(contentsOf: url),
                  let archive = try? decoder.decode(SaveArchive.self, from: data) else {
                continue
            }
            entries.append(SaveEntry(url: url, metadata: archive.metadata))
        }
        return entries.sorted { lhs, rhs in
            if lhs.metadata.savedAt != rhs.metadata.savedAt {
                return lhs.metadata.savedAt > rhs.metadata.savedAt
            }
            return lhs.url.lastPathComponent < rhs.url.lastPathComponent
        }
    }

    public static func deleteSave(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
