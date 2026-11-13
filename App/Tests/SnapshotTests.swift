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

    func testMapModes() async throws {
        let model = GameModel()
        var image = try await waitForMap(model)
        XCTAssertEqual(image.width, model.idMap.width)
        save(image, "map_political_full.png")
        if let europe = crop(image, model: model, lonMin: -10, latMax: 60, lonMax: 32, latMin: 35) {
            save(europe, "map_political_europe.png")
        }
        if let india = crop(image, model: model, lonMin: 60, latMax: 37, lonMax: 93, latMin: 5) {
            save(india, "map_political_india.png")
        }
        for mode in [MapMode.states, .terrain, .religion, .culture, .development] {
            let previous = image
            model.mapMode = mode
            image = try await waitForMap(model, previous: previous)
            if let europe = crop(image, model: model, lonMin: -10, latMax: 60, lonMax: 45, latMin: 28) {
                save(europe, "map_\(mode.rawValue).png")
            }
        }
    }

    func testMainScreen() async throws {
        let model = GameModel()
        _ = try await waitForMap(model)
        model.select(province: model.world.provinces.id(named: "Konstantiniyye"))
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
