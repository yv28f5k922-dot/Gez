/// Starting scenario: 30 May 1453, the day after Mehmed II took Constantinople.
///
/// PLACEHOLDER DATA. Each country currently has only its capital (plus a few
/// extra provinces for the Ottomans and Venice), placed by real latitude and
/// longitude. Population, tax, production and fort values are rough guesses.
/// The full province map (Europe, North Africa, Horn of Africa, Middle East,
/// Central Asia, India) replaces this in the map milestone.
public enum Scenario1453 {
    public static let startDate = GameDate(year: 1453, month: 5, day: 30)
    public static let defaultPlayerTag = "TUR"

    struct CountrySpec {
        let tag: String
        let name: String
        let color: RGB
        let government: GovernmentType
        let religion: Religion
        let treasury: Double
    }

    struct ProvinceSpec {
        let name: String
        let owner: String
        let lat: Double
        let lon: Double
        let terrain: Terrain
        let population: Double
        let tax: Double
        let production: Double
        let fort: Int
        let isCapital: Bool
    }

    // swiftlint:disable line_length
    static let countries: [CountrySpec] = [
        // Anatolia, Balkans, Caucasus
        .init(tag: "TUR", name: "Ottoman Empire", color: RGB(186, 45, 45), government: .monarchy, religion: .sunni, treasury: 150),
        .init(tag: "KAR", name: "Karaman", color: RGB(120, 160, 110), government: .monarchy, religion: .sunni, treasury: 40),
        .init(tag: "TRE", name: "Trebizond", color: RGB(150, 70, 140), government: .monarchy, religion: .orthodox, treasury: 25),
        .init(tag: "MOE", name: "Despotate of the Morea", color: RGB(210, 140, 200), government: .monarchy, religion: .orthodox, treasury: 15),
        .init(tag: "SER", name: "Serbia", color: RGB(150, 40, 60), government: .monarchy, religion: .orthodox, treasury: 30),
        .init(tag: "BOS", name: "Bosnia", color: RGB(90, 120, 170), government: .monarchy, religion: .catholic, treasury: 20),
        .init(tag: "WAL", name: "Wallachia", color: RGB(200, 170, 70), government: .monarchy, religion: .orthodox, treasury: 25),
        .init(tag: "MOL", name: "Moldavia", color: RGB(230, 200, 90), government: .monarchy, religion: .orthodox, treasury: 25),
        .init(tag: "GEO", name: "Georgia", color: RGB(220, 220, 220), government: .monarchy, religion: .orthodox, treasury: 25),
        .init(tag: "KNI", name: "Knights Hospitaller", color: RGB(60, 60, 60), government: .theocracy, religion: .catholic, treasury: 40),
        // Italy
        .init(tag: "VEN", name: "Venice", color: RGB(60, 150, 140), government: .republic, religion: .catholic, treasury: 200),
        .init(tag: "GEN", name: "Genoa", color: RGB(200, 90, 90), government: .republic, religion: .catholic, treasury: 120),
        .init(tag: "MLO", name: "Milan", color: RGB(140, 180, 220), government: .monarchy, religion: .catholic, treasury: 100),
        .init(tag: "FLO", name: "Florence", color: RGB(150, 60, 150), government: .republic, religion: .catholic, treasury: 110),
        .init(tag: "PAP", name: "Papal States", color: RGB(240, 230, 170), government: .theocracy, religion: .catholic, treasury: 90),
        .init(tag: "NAP", name: "Naples", color: RGB(110, 170, 120), government: .monarchy, religion: .catholic, treasury: 80),
        // Central and Eastern Europe
        .init(tag: "HUN", name: "Hungary", color: RGB(170, 200, 120), government: .monarchy, religion: .catholic, treasury: 100),
        .init(tag: "HAB", name: "Austria", color: RGB(240, 240, 240), government: .monarchy, religion: .catholic, treasury: 90),
        .init(tag: "BOH", name: "Bohemia", color: RGB(220, 170, 100), government: .monarchy, religion: .catholic, treasury: 70),
        .init(tag: "POL", name: "Poland", color: RGB(200, 70, 100), government: .monarchy, religion: .catholic, treasury: 90),
        .init(tag: "LIT", name: "Lithuania", color: RGB(190, 220, 160), government: .monarchy, religion: .catholic, treasury: 70),
        .init(tag: "MOS", name: "Muscovy", color: RGB(110, 140, 70), government: .monarchy, religion: .orthodox, treasury: 60),
        .init(tag: "KAZ", name: "Kazan", color: RGB(150, 110, 70), government: .steppeHorde, religion: .sunni, treasury: 40),
        .init(tag: "GRH", name: "Great Horde", color: RGB(170, 140, 80), government: .steppeHorde, religion: .sunni, treasury: 40),
        .init(tag: "CRI", name: "Crimea", color: RGB(110, 170, 70), government: .steppeHorde, religion: .sunni, treasury: 40),
        // Western Europe
        .init(tag: "FRA", name: "France", color: RGB(30, 60, 160), government: .monarchy, religion: .catholic, treasury: 150),
        .init(tag: "ENG", name: "England", color: RGB(180, 30, 40), government: .monarchy, religion: .catholic, treasury: 130),
        .init(tag: "SCO", name: "Scotland", color: RGB(80, 120, 200), government: .monarchy, religion: .catholic, treasury: 40),
        .init(tag: "BUR", name: "Burgundy", color: RGB(190, 120, 50), government: .monarchy, religion: .catholic, treasury: 140),
        .init(tag: "DAN", name: "Denmark", color: RGB(170, 50, 70), government: .monarchy, religion: .catholic, treasury: 80),
        .init(tag: "CAS", name: "Castile", color: RGB(220, 190, 50), government: .monarchy, religion: .catholic, treasury: 120),
        .init(tag: "ARA", name: "Aragon", color: RGB(200, 160, 40), government: .monarchy, religion: .catholic, treasury: 100),
        .init(tag: "POR", name: "Portugal", color: RGB(40, 120, 70), government: .monarchy, religion: .catholic, treasury: 80),
        .init(tag: "GRA", name: "Granada", color: RGB(70, 140, 90), government: .monarchy, religion: .sunni, treasury: 50),
        // North Africa and Middle East
        .init(tag: "MOR", name: "Morocco", color: RGB(170, 80, 60), government: .monarchy, religion: .sunni, treasury: 70),
        .init(tag: "TLE", name: "Tlemcen", color: RGB(210, 150, 110), government: .monarchy, religion: .sunni, treasury: 40),
        .init(tag: "TUN", name: "Tunis", color: RGB(120, 160, 70), government: .monarchy, religion: .sunni, treasury: 60),
        .init(tag: "MAM", name: "Mamluk Sultanate", color: RGB(220, 200, 110), government: .monarchy, religion: .sunni, treasury: 200),
        .init(tag: "HEJ", name: "Sharifate of Mecca", color: RGB(110, 190, 150), government: .theocracy, religion: .sunni, treasury: 40),
        .init(tag: "AKK", name: "Aq Qoyunlu", color: RGB(230, 230, 200), government: .steppeHorde, religion: .sunni, treasury: 60),
        .init(tag: "QAR", name: "Qara Qoyunlu", color: RGB(50, 50, 80), government: .steppeHorde, religion: .shia, treasury: 80),
        .init(tag: "TIM", name: "Timurid Empire", color: RGB(140, 70, 160), government: .monarchy, religion: .sunni, treasury: 120),
        // Horn of Africa
        .init(tag: "ETH", name: "Ethiopia", color: RGB(100, 160, 60), government: .monarchy, religion: .miaphysite, treasury: 70),
        .init(tag: "ADA", name: "Adal", color: RGB(180, 150, 90), government: .monarchy, religion: .sunni, treasury: 40),
        // India
        .init(tag: "DEL", name: "Delhi Sultanate", color: RGB(200, 120, 50), government: .monarchy, religion: .sunni, treasury: 120),
        .init(tag: "JNP", name: "Jaunpur", color: RGB(160, 200, 200), government: .monarchy, religion: .sunni, treasury: 80),
        .init(tag: "BNG", name: "Bengal", color: RGB(60, 140, 120), government: .monarchy, religion: .sunni, treasury: 130),
        .init(tag: "GUJ", name: "Gujarat", color: RGB(230, 160, 120), government: .monarchy, religion: .sunni, treasury: 130),
        .init(tag: "MLW", name: "Malwa", color: RGB(120, 100, 60), government: .monarchy, religion: .sunni, treasury: 80),
        .init(tag: "KSH", name: "Kashmir", color: RGB(150, 200, 230), government: .monarchy, religion: .sunni, treasury: 50),
        .init(tag: "BAH", name: "Bahmani Sultanate", color: RGB(60, 110, 60), government: .monarchy, religion: .sunni, treasury: 130),
        .init(tag: "VIJ", name: "Vijayanagara", color: RGB(230, 120, 160), government: .monarchy, religion: .hindu, treasury: 150),
    ]

