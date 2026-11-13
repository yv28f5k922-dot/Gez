import GezCore
import SwiftUI

/// Draws a `CoatOfArms` at any size.
struct CoatOfArmsView: View {
    let arms: CoatOfArms

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let outline = Self.outline(arms.shape, in: rect)
            context.drawLayer { layer in
                layer.clip(to: outline)
                Self.drawField(arms, in: rect, context: &layer)
                Self.drawOrdinary(arms, in: rect, context: &layer)
                Self.drawCharges(arms, in: rect, context: &layer)
                // Soft shading for a painted look.
                layer.fill(outline, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.18)]),
                    startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            }
            context.stroke(outline, with: .color(Color(red: 0.15, green: 0.12, blue: 0.08)), lineWidth: max(1, size.width / 28))
        }
        .aspectRatio(arms.shape == .banner ? 0.8 : (arms.shape == .round ? 1 : 0.84), contentMode: .fit)
        .accessibilityHidden(true)
    }

    static func color(_ t: Tincture) -> Color {
        Color(red: Double(t.rgb.r) / 255, green: Double(t.rgb.g) / 255, blue: Double(t.rgb.b) / 255)
    }

    static func outline(_ shape: ShieldShape, in r: CGRect) -> Path {
        switch shape {
        case .round:
            return Path(ellipseIn: r)
        case .banner:
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.height * 0.14))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            return p
        case .heater:
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.42))
            p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.12))
            p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.42), control: CGPoint(x: r.minX, y: r.maxY - r.height * 0.12))
            p.closeSubpath()
            return p
        }
    }

    static func drawField(_ a: CoatOfArms, in r: CGRect, context: inout GraphicsContext) {
        context.fill(Path(r), with: .color(color(a.field)))
        let second = color(a.secondField)
        var p = Path()
        switch a.division {
        case .plain: return
        case .perPale: p.addRect(CGRect(x: r.midX, y: r.minY, width: r.width / 2, height: r.height))
        case .perFess: p.addRect(CGRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2))
        case .perBend:
            p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        case .quarterly:
            p.addRect(CGRect(x: r.midX, y: r.minY, width: r.width / 2, height: r.height / 2))
            p.addRect(CGRect(x: r.minX, y: r.midY, width: r.width / 2, height: r.height / 2))
        case .perChevron:
            p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.45))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.closeSubpath()
        }
        context.fill(p, with: .color(second))
    }

    static func drawOrdinary(_ a: CoatOfArms, in r: CGRect, context: inout GraphicsContext) {
        let w = r.width * 0.2
        let c = color(a.ordinaryTincture)
        var p = Path()
        switch a.ordinary {
        case .none: return
        case .cross:
            p.addRect(CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height))
            p.addRect(CGRect(x: r.minX, y: r.minY + r.height * 0.4 - w / 2, width: r.width, height: w))
        case .nordicCross:
            p.addRect(CGRect(x: r.minX + r.width * 0.32 - w / 2, y: r.minY, width: w, height: r.height))
            p.addRect(CGRect(x: r.minX, y: r.minY + r.height * 0.42 - w / 2, width: r.width, height: w))
        case .saltire:
            var s = Path()
            s.move(to: r.origin); s.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            s.move(to: CGPoint(x: r.maxX, y: r.minY)); s.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            context.stroke(s, with: .color(c), lineWidth: w)
            return
        case .fess: p.addRect(CGRect(x: r.minX, y: r.minY + r.height * 0.42 - w / 2, width: r.width, height: w))
        case .pale: p.addRect(CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height))
        case .bend:
            var s = Path()
            s.move(to: r.origin); s.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            context.stroke(s, with: .color(c), lineWidth: w)
            return
        case .chevron:
            var s = Path()
            s.move(to: CGPoint(x: r.minX, y: r.maxY - r.height * 0.1))
            s.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.38))
            s.addLine(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.1))
            context.stroke(s, with: .color(c), style: StrokeStyle(lineWidth: w, lineJoin: .miter))
            return
        case .chief: p.addRect(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.28))
        case .bordure:
            context.stroke(outline(a.shape, in: r), with: .color(c), lineWidth: w * 0.9)
            return
        }
        context.fill(p, with: .color(c))
    }

    /// Where charges go so they avoid the ordinary.
    static func positions(_ a: CoatOfArms, in r: CGRect) -> [CGPoint] {
        let midY = r.minY + r.height * 0.45
        switch (a.chargeCount, a.ordinary) {
        case (1, .chief): return [CGPoint(x: r.midX, y: r.minY + r.height * 0.58)]
        case (1, .fess), (1, .cross), (1, .nordicCross), (1, .saltire), (1, .bend):
            return [CGPoint(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.2)]
        case (1, _): return [CGPoint(x: r.midX, y: midY)]
        case (2, _): return [CGPoint(x: r.minX + r.width * 0.3, y: midY), CGPoint(x: r.maxX - r.width * 0.3, y: midY)]
        case (3, .chief), (3, .fess):
            return [CGPoint(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.14),
                    CGPoint(x: r.midX, y: r.minY + r.height * 0.14),
                    CGPoint(x: r.maxX - r.width * 0.25, y: r.minY + r.height * 0.14)]
        case (3, _):
            return [CGPoint(x: r.minX + r.width * 0.3, y: r.minY + r.height * 0.27),
                    CGPoint(x: r.maxX - r.width * 0.3, y: r.minY + r.height * 0.27),
                    CGPoint(x: r.midX, y: r.minY + r.height * 0.62)]
        default: return []
        }
    }

    static func drawCharges(_ a: CoatOfArms, in r: CGRect, context: inout GraphicsContext) {
        guard a.charge != .none else { return }
        let size = r.width * (a.chargeCount == 1 ? 0.42 : 0.24)
        for p in positions(a, in: r) {
            let box = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            let shape = chargePath(a.charge, in: box)
            // Even-odd fill only where the shape has holes (crescent, wheel, tower door).
            let eo = [Charge.crescent, .wheel, .tower].contains(a.charge)
            context.fill(shape, with: .color(color(a.chargeTincture)), style: FillStyle(eoFill: eo))
            context.stroke(shape, with: .color(.black.opacity(0.35)), lineWidth: max(0.5, size / 30))
        }
    }

    static func chargePath(_ charge: Charge, in b: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: b.midX, y: b.midY)
        let R = b.width / 2
        switch charge {
        case .none: break
        case .star:
            for i in 0..<10 {
                let a = -Double.pi / 2 + Double(i) * .pi / 5
                let rad = i % 2 == 0 ? R : R * 0.42
                let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rad, y: c.y + CGFloat(sin(a)) * rad)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        case .crescent:
            p.addEllipse(in: b)
            p.addEllipse(in: b.offsetBy(dx: R * 0.38, dy: -R * 0.12).insetBy(dx: R * 0.1, dy: R * 0.1))
        case .roundel:
            p.addEllipse(in: b.insetBy(dx: R * 0.1, dy: R * 0.1))
        case .lozenge:
            p.move(to: CGPoint(x: c.x, y: b.minY)); p.addLine(to: CGPoint(x: b.maxX - R * 0.25, y: c.y))
            p.addLine(to: CGPoint(x: c.x, y: b.maxY)); p.addLine(to: CGPoint(x: b.minX + R * 0.25, y: c.y))
            p.closeSubpath()
        case .tower:
            let w = R * 1.3, h = R * 1.6
            let x0 = c.x - w / 2, y0 = c.y - h / 2
            p.move(to: CGPoint(x: x0, y: y0 + h))
            p.addLine(to: CGPoint(x: x0, y: y0))
            for i in 0..<3 {
                let cx = x0 + w * CGFloat(i) / 2.5
                p.addLine(to: CGPoint(x: cx + w * 0.2, y: y0))
                p.addLine(to: CGPoint(x: cx + w * 0.2, y: y0 + h * 0.12))
                p.addLine(to: CGPoint(x: min(cx + w * 0.4, x0 + w), y: y0 + h * 0.12))
                p.addLine(to: CGPoint(x: min(cx + w * 0.4, x0 + w), y: y0))
            }
            p.addLine(to: CGPoint(x: x0 + w, y: y0 + h))
            p.closeSubpath()
            p.addRect(CGRect(x: c.x - w * 0.12, y: y0 + h * 0.62, width: w * 0.24, height: h * 0.38))
        case .crown:
            let w = R * 1.7, h = R * 1.2
            let x0 = c.x - w / 2, y0 = c.y - h / 2
            p.move(to: CGPoint(x: x0, y: y0 + h))
            p.addLine(to: CGPoint(x: x0, y: y0 + h * 0.2))
            p.addLine(to: CGPoint(x: x0 + w * 0.25, y: y0 + h * 0.55))
            p.addLine(to: CGPoint(x: x0 + w * 0.5, y: y0))
            p.addLine(to: CGPoint(x: x0 + w * 0.75, y: y0 + h * 0.55))
            p.addLine(to: CGPoint(x: x0 + w, y: y0 + h * 0.2))
            p.addLine(to: CGPoint(x: x0 + w, y: y0 + h))
            p.closeSubpath()
        case .sun:
            p.addEllipse(in: b.insetBy(dx: R * 0.45, dy: R * 0.45))
            for i in 0..<12 {
                let a = Double(i) * .pi / 6
                let inner = R * 0.6, outer = R
                let a1 = a - 0.12, a2 = a + 0.12
                p.move(to: CGPoint(x: c.x + CGFloat(cos(a1)) * inner, y: c.y + CGFloat(sin(a1)) * inner))
                p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * outer, y: c.y + CGFloat(sin(a)) * outer))
                p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a2)) * inner, y: c.y + CGFloat(sin(a2)) * inner))
                p.closeSubpath()
            }
        case .crossPattee:
            for i in 0..<4 {
                let a = Double(i) * .pi / 2
                let tip = R, root = R * 0.12, spread = 0.38
                p.move(to: CGPoint(x: c.x + CGFloat(cos(a + 0.7)) * root, y: c.y + CGFloat(sin(a + 0.7)) * root))
                p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a + spread)) * tip, y: c.y + CGFloat(sin(a + spread)) * tip))
                p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a - spread)) * tip, y: c.y + CGFloat(sin(a - spread)) * tip))
                p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a - 0.7)) * root, y: c.y + CGFloat(sin(a - 0.7)) * root))
                p.closeSubpath()
            }
            p.addEllipse(in: b.insetBy(dx: R * 0.82, dy: R * 0.82))
        case .wheel:
            p.addEllipse(in: b.insetBy(dx: R * 0.05, dy: R * 0.05))
            p.addEllipse(in: b.insetBy(dx: R * 0.22, dy: R * 0.22))
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                let s = CGRect(x: -R * 0.06, y: 0, width: R * 0.12, height: R * 0.8)
                p.addPath(Path(s).applying(CGAffineTransform(rotationAngle: CGFloat(a) - .pi / 2).concatenating(CGAffineTransform(translationX: c.x, y: c.y))))
            }
            p.addEllipse(in: b.insetBy(dx: R * 0.8, dy: R * 0.8))
        case .fleur:
            // Central petal, two side petals and a band.
            p.move(to: CGPoint(x: c.x, y: b.minY))
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + R * 0.2), control: CGPoint(x: c.x + R * 0.45, y: c.y - R * 0.35))
            p.addQuadCurve(to: CGPoint(x: c.x, y: b.minY), control: CGPoint(x: c.x - R * 0.45, y: c.y - R * 0.35))
            p.closeSubpath()
            for side in [-1.0, 1.0] {
                let s = CGFloat(side)
                p.move(to: CGPoint(x: c.x + s * R * 0.1, y: c.y + R * 0.1))
                p.addQuadCurve(to: CGPoint(x: c.x + s * R * 0.95, y: c.y - R * 0.25), control: CGPoint(x: c.x + s * R * 0.75, y: c.y + R * 0.35))
                p.addQuadCurve(to: CGPoint(x: c.x + s * R * 0.25, y: c.y + R * 0.35), control: CGPoint(x: c.x + s * R * 0.5, y: c.y - R * 0.45))
                p.closeSubpath()
            }
            p.addRect(CGRect(x: c.x - R * 0.45, y: c.y + R * 0.3, width: R * 0.9, height: R * 0.16))
            p.move(to: CGPoint(x: c.x - R * 0.12, y: c.y + R * 0.46))
            p.addLine(to: CGPoint(x: c.x + R * 0.12, y: c.y + R * 0.46))
            p.addLine(to: CGPoint(x: c.x, y: b.maxY))
            p.closeSubpath()
        }
        return p
    }
}

/// A country's real arms or banner (from Wikimedia Commons, bundled as
/// `arms_<TAG>.png`), falling back to the generated arms when none is chosen.
struct CountryArmsView: View {
    let world: World
    let country: CountryID

    var body: some View {
        if let image = Self.image(forTag: world.countries.tag[country.index]) {
            image
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                .accessibilityHidden(true)
        } else {
            CoatOfArmsView(arms: world.arms(of: country))
        }
    }

    @MainActor private static var cache: [String: Image?] = [:]

    @MainActor static func image(forTag tag: String) -> Image? {
        if let hit = cache[tag] { return hit }
        var result: Image?
        if let url = Bundle.main.url(forResource: "arms_\(tag)", withExtension: "png")
            ?? Bundle.main.url(forResource: "arms_\(tag)", withExtension: "png", subdirectory: "Heraldry") {
            #if canImport(UIKit)
            if let ui = UIImage(contentsOfFile: url.path) { result = Image(uiImage: ui) }
            #else
            if let ns = NSImage(contentsOf: url) { result = Image(nsImage: ns) }
            #endif
        }
        cache[tag] = result
        return result
    }
}
