import GezCore
import SwiftUI

enum MapMode: String, CaseIterable, Identifiable {
    case political, states, terrain, religion, development

    var id: String { rawValue }

    var title: String {
        switch self {
        case .political: return "Political"
        case .states: return "States"
        case .terrain: return "Terrain"
        case .religion: return "Religion"
        case .development: return "Development"
        }
    }

    var systemImage: String {
        switch self {
        case .political: return "flag"
        case .states: return "square.grid.3x3"
        case .terrain: return "mountain.2"
        case .religion: return "building.columns"
        case .development: return "chart.bar"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .political: return "q"
        case .states: return "w"
        case .terrain: return "e"
        case .religion: return "r"
        case .development: return "t"
        }
    }
}

/// Colors as packed RGBA (red in the lowest byte), one entry per ID-map value:
/// index 0 = water, 1 = wasteland, n + 2 = province n.
enum MapPalette {
    static let water = pack(104, 140, 158)
    static let wasteland = pack(112, 100, 86)
    static let wastelandStripe = pack(96, 85, 72)
    static let unowned = pack(196, 182, 150)
    static let border = pack(32, 26, 20)

    static func pack(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt32 {
        UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | 0xFF00_0000
    }

    static func pack(_ rgb: RGB) -> UInt32 {
        pack(rgb.r, rgb.g, rgb.b)
    }

    static func colors(for mode: MapMode, world: World) -> [UInt32] {
        let p = world.provinces
        var out = [UInt32](repeating: unowned, count: p.count + 2)
        out[0] = water
        out[1] = wasteland
        for i in 0..<p.count {
            out[i + 2] = provinceColor(i, mode: mode, world: world)
        }
        return out
    }

    private static func provinceColor(_ i: Int, mode: MapMode, world: World) -> UInt32 {
        let p = world.provinces
        switch mode {
        case .political:
            guard let owner = p.owner[i] else { return unowned }
            return pack(world.countries.color[owner.index])
        case .states:
            let s = p.state[i].index
            let region = world.states.region[s].index
            // Neighbouring states get clearly different hues; regions shift
            // the base hue so the same state index differs between regions.
            let hue = (Double(s) * 0.618_034 + Double(region) * 0.137).truncatingRemainder(dividingBy: 1)
            let light = 0.62 + 0.12 * Double(s % 3) / 2
            return hsl(hue, 0.45, light)
        case .terrain:
            switch p.terrain[i] {
            case .farmland: return pack(150, 180, 90)
            case .plains: return pack(190, 200, 120)
            case .hills: return pack(170, 150, 100)
            case .mountains: return pack(130, 115, 100)
            case .forest: return pack(70, 120, 70)
            case .marsh: return pack(110, 140, 120)
            case .desert: return pack(225, 200, 140)
            case .steppe: return pack(205, 190, 120)
            }
        case .religion:
            switch p.religion[i] {
            case .catholic: return pack(235, 220, 120)
            case .orthodox: return pack(160, 110, 200)
            case .miaphysite: return pack(200, 140, 210)
            case .sunni: return pack(70, 160, 80)
            case .shia: return pack(40, 110, 70)
            case .hindu: return pack(240, 150, 60)
            case .buddhist: return pack(220, 110, 90)
            }
        case .development:
            let t = Double(min(max(p.development[i], 1), 10) - 1) / 9
            return pack(
                UInt8(240 - 60 * t),
                UInt8(230 - 170 * t),
                UInt8(170 - 130 * t)
            )
        }
    }

    private static func hsl(_ h: Double, _ s: Double, _ l: Double) -> UInt32 {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var r = 0.0, g = 0.0, b = 0.0
        switch Int(hp) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        let m = l - c / 2
        return pack(UInt8((r + m) * 255), UInt8((g + m) * 255), UInt8((b + m) * 255))
    }
}
