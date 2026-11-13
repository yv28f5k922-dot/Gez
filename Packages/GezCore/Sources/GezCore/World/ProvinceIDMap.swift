import Foundation

/// Which province is at each pixel of the map image.
///
/// Stored value per pixel: 0 = water, 1 = wasteland, n >= 2 = province n - 2.
/// Loaded from the run-length encoded `.idmap` file written by
/// `tools/mapgen/mapgen.py`.
public struct ProvinceIDMap: Sendable {
    public static let water: UInt16 = 0
    public static let wasteland: UInt16 = 1
    public static let firstProvince: UInt16 = 2

    public enum LoadError: Error {
        case badHeader
        case badLength
        case missingResource
    }

    public let width: Int
    public let height: Int
    /// Row by row, left to right.
    public let values: [UInt16]

    public init(width: Int, height: Int, values: [UInt16]) {
        precondition(values.count == width * height)
        self.width = width
        self.height = height
        self.values = values
    }

    public init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 16, bytes[0] == 0x47, bytes[1] == 0x5A, bytes[2] == 0x49, bytes[3] == 0x44 else {
            throw LoadError.badHeader
        }
        func u32(_ o: Int) -> Int {
            Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24
        }
        let width = u32(4)
        let height = u32(8)
        let runCount = u32(12)
        guard bytes.count == 16 + runCount * 4 else { throw LoadError.badLength }

        var values = [UInt16](repeating: 0, count: width * height)
        var position = 0
        try values.withUnsafeMutableBufferPointer { out in
            var o = 16
            for _ in 0..<runCount {
                let value = UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8
                let length = Int(bytes[o + 2]) | Int(bytes[o + 3]) << 8
                o += 4
                guard position + length <= out.count else { throw LoadError.badLength }
                if length > 0 {
                    (out.baseAddress! + position).update(repeating: value, count: length)
                }
                position += length
            }
        }
        guard position == width * height else { throw LoadError.badLength }
        self.init(width: width, height: height, values: values)
    }

    /// The bundled 1453 map.
    public static func loadBundled() throws -> ProvinceIDMap {
        guard let url = Bundle.module.url(forResource: "provinces1453", withExtension: "idmap") else {
            throw LoadError.missingResource
        }
        return try ProvinceIDMap(data: Data(contentsOf: url))
    }

    public func value(x: Int, y: Int) -> UInt16 {
        guard x >= 0, y >= 0, x < width, y < height else { return ProvinceIDMap.water }
        return values[y * width + x]
    }

    public func province(x: Int, y: Int) -> ProvinceID? {
        let v = value(x: x, y: y)
        return v >= ProvinceIDMap.firstProvince ? ProvinceID(Int(v - ProvinceIDMap.firstProvince)) : nil
    }
}
