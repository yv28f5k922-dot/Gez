import GezCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The zoomable, pannable province map.
///
/// - iPad: pinch to zoom, drag to pan, tap to select.
/// - Mac: trackpad pinch or mouse wheel to zoom, two-finger scroll or drag
///   to pan, click to select.
struct MapCanvasView: View {
    @Environment(GameModel.self) private var model

    /// Screen points per map pixel.
    @State private var zoom: CGFloat = 0
    /// Where the map's top-left corner sits in the view.
    @State private var offset: CGPoint = .zero
    @State private var viewSize: CGSize = .zero
    @State private var dragStart: CGPoint?
    @State private var pinchStart: (zoom: CGFloat, offset: CGPoint)?
    #if os(macOS)
    @State private var scrollMonitor: Any?
    @State private var globalFrame: CGRect = .zero
    #endif

    private var mapWidth: CGFloat { CGFloat(model.idMap.width) }
    private var mapHeight: CGFloat { CGFloat(model.idMap.height) }

    var body: some View {
        GeometryReader { geo in
            // Before the first layout pass (and in snapshot renders, where
            // onAppear never runs) use the starting view directly.
            let z = zoom > 0 ? zoom : startZoom(for: geo.size)
            let o = zoom > 0 ? offset : startOffset(for: geo.size)
            ZStack(alignment: .topLeading) {
                MapPalette.waterColor
                    .frame(width: geo.size.width, height: geo.size.height)

                if let snapshot = model.snapshotMapImage {
                    Image(decorative: snapshot, scale: 1)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if let metal = model.metal, z > 0 {
                    MetalMapView(renderer: metal, camera: MapCamera(zoom: z, offset: o))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                } else if let image = model.mapImage, z > 0 {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(z >= 2 ? .none : .medium)
                        .frame(width: mapWidth * z, height: mapHeight * z)
                        .offset(x: o.x, y: o.y)
                }

                if model.metal == nil, let overlay = model.selectionOverlay, z > 0 {
                    Image(decorative: overlay.image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: overlay.box.width * z, height: overlay.box.height * z)
                        .offset(x: o.x + overlay.box.minX * z, y: o.y + overlay.box.minY * z)
                }

                if z > 0 {
                    MapLabelsLayer(zoom: z, offset: o, viewSize: geo.size)
                }

                if model.metal == nil && model.mapImage == nil {
                    ProgressView("Drawing map…")
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            // The map image is far bigger than the view; pin its top-left
            // corner to the view's so offsets and taps line up.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(tapGesture)
            .simultaneousGesture(dragGesture)
            .simultaneousGesture(pinchGesture)
            .onAppear {
                viewSize = geo.size
                fitIfNeeded()
                #if os(macOS)
                globalFrame = geo.frame(in: .global)
                installScrollMonitor()
                #endif
            }
            .onChange(of: geo.size) { _, newSize in
                viewSize = newSize
                fitIfNeeded()
                offset = clamped(offset, zoom: zoom)
                #if os(macOS)
                globalFrame = geo.frame(in: .global)
                #endif
            }
            #if os(macOS)
            .onDisappear { removeScrollMonitor() }
            #endif
            .overlay(alignment: .bottomTrailing) { zoomButtons.padding(12) }
        }
    }

    // MARK: - Zoom limits

    private var fitZoom: CGFloat {
        guard viewSize.width > 0, viewSize.height > 0 else { return 0.3 }
        return min(viewSize.width / mapWidth, viewSize.height / mapHeight)
    }

    private var minZoom: CGFloat { fitZoom * 0.9 }
    private let maxZoom: CGFloat = 8

    private func fitIfNeeded() {
        guard zoom == 0, viewSize.width > 0 else { return }
        resetView()
    }

    private func resetView() {
        zoom = startZoom(for: viewSize)
        offset = startOffset(for: viewSize)
    }

    private func startZoom(for size: CGSize) -> CGFloat {
        Self.startCamera(size: size, map: model.world.map).zoom
    }

    private func startOffset(for size: CGSize) -> CGPoint {
        Self.startCamera(size: size, map: model.world.map).offset
    }

    /// The opening view: zoomed in on the Ottoman heartland, three times the
    /// whole-map fit. Also used by snapshot tests.
    static func startCamera(size: CGSize, map: MapInfo) -> MapCamera {
        guard size.width > 0, size.height > 0 else { return MapCamera(zoom: 0, offset: .zero) }
        let w = CGFloat(map.width), h = CGFloat(map.height)
        let fit = min(size.width / w, size.height / h)
        let zoom = min(fit * 3, 8)
        let focus = map.point(for: GeoPoint(latitude: 41.0, longitude: 29.0))
        var x = size.width / 2 - CGFloat(focus.x) * zoom
        var y = size.height / 2 - CGFloat(focus.y) * zoom
        let margin: CGFloat = 80
        x = min(max(x, size.width - w * zoom - margin), margin)
        y = min(max(y, size.height - h * zoom - margin), margin)
        return MapCamera(zoom: zoom, offset: CGPoint(x: x, y: y))
    }

    private func showWholeMap() {
        zoom = fitZoom
        offset = clamped(.zero, zoom: zoom)
    }

    /// Keeps the map on screen; centres it when it is smaller than the view.
    private func clamped(_ o: CGPoint, zoom z: CGFloat) -> CGPoint {
        clamped(o, zoom: z, in: viewSize)
    }

    private func clamped(_ o: CGPoint, zoom z: CGFloat, in viewSize: CGSize) -> CGPoint {
        let w = mapWidth * z, h = mapHeight * z
        let margin: CGFloat = 80
        var x = o.x, y = o.y
        if w <= viewSize.width {
            x = (viewSize.width - w) / 2
        } else {
            x = min(max(x, viewSize.width - w - margin), margin)
        }
        if h <= viewSize.height {
            y = (viewSize.height - h) / 2
        } else {
            y = min(max(y, viewSize.height - h - margin), margin)
        }
        return CGPoint(x: x, y: y)
    }

    private func zoomBy(_ factor: CGFloat, around anchor: CGPoint) {
        let newZoom = min(max(zoom * factor, minZoom), maxZoom)
        let ratio = newZoom / zoom
        let o = CGPoint(x: anchor.x - (anchor.x - offset.x) * ratio, y: anchor.y - (anchor.y - offset.y) * ratio)
        zoom = newZoom
        offset = clamped(o, zoom: newZoom)
    }

    // MARK: - Gestures

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let x = Int((value.location.x - offset.x) / zoom)
                let y = Int((value.location.y - offset.y) / zoom)
                model.select(mapX: x, y: y)
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard pinchStart == nil else { return }
                if dragStart == nil { dragStart = offset }
                guard let start = dragStart else { return }
                offset = clamped(
                    CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height),
                    zoom: zoom
                )
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStart == nil { pinchStart = (zoom, offset) }
                guard let start = pinchStart else { return }
                let newZoom = min(max(start.zoom * value.magnification, minZoom), maxZoom)
                let ratio = newZoom / start.zoom
                let anchor = value.startLocation
                zoom = newZoom
                offset = clamped(
                    CGPoint(x: anchor.x - (anchor.x - start.offset.x) * ratio, y: anchor.y - (anchor.y - start.offset.y) * ratio),
                    zoom: newZoom
                )
            }
            .onEnded { _ in
                pinchStart = nil
                dragStart = nil
            }
    }

