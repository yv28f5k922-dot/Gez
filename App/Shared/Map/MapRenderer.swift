import CoreGraphics
import Foundation
import GezCore

/// Per-province facts about the ID map that the app needs often:
/// pixel bounding boxes (for the selection highlight) and pixel counts
/// (to decide which names fit on screen).
struct MapGeometry {
    var minX: [Int]
    var minY: [Int]
    var maxX: [Int]
    var maxY: [Int]
    var pixelCount: [Int]

    init(map: ProvinceIDMap, provinceCount n: Int) {
        var minX = [Int](repeating: Int.max, count: n)
        var minY = [Int](repeating: Int.max, count: n)
        var maxX = [Int](repeating: -1, count: n)
        var maxY = [Int](repeating: -1, count: n)
        var count = [Int](repeating: 0, count: n)
        let w = map.width
        map.values.withUnsafeBufferPointer { ids in
            for y in 0..<map.height {
                let row = y * w
                for x in 0..<w {
                    let v = Int(ids[row + x])
                    guard v >= 2 else { continue }
                    let p = v - 2
                    if x < minX[p] { minX[p] = x }
                    if x > maxX[p] { maxX[p] = x }
                    if y < minY[p] { minY[p] = y }
                    if y > maxY[p] { maxY[p] = y }
                    count[p] += 1
                }
            }
        }
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
        self.pixelCount = count
    }

    func bounds(of province: ProvinceID) -> CGRect? {
        let i = province.index
        guard maxX[i] >= 0 else { return nil }
        return CGRect(x: minX[i], y: minY[i], width: maxX[i] - minX[i] + 1, height: maxY[i] - minY[i] + 1)
    }
}

/// Builds the map image on the CPU from the ID map and a color per province.
///
/// Borders come in three strengths so the hierarchy is readable:
/// province border (light), state border (medium), country border and
/// coastline (dark, two pixels wide).
enum MapRenderer {
    struct Input {
        let map: ProvinceIDMap
        /// Color per ID-map value (see MapPalette).
        let colors: [UInt32]
        /// Owner per ID-map value: country index, -1 unowned, -2 water, -3 wasteland.
        let ownerKey: [Int32]
        /// State per ID-map value: state index, or negative for water/wasteland.
        let stateKey: [Int32]
        /// River lines in map pixels, drawn on top.
        var rivers: [[CGPoint]] = []
    }

    static func keys(world: World) -> (owner: [Int32], state: [Int32]) {
        let n = world.provinces.count
        var owner = [Int32](repeating: -1, count: n + 2)
        var state = [Int32](repeating: -1, count: n + 2)
        owner[0] = -2
        owner[1] = -3
        state[0] = -2
        state[1] = -3
        for i in 0..<n {
            owner[i + 2] = world.provinces.owner[i].map { Int32($0.index) } ?? -1
            state[i + 2] = Int32(world.provinces.state[i].index)
        }
        return (owner, state)
    }

