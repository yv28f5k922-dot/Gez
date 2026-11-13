public struct CountryID: Hashable, Sendable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

public struct ProvinceID: Hashable, Sendable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

public struct StateID: Hashable, Sendable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

public struct RegionID: Hashable, Sendable {
    public let index: Int
    public init(_ index: Int) { self.index = index }
}

/// A pixel position on the province map image.
public struct MapPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// How the province map image relates to the globe.
public struct MapInfo: Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var pixelsPerDegree: Double
    public var longitudeMin: Double
    public var latitudeMax: Double

    public init(width: Int, height: Int, pixelsPerDegree: Double, longitudeMin: Double, latitudeMax: Double) {
        self.width = width
        self.height = height
        self.pixelsPerDegree = pixelsPerDegree
        self.longitudeMin = longitudeMin
        self.latitudeMax = latitudeMax
    }

    public func point(for geo: GeoPoint) -> MapPoint {
        MapPoint(
            x: Int((geo.longitude - longitudeMin) * pixelsPerDegree),
            y: Int((latitudeMax - geo.latitude) * pixelsPerDegree)
        )
    }
}

/// A line on the map image (rivers), in map pixels.
public struct MapPolyline: Sendable {
    public var name: String
    public var points: [SIMD2<Double>]
    public init(name: String, points: [SIMD2<Double>]) {
        self.name = name
        self.points = points
    }
}

/// An unordered pair of provinces.
public struct ProvincePair: Hashable, Sendable {
    public let low: Int
    public let high: Int
    public init(_ a: ProvinceID, _ b: ProvinceID) {
        low = min(a.index, b.index)
        high = max(a.index, b.index)
    }
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
    case catholic, orthodox, miaphysite, sunni, shia, hindu, buddhist
    /// Local folk and ancestral religions (Sami, Komi, Mordvins, Ahom, ...).
    case folk
}

public enum GovernmentType: String, CaseIterable, Sendable {
    case monarchy, republic, theocracy, steppeHorde
}

public enum Terrain: String, CaseIterable, Sendable {
    case farmland, plains, hills, mountains, forest, marsh, desert, steppe
}
