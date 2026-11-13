import GezCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Gez

/// Renders the real map and the main screen to PNG files so the look can be
/// checked without a person at the Mac. CI uploads them as an artifact.
/// Output folder: $GEZ_SNAPSHOT_DIR, or a temporary folder.
@MainActor
final class SnapshotTests: XCTestCase {
    private var outputDir: URL {
        let path = ProcessInfo.processInfo.environment["GEZ_SNAPSHOT_DIR"] ?? NSTemporaryDirectory() + "gez-snapshots"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForMap(_ model: GameModel, previous: CGImage? = nil) async throws -> CGImage {
        for _ in 0..<300 {
            if let image = model.mapImage, image !== previous { return image }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("map image never appeared")
        throw CancellationError()
    }

    private func save(_ image: CGImage, _ name: String) {
        let url = outputDir.appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            XCTFail("cannot write \(url.path)")
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("snapshot: \(url.path)")
    }

    private func crop(_ image: CGImage, model: GameModel, lonMin: Double, latMax: Double, lonMax: Double, latMin: Double) -> CGImage? {
        let a = model.world.map.point(for: GeoPoint(latitude: latMax, longitude: lonMin))
        let b = model.world.map.point(for: GeoPoint(latitude: latMin, longitude: lonMax))
        return image.cropping(to: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
    }

    /// The CPU fallback map (used when Metal is missing).
    func testMapModes() async throws {
        let model = GameModel(useMetal: false)
        var image = try await waitForMap(model)
        XCTAssertEqual(image.width, model.idMap.width)
        save(image, "map_political_full.png")
        if let europe = crop(image, model: model, lonMin: -10, latMax: 60, lonMax: 32, latMin: 35) {
            save(europe, "map_political_europe.png")
        }
        if let india = crop(image, model: model, lonMin: 60, latMax: 37, lonMax: 93, latMin: 5) {
            save(india, "map_political_india.png")
        }
        for mode in [MapMode.states, .terrain, .religion, .culture, .development, .goods, .markets] {
            let previous = image
            model.mapMode = mode
            image = try await waitForMap(model, previous: previous)
            if let europe = crop(image, model: model, lonMin: -10, latMax: 60, lonMax: 45, latMin: 28) {
                save(europe, "map_\(mode.rawValue).png")
            }
        }
    }

    /// The real Metal map at several places and modes.
    func testMetalMap() throws {
        let model = GameModel()
        guard let metal = model.metal else { throw XCTSkip("Metal not available on this machine") }
        metal.contentScale = 1
        let size = CGSize(width: 1400, height: 812)
        metal.camera = MapCanvasView.startCamera(size: size, map: model.world.map)
        model.select(province: model.world.provinces.id(named: "Konstantiniyye"))
        let start = try XCTUnwrap(metal.renderImage(width: 1400, height: 812))
        save(start, "metal_start.png")

        // Whole map.
        let w = CGFloat(model.idMap.width), h = CGFloat(model.idMap.height)
        let fit = min(1400 / w, 812 / h)
        metal.camera = MapCamera(zoom: fit, offset: CGPoint(x: (1400 - w * fit) / 2, y: (812 - h * fit) / 2))
        save(try XCTUnwrap(metal.renderImage(width: 1400, height: 812)), "metal_world.png")

        // Indian Ocean and India with a sea zone selected.
        let india = model.world.map.point(for: GeoPoint(latitude: 18.0, longitude: 78.0))
        let iz: CGFloat = 0.9
        metal.camera = MapCamera(zoom: iz, offset: CGPoint(x: 700 - CGFloat(india.x) * iz, y: 406 - CGFloat(india.y) * iz))
        model.select(sea: model.world.seaZones.id(named: "Malabar Coast"))
        save(try XCTUnwrap(metal.renderImage(width: 1400, height: 812)), "metal_india.png")
        model.select(sea: nil)

        // Close-up of western Europe, then religion and culture modes.
        let paris = model.world.map.point(for: GeoPoint(latitude: 47.0, longitude: 6.0))
        let zoom: CGFloat = 1.6
        metal.camera = MapCamera(zoom: zoom, offset: CGPoint(x: 700 - CGFloat(paris.x) * zoom, y: 406 - CGFloat(paris.y) * zoom))
        save(try XCTUnwrap(metal.renderImage(width: 1400, height: 812)), "metal_europe.png")
        for mode in [MapMode.religion, .culture, .terrain, .goods, .markets] {
            metal.updateStyles(world: model.world, mode: mode)
            save(try XCTUnwrap(metal.renderImage(width: 1400, height: 812)), "metal_\(mode.rawValue).png")
        }
    }

    /// A sheet of generated coats of arms.
    func testHeraldrySheet() throws {
        let model = GameModel(useMetal: false)
        let world = model.world
        let ids = (0..<world.countries.count).map { CountryID($0) }
        let view = LazyVGrid(columns: Array(repeating: GridItem(.fixed(96)), count: 14), spacing: 8) {
            ForEach(ids, id: \.index) { id in
                VStack(spacing: 3) {
                    CountryArmsView(world: world, country: id).frame(height: 56)
                    Text(world.countries.tag[id.index]).font(.caption2.bold())
                    Text(world.countries.name[id.index]).font(.system(size: 9)).lineLimit(1)
                }
                .frame(width: 92)
            }
        }
        .padding(12)
        .frame(width: 1400)
        .background(Palette.parchment)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        save(try XCTUnwrap(renderer.cgImage), "heraldry.png")
    }

    func testMarketPanel() throws {
        let model = GameModel(useMetal: false)
        let world = model.world
        for name in ["Venice", "Calicut"] {
            let m = world.economy.markets.id(named: name)!
            let view = MarketPanel(market: m, scrolls: false)
                .environment(model)
                .frame(width: 380)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            save(try XCTUnwrap(renderer.cgImage), "market_\(name.lowercased()).png")
        }
    }

    func testMainScreen() async throws {
        let model = GameModel()
        if let metal = model.metal {
            metal.contentScale = 1
            metal.camera = MapCanvasView.startCamera(size: CGSize(width: 1400, height: 812), map: model.world.map)
            model.select(province: model.world.provinces.id(named: "Konstantiniyye"))
            model.snapshotMapImage = metal.renderImage(width: 1400, height: 812)
        } else {
            _ = try await waitForMap(model)
        }
        model.select(province: model.world.provinces.id(named: "Konstantiniyye"))
        model.openMarket = model.world.market(of: model.world.provinces.id(named: "Konstantiniyye")!)
        let view = ContentView()
            .environment(model)
            .frame(width: 1400, height: 860)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            XCTFail("could not render the main screen")
            return
        }
        save(image, "screen_main.png")
    }
}
