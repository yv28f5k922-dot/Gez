public struct CountryID: Hashable, Sendable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

public struct ProvinceID: Hashable, Sendable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

public struct RGB: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
}

public struct GeoPoint: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum Religion: String, CaseIterable, Sendable {
    case catholic, orthodox, miaphysite, sunni, shia, hindu
}

public enum GovernmentType: String, CaseIterable, Sendable {
    case monarchy, republic, theocracy, steppeHorde
}

public enum Terrain: String, CaseIterable, Sendable {
    case farmland, plains, hills, mountains, forest, marsh, desert, steppe
}
