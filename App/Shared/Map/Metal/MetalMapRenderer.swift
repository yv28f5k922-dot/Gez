import CoreGraphics
import Foundation
import GezCore
import ImageIO
import Metal
import MetalKit
import simd

/// Camera for the map: where it is and how far zoomed, in view points.
struct MapCamera: Equatable {
    /// Screen points per map pixel.
    var zoom: CGFloat
    /// Map top-left corner in view points.
    var offset: CGPoint
}

/// Matches `ProvinceStyle` in MapShaders.metal.
struct ProvinceStyleGPU {
    var color: SIMD4<Float>
    var owner: Int32
    var state: Int32
    var pad0: Int32 = 0
    var pad1: Int32 = 0
}

/// Matches `MapUniforms` in MapShaders.metal.
struct MapUniformsGPU {
    var viewSize: SIMD2<Float>
    var offset: SIMD2<Float>
    var zoom: Float
    var time: Float
    var mapSize: SIMD2<Float>
    var selected: UInt32
    var tint: Float
    var mode: UInt32
    var pad: Float = 0
}

/// Draws the map with Metal: terrain texture, province colours, borders,
/// animated water. Owns the GPU resources; the view tells it what to draw.
final class MetalMapRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let idTexture: MTLTexture
    private let terrainTexture: MTLTexture
    private var styleBuffer: MTLBuffer
    private let mapSize: SIMD2<Float>
    private let startTime = Date()

    var camera = MapCamera(zoom: 1, offset: .zero)
    var selectedValue: UInt32 = 0
    var mode: MapMode = .political
    /// Points to pixels on screen (2 on Retina).
    var contentScale: CGFloat = 2

    static func makeDevice() -> MTLDevice? { MTLCreateSystemDefaultDevice() }

    init?(device: MTLDevice, idMap: ProvinceIDMap, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        mapSize = SIMD2(Float(idMap.width), Float(idMap.height))

        let library: MTLLibrary? = (try? device.makeDefaultLibrary(bundle: .main)) ?? device.makeDefaultLibrary()
        guard let library,
              let vertex = library.makeFunction(name: "map_vertex"),
              let fragment = library.makeFunction(name: "map_fragment") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = pixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        self.pipeline = pipeline

        // Province IDs as a 16-bit integer texture (read exactly, never blended).
        let idDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Uint, width: idMap.width, height: idMap.height, mipmapped: false)
        idDesc.usage = .shaderRead
        idDesc.storageMode = .shared
        guard let ids = device.makeTexture(descriptor: idDesc) else { return nil }
        idMap.values.withUnsafeBytes { raw in
            ids.replace(region: MTLRegionMake2D(0, 0, idMap.width, idMap.height), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: idMap.width * 2)
        }
        idTexture = ids

        guard let terrain = MetalMapRenderer.loadTerrain(device: device) else { return nil }
        terrainTexture = terrain

        guard let buffer = device.makeBuffer(length: MemoryLayout<ProvinceStyleGPU>.stride * 2, options: .storageModeShared)
        else { return nil }
        styleBuffer = buffer
    }

    /// The baked terrain picture (tools/terrain/bake_terrain.py).
    private static func loadTerrain(device: MTLDevice) -> MTLTexture? {
        guard let url = Bundle.main.url(forResource: "terrain", withExtension: "jpg") else { return nil }
        let loader = MTKTextureLoader(device: device)
        return try? loader.newTexture(URL: url, options: [
            .SRGB: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            .generateMipmaps: false,
        ])
    }

    /// Per-province colours and border keys for the current map mode.
    func updateStyles(world: World, mode: MapMode) {
        self.mode = mode
        let colors = MapPalette.colors(for: mode, world: world)
        let keys = MapRenderer.keys(world: world)
        var styles = [ProvinceStyleGPU]()
        styles.reserveCapacity(colors.count)
        for v in 0..<colors.count {
            let c = colors[v]
            var rgba = SIMD4<Float>(Float(c & 0xFF) / 255, Float((c >> 8) & 0xFF) / 255, Float((c >> 16) & 0xFF) / 255, 1)
            let owner = keys.owner[v]
            if v < 2 { rgba.w = 0 }                                   // water, wasteland: no tint
            if mode == .political && owner == -1 { rgba.w = 0 }      // unclaimed: show bare land
            if mode == .terrain { rgba.w = 0 }
            styles.append(ProvinceStyleGPU(color: rgba, owner: owner, state: keys.state[v]))
        }
        let length = MemoryLayout<ProvinceStyleGPU>.stride * styles.count
        if styleBuffer.length < length, let bigger = device.makeBuffer(length: length, options: .storageModeShared) {
            styleBuffer = bigger
        }
        styles.withUnsafeBytes { raw in
            styleBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: length)
        }
    }

    private func uniforms(drawableSize: CGSize) -> MapUniformsGPU {
        let s = Float(contentScale)
        let tint: Float
        switch mode {
        // Strong colours zoomed out (to read countries), lighter zoomed in
        // (to see the terrain).
        case .political: tint = Float(min(max(0.72 - 0.2 * camera.zoom, 0.38), 0.66))
        case .terrain: tint = 0
        default: tint = 0.8
        }
        let modeIndex: UInt32
        switch mode {
        case .political: modeIndex = 0
        case .states: modeIndex = 1
        case .terrain: modeIndex = 2
        case .religion: modeIndex = 3
        case .culture: modeIndex = 4
        case .development: modeIndex = 5
        }
        return MapUniformsGPU(
            viewSize: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            offset: SIMD2(Float(camera.offset.x) * s, Float(camera.offset.y) * s),
            zoom: Float(camera.zoom) * s,
            time: Float(Date().timeIntervalSince(startTime)),
            mapSize: mapSize,
            selected: selectedValue,
            tint: tint,
            mode: modeIndex
        )
    }

    func encode(into pass: MTLRenderPassDescriptor, drawableSize: CGSize, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var u = uniforms(drawableSize: drawableSize)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<MapUniformsGPU>.stride, index: 0)
        encoder.setFragmentBuffer(styleBuffer, offset: 0, index: 1)
        encoder.setFragmentTexture(idTexture, index: 0)
        encoder.setFragmentTexture(terrainTexture, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer() else { return }
        encode(into: pass, drawableSize: view.drawableSize, commandBuffer: cb)
        cb.present(drawable)
        cb.commit()
    }

    /// Renders one frame into an image (used by tests and screenshots).
    func renderImage(width: Int, height: Int) -> CGImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let target = device.makeTexture(descriptor: desc), let cb = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        encode(into: pass, drawableSize: CGSize(width: width, height: height), commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        // BGRA to RGBA.
        for i in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(i, i + 2) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