    private var zoomButtons: some View {
        VStack(spacing: 6) {
            mapButton("plus.magnifyingglass") {
                zoomBy(1.5, around: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
            }
            mapButton("minus.magnifyingglass") {
                zoomBy(1 / 1.5, around: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
            }
            mapButton("globe.europe.africa") { showWholeMap() }
        }
    }

    private func mapButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(Palette.parchment.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Palette.ink)
                .shadow(radius: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mac scroll wheel

    #if os(macOS)
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handleScroll(event)
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor { NSEvent.removeMonitor(monitor) }
        scrollMonitor = nil
    }

    /// Returns nil when the event was used, so it doesn't also scroll something else.
    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window, let content = window.contentView else { return event }
        let inWindow = event.locationInWindow
        let point = CGPoint(x: inWindow.x, y: content.bounds.height - inWindow.y)
        guard globalFrame.contains(point) else { return event }
        let local = CGPoint(x: point.x - globalFrame.minX, y: point.y - globalFrame.minY)

        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            // Trackpad two-finger scroll: pan.
            offset = clamped(CGPoint(x: offset.x + event.scrollingDeltaX, y: offset.y + event.scrollingDeltaY), zoom: zoom)
        } else {
            // Mouse wheel, or Command + scroll: zoom around the pointer.
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
            zoomBy(exp(delta), around: local)
        }
        return nil
    }
    #endif
}

/// Country names when zoomed out, province names when zoomed in.
private struct MapLabelsLayer: View {
    @Environment(GameModel.self) private var model
    let zoom: CGFloat
    let offset: CGPoint
    let viewSize: CGSize

    var body: some View {
        let showProvinces = zoom >= 1.1
        let labels = showProvinces ? model.provinceLabels : model.countryLabels
        let mode = model.mapMode
        Canvas { context, size in
            context.addFilter(.shadow(color: .white.opacity(0.85), radius: 1.2))
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -60, dy: -20)
            var placed: [CGRect] = []
            for label in labels {
                let screenArea = label.pixelArea * Double(zoom * zoom)
                let p = CGPoint(x: offset.x + label.position.x * zoom, y: offset.y + label.position.y * zoom)
                guard bounds.contains(p) else { continue }
                let fontSize: CGFloat
                let text: Text
                let width: CGFloat
                if showProvinces {
                    guard screenArea > 2_200 else { continue }
                    fontSize = min(max(sqrt(screenArea) / 9, 9), 14)
                    text = Text(label.text).font(.system(size: fontSize, weight: .medium, design: .serif))
                        .foregroundColor(Palette.ink.opacity(0.85))
                    width = CGFloat(label.text.count) * fontSize * 0.55
                } else {
                    guard mode == .political, screenArea > 1_800 else { continue }
                    fontSize = min(max(sqrt(screenArea) / 7, 9), 26)
                    text = Text(label.text.uppercased()).font(.system(size: fontSize, weight: .semibold, design: .serif))
                        .kerning(fontSize * 0.12)
                        .foregroundColor(Palette.ink.opacity(0.8))
                    width = CGFloat(label.text.count) * fontSize * 0.78
                }
                // Skip names that would sit on top of a bigger one.
                let rect = CGRect(x: p.x - width / 2, y: p.y - fontSize * 0.7, width: width, height: fontSize * 1.4)
                if placed.contains(where: { $0.intersects(rect) }) { continue }
                placed.append(rect)
                context.draw(text, at: p)
            }
        }
        .allowsHitTesting(false)
    }
}

extension MapPalette {
    static let waterColor = Color(red: 104 / 255, green: 140 / 255, blue: 158 / 255)
}