    static let provinces: [ProvinceSpec] = [
        .init(name: "Konstantiniyye", owner: "TUR", lat: 41.01, lon: 28.98, terrain: .farmland, population: 50_000, tax: 12, production: 10, fort: 3, isCapital: true),
        .init(name: "Edirne", owner: "TUR", lat: 41.68, lon: 26.56, terrain: .farmland, population: 40_000, tax: 8, production: 6, fort: 2, isCapital: false),
        .init(name: "Bursa", owner: "TUR", lat: 40.19, lon: 29.06, terrain: .hills, population: 45_000, tax: 8, production: 8, fort: 2, isCapital: false),
        .init(name: "Konya", owner: "KAR", lat: 37.87, lon: 32.48, terrain: .plains, population: 35_000, tax: 6, production: 5, fort: 2, isCapital: true),
        .init(name: "Trebizond", owner: "TRE", lat: 41.00, lon: 39.72, terrain: .hills, population: 30_000, tax: 5, production: 6, fort: 2, isCapital: true),
        .init(name: "Mystras", owner: "MOE", lat: 37.07, lon: 22.37, terrain: .hills, population: 20_000, tax: 4, production: 3, fort: 2, isCapital: true),
        .init(name: "Smederevo", owner: "SER", lat: 44.66, lon: 20.93, terrain: .plains, population: 25_000, tax: 5, production: 4, fort: 3, isCapital: true),
        .init(name: "Jajce", owner: "BOS", lat: 44.34, lon: 17.27, terrain: .mountains, population: 15_000, tax: 3, production: 3, fort: 2, isCapital: true),
        .init(name: "Targoviste", owner: "WAL", lat: 44.93, lon: 25.46, terrain: .plains, population: 20_000, tax: 4, production: 3, fort: 1, isCapital: true),
        .init(name: "Suceava", owner: "MOL", lat: 47.65, lon: 26.26, terrain: .hills, population: 20_000, tax: 4, production: 3, fort: 2, isCapital: true),
        .init(name: "Tbilisi", owner: "GEO", lat: 41.72, lon: 44.79, terrain: .mountains, population: 25_000, tax: 4, production: 4, fort: 2, isCapital: true),
        .init(name: "Rhodes", owner: "KNI", lat: 36.43, lon: 28.22, terrain: .hills, population: 15_000, tax: 3, production: 4, fort: 4, isCapital: true),
        .init(name: "Venice", owner: "VEN", lat: 45.44, lon: 12.33, terrain: .marsh, population: 100_000, tax: 12, production: 16, fort: 3, isCapital: true),
        .init(name: "Candia", owner: "VEN", lat: 35.34, lon: 25.13, terrain: .hills, population: 30_000, tax: 5, production: 5, fort: 3, isCapital: false),
        .init(name: "Genoa", owner: "GEN", lat: 44.41, lon: 8.93, terrain: .hills, population: 60_000, tax: 8, production: 12, fort: 3, isCapital: true),
        .init(name: "Milan", owner: "MLO", lat: 45.46, lon: 9.19, terrain: .farmland, population: 90_000, tax: 12, production: 12, fort: 3, isCapital: true),
        .init(name: "Florence", owner: "FLO", lat: 43.77, lon: 11.26, terrain: .hills, population: 60_000, tax: 9, production: 13, fort: 2, isCapital: true),
        .init(name: "Rome", owner: "PAP", lat: 41.90, lon: 12.50, terrain: .farmland, population: 40_000, tax: 8, production: 7, fort: 2, isCapital: true),
        .init(name: "Naples", owner: "NAP", lat: 40.85, lon: 14.27, terrain: .farmland, population: 100_000, tax: 10, production: 9, fort: 3, isCapital: true),
        .init(name: "Buda", owner: "HUN", lat: 47.50, lon: 19.04, terrain: .plains, population: 40_000, tax: 9, production: 7, fort: 3, isCapital: true),
        .init(name: "Vienna", owner: "HAB", lat: 48.21, lon: 16.37, terrain: .farmland, population: 40_000, tax: 8, production: 8, fort: 3, isCapital: true),
        .init(name: "Prague", owner: "BOH", lat: 50.08, lon: 14.44, terrain: .farmland, population: 50_000, tax: 8, production: 8, fort: 2, isCapital: true),
        .init(name: "Krakow", owner: "POL", lat: 50.06, lon: 19.94, terrain: .farmland, population: 30_000, tax: 8, production: 6, fort: 2, isCapital: true),
        .init(name: "Vilnius", owner: "LIT", lat: 54.69, lon: 25.28, terrain: .forest, population: 20_000, tax: 6, production: 4, fort: 2, isCapital: true),
        .init(name: "Moscow", owner: "MOS", lat: 55.76, lon: 37.62, terrain: .forest, population: 40_000, tax: 7, production: 5, fort: 2, isCapital: true),
        .init(name: "Kazan", owner: "KAZ", lat: 55.79, lon: 49.12, terrain: .forest, population: 20_000, tax: 4, production: 3, fort: 2, isCapital: true),
        .init(name: "Saray", owner: "GRH", lat: 46.62, lon: 47.83, terrain: .steppe, population: 15_000, tax: 3, production: 3, fort: 1, isCapital: true),
        .init(name: "Qirq Yer", owner: "CRI", lat: 44.74, lon: 33.92, terrain: .hills, population: 15_000, tax: 3, production: 3, fort: 2, isCapital: true),
        .init(name: "Paris", owner: "FRA", lat: 48.86, lon: 2.35, terrain: .farmland, population: 150_000, tax: 14, production: 12, fort: 3, isCapital: true),
        .init(name: "London", owner: "ENG", lat: 51.51, lon: -0.13, terrain: .farmland, population: 50_000, tax: 10, production: 10, fort: 2, isCapital: true),
        .init(name: "Edinburgh", owner: "SCO", lat: 55.95, lon: -3.19, terrain: .hills, population: 15_000, tax: 4, production: 3, fort: 2, isCapital: true),
        .init(name: "Dijon", owner: "BUR", lat: 47.32, lon: 5.04, terrain: .farmland, population: 20_000, tax: 7, production: 8, fort: 2, isCapital: true),
        .init(name: "Copenhagen", owner: "DAN", lat: 55.68, lon: 12.57, terrain: .farmland, population: 15_000, tax: 6, production: 6, fort: 2, isCapital: true),
        .init(name: "Toledo", owner: "CAS", lat: 39.86, lon: -4.03, terrain: .plains, population: 40_000, tax: 9, production: 7, fort: 2, isCapital: true),
        .init(name: "Zaragoza", owner: "ARA", lat: 41.65, lon: -0.89, terrain: .plains, population: 25_000, tax: 7, production: 6, fort: 2, isCapital: true),
        .init(name: "Lisbon", owner: "POR", lat: 38.72, lon: -9.14, terrain: .hills, population: 50_000, tax: 7, production: 8, fort: 2, isCapital: true),
        .init(name: "Granada", owner: "GRA", lat: 37.18, lon: -3.60, terrain: .mountains, population: 50_000, tax: 6, production: 6, fort: 3, isCapital: true),
        .init(name: "Fez", owner: "MOR", lat: 34.03, lon: -5.00, terrain: .hills, population: 100_000, tax: 8, production: 8, fort: 2, isCapital: true),
        .init(name: "Tlemcen", owner: "TLE", lat: 34.88, lon: -1.32, terrain: .hills, population: 40_000, tax: 5, production: 5, fort: 2, isCapital: true),
        .init(name: "Tunis", owner: "TUN", lat: 36.81, lon: 10.18, terrain: .plains, population: 60_000, tax: 7, production: 7, fort: 2, isCapital: true),
        .init(name: "Cairo", owner: "MAM", lat: 30.04, lon: 31.24, terrain: .farmland, population: 250_000, tax: 16, production: 14, fort: 3, isCapital: true),
        .init(name: "Mecca", owner: "HEJ", lat: 21.42, lon: 39.83, terrain: .desert, population: 20_000, tax: 3, production: 4, fort: 1, isCapital: true),
        .init(name: "Amid", owner: "AKK", lat: 37.91, lon: 40.24, terrain: .hills, population: 25_000, tax: 5, production: 4, fort: 2, isCapital: true),
        .init(name: "Tabriz", owner: "QAR", lat: 38.08, lon: 46.29, terrain: .hills, population: 60_000, tax: 8, production: 9, fort: 2, isCapital: true),
        .init(name: "Herat", owner: "TIM", lat: 34.35, lon: 62.20, terrain: .plains, population: 80_000, tax: 9, production: 10, fort: 3, isCapital: true),
        .init(name: "Debre Berhan", owner: "ETH", lat: 9.68, lon: 39.53, terrain: .mountains, population: 20_000, tax: 5, production: 4, fort: 1, isCapital: true),
        .init(name: "Dakkar", owner: "ADA", lat: 9.31, lon: 42.12, terrain: .hills, population: 15_000, tax: 3, production: 3, fort: 1, isCapital: true),
        .init(name: "Delhi", owner: "DEL", lat: 28.61, lon: 77.21, terrain: .farmland, population: 100_000, tax: 10, production: 9, fort: 3, isCapital: true),
        .init(name: "Jaunpur", owner: "JNP", lat: 25.75, lon: 82.69, terrain: .farmland, population: 60_000, tax: 8, production: 7, fort: 2, isCapital: true),
        .init(name: "Gaur", owner: "BNG", lat: 24.87, lon: 88.13, terrain: .farmland, population: 150_000, tax: 11, production: 12, fort: 2, isCapital: true),
        .init(name: "Ahmedabad", owner: "GUJ", lat: 23.02, lon: 72.57, terrain: .farmland, population: 100_000, tax: 10, production: 12, fort: 2, isCapital: true),
        .init(name: "Mandu", owner: "MLW", lat: 22.36, lon: 75.39, terrain: .hills, population: 40_000, tax: 7, production: 6, fort: 3, isCapital: true),
        .init(name: "Srinagar", owner: "KSH", lat: 34.08, lon: 74.80, terrain: .mountains, population: 40_000, tax: 5, production: 6, fort: 2, isCapital: true),
        .init(name: "Bidar", owner: "BAH", lat: 17.91, lon: 77.52, terrain: .hills, population: 60_000, tax: 10, production: 9, fort: 3, isCapital: true),
        .init(name: "Vijayanagara", owner: "VIJ", lat: 15.34, lon: 76.46, terrain: .hills, population: 200_000, tax: 12, production: 13, fort: 3, isCapital: true),
    ]
    // swiftlint:enable line_length

    public static func makeWorld() -> World {
        var world = World()
        for spec in countries {
            world.countries.add(
                tag: spec.tag,
                name: spec.name,
                color: spec.color,
                government: spec.government,
                religion: spec.religion,
                treasury: spec.treasury
            )
        }
        for spec in provinces {
            guard let owner = world.countries.id(forTag: spec.owner) else {
                preconditionFailure("province \(spec.name) has unknown owner \(spec.owner)")
            }
            let id = world.provinces.add(
                name: spec.name,
                location: GeoPoint(latitude: spec.lat, longitude: spec.lon),
                owner: owner,
                population: spec.population,
                baseTax: spec.tax,
                production: spec.production,
                terrain: spec.terrain,
                religion: world.countries.religion[owner.index],
                fortLevel: spec.fort
            )
            if spec.isCapital {
                world.countries.capital[owner.index] = id
            }
        }
        return world
    }
}