    static func render(_ input: Input) -> CGImage? {
        let w = input.map.width
        let h = input.map.height
        var pixels = [UInt32](repeating: 0, count: w * h)

        input.map.values.withUnsafeBufferPointer { ids in
            input.colors.withUnsafeBufferPointer { colors in
                input.ownerKey.withUnsafeBufferPointer { owner in
                    input.stateKey.withUnsafeBufferPointer { state in
                        pixels.withUnsafeMutableBufferPointer { out in
                            for y in 0..<h {
                                let row = y * w
                                for x in 0..<w {
                                    let i = row + x
                                    let v = Int(ids[i])
                                    if v == 0 {
                                        out[i] = MapPalette.water
                                        continue
                                    }
                                    if v == 1 {
                                        out[i] = ((x + y) & 7) < 2 ? MapPalette.wastelandStripe : MapPalette.wasteland
                                        // Wasteland still gets a dark edge against provinces.
                                        if hasCountryEdge(i, x, y, v, w, h, ids, owner) { out[i] = MapPalette.border }
                                        continue
                                    }
                                    var level = 0
                                    if x + 1 < w { level = max(level, edge(v, Int(ids[i + 1]), owner, state)) }
                                    if y + 1 < h { level = max(level, edge(v, Int(ids[i + w]), owner, state)) }
                                    if level < 3 {
                                        // Country borders and coasts are drawn on both sides.
                                        if x > 0, edge(v, Int(ids[i - 1]), owner, state) == 3 { level = 3 }
                                        if y > 0, edge(v, Int(ids[i - w]), owner, state) == 3 { level = 3 }
                                    }
                                    let c = colors[v]
                                    switch level {
                                    case 0: out[i] = c
                                    case 1: out[i] = shade(c, 0.82)
                                    case 2: out[i] = shade(c, 0.55)
                                    default: out[i] = MapPalette.border
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if input.rivers.isEmpty {
            return makeImage(pixels: pixels, width: w, height: h)
        }
        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            // Map pixels count from the top; CoreGraphics counts from the bottom.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(red: 0.27, green: 0.43, blue: 0.58, alpha: 0.95)
            ctx.setLineWidth(1.8)
            for river in input.rivers where river.count >= 2 {
                ctx.beginPath()
                ctx.addLines(between: river)
                ctx.strokePath()
            }
            return ctx.makeImage()
        }
    }

    /// 0 none, 1 province, 2 state, 3 country or coast.
    @inline(__always)
    private static func edge(_ a: Int, _ b: Int, _ owner: UnsafeBufferPointer<Int32>, _ state: UnsafeBufferPointer<Int32>) -> Int {
        if a == b { return 0 }
        if b < 2 { return 3 }
        if owner[a] != owner[b] { return 3 }
        if state[a] != state[b] { return 2 }
        return 1
    }

    @inline(__always)
    private static func hasCountryEdge(
        _ i: Int, _ x: Int, _ y: Int, _ v: Int, _ w: Int, _ h: Int,
        _ ids: UnsafeBufferPointer<UInt16>, _ owner: UnsafeBufferPointer<Int32>
    ) -> Bool {
        if x + 1 < w, ids[i + 1] >= 2 { return true }
        if y + 1 < h, ids[i + w] >= 2 { return true }
        return false
    }

    @inline(__always)
    private static func shade(_ c: UInt32, _ f: Double) -> UInt32 {
        let r = UInt32(Double(c & 0xFF) * f)
        let g = UInt32(Double((c >> 8) & 0xFF) * f)
        let b = UInt32(Double((c >> 16) & 0xFF) * f)
        return r | g << 8 | b << 16 | 0xFF00_0000
    }

    /// White fill with a bright outline over one province, sized to its
    /// bounding box. Returned with the box (in map pixels) to place it.
    static func selectionOverlay(province: ProvinceID, map: ProvinceIDMap, geometry: MapGeometry) -> (CGImage, CGRect)? {
        guard let box = geometry.bounds(of: province) else { return nil }
        let bx = Int(box.minX), by = Int(box.minY)
        let bw = Int(box.width), bh = Int(box.height)
        let target = UInt16(province.index + 2)
        var pixels = [UInt32](repeating: 0, count: bw * bh)
        let fill: UInt32 = 0x55FF_FFFF  // white, about 33% (premultiplied below)
        let outline: UInt32 = 0xFFFF_FFFF
        for y in 0..<bh {
            for x in 0..<bw {
                let mx = bx + x, my = by + y
                guard map.value(x: mx, y: my) == target else { continue }
                let isEdge = map.value(x: mx - 1, y: my) != target || map.value(x: mx + 1, y: my) != target
                    || map.value(x: mx, y: my - 1) != target || map.value(x: mx, y: my + 1) != target
                pixels[y * bw + x] = isEdge ? outline : fill
            }
        }
        guard let image = makeImage(pixels: pixels, width: bw, height: bh, alpha: true) else { return nil }
        return (image, box)
    }

    static func makeImage(pixels: [UInt32], width: Int, height: Int, alpha: Bool = false) -> CGImage? {
        var data = pixels
        if alpha {
            // CoreGraphics wants premultiplied alpha.
            for i in 0..<data.count {
                let c = data[i]
                let a = (c >> 24) & 0xFF
                if a == 0xFF || a == 0 { continue }
                let f = Double(a) / 255
                data[i] = UInt32(Double(c & 0xFF) * f) | UInt32(Double((c >> 8) & 0xFF) * f) << 8
                    | UInt32(Double((c >> 16) & 0xFF) * f) << 16 | a << 24
            }
        }
        let bytes = data.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
