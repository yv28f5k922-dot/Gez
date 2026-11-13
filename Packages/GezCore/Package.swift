// swift-tools-version:5.9
import PackageDescription

// GezCore is the pure-Swift simulation: calendar, daily tick, economy,
// diplomacy, war, sieges and battle resolution. It must not import any
// Apple-only framework (SwiftUI, Metal, UIKit, AppKit) so it stays portable
// and testable on its own.
let package = Package(
    name: "GezCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "GezCore", targets: ["GezCore"])
    ],
    targets: [
        .target(name: "GezCore"),
        .testTarget(name: "GezCoreTests", dependencies: ["GezCore"])
    ]
)
