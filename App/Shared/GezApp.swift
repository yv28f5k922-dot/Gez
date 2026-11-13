import SwiftUI

@main
struct GezApp: App {
    @State private var model = GameModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        #if os(macOS)
        .defaultSize(width: 1400, height: 860)
        #endif
    }
}
