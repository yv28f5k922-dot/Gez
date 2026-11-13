import GezCore
import SwiftUI

/// A country's real arms or banner (from Wikimedia Commons, bundled as
/// `arms_<TAG>.png`), falling back to a plain banner in the country's colour when no real one is known.
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
            PlainBannerView(color: world.countries.color[country.index])
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

/// A simple swallow-tailed banner in a country's map colour, used where no
/// real 1453 arms or banner is known.
struct PlainBannerView: View {
    let color: RGB

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var p = Path()
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.5))
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.closeSubpath()
            let c = Color(red: Double(color.r) / 255, green: Double(color.g) / 255, blue: Double(color.b) / 255)
            context.fill(p, with: .color(c))
            context.fill(p, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.15)]),
                startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            context.stroke(p, with: .color(.black.opacity(0.55)), lineWidth: max(1, w / 30))
        }
        .aspectRatio(1.4, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
