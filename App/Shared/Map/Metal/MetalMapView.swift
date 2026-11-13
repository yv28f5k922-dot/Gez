import MetalKit
import SwiftUI

/// Hosts the Metal map inside SwiftUI. Input (taps, drags, pinches) is
/// handled by the SwiftUI view on top; this view only draws.
struct MetalMapView {
    let renderer: MetalMapRenderer
    let camera: MapCamera

    final class Coordinator: NSObject, MTKViewDelegate {
        let renderer: MetalMapRenderer
        init(renderer: MetalMapRenderer) { self.renderer = renderer }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            if view.bounds.width > 0 {
                renderer.contentScale = view.drawableSize.width / view.bounds.width
            }
            renderer.draw(in: view)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(renderer: renderer) }

    private func makeMTKView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 30   // water animation; saves battery
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.delegate = context.coordinator
        return view
    }
}

#if os(macOS)
extension MetalMapView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView { makeMTKView(context: context) }
    func updateNSView(_ view: MTKView, context: Context) { renderer.camera = camera }
}
#else
extension MetalMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView { makeMTKView(context: context) }
    func updateUIView(_ view: MTKView, context: Context) { renderer.camera = camera }
}
#endif
