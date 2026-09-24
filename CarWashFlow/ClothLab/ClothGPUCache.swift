import Foundation
import Metal

final class ClothGPU {

    let device: MTLDevice
    let queue: MTLCommandQueue
    let backgroundPipeline: MTLRenderPipelineState
    let surfacePipeline: MTLRenderPipelineState
    let pointsPipeline: MTLRenderPipelineState
    let compositePipeline: MTLRenderPipelineState
    let clothDepth: MTLDepthStencilState
    let backdropDepth: MTLDepthStencilState
    let repeatSampler: MTLSamplerState
    let clampSampler: MTLSamplerState
    let blankTexture: MTLTexture

    static let sceneFormat = MTLPixelFormat.bgra8Unorm
    static let depthFormat = MTLPixelFormat.depth32Float
    static let drawableFormat = MTLPixelFormat.bgra8Unorm

    private static var cache: [ObjectIdentifier: ClothGPU] = [:]
    private static let lock = NSLock()

    static func shared(for device: MTLDevice) -> ClothGPU? {
        let key = ObjectIdentifier(device as AnyObject)
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        guard let made = ClothGPU(device: device) else { return nil }
        cache[key] = made
        return made
    }

    static func warmUp() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        DispatchQueue.global(qos: .userInitiated).async { _ = shared(for: device) }
    }

    private init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: ClothShaders.source, options: nil)
        else { return nil }

        func pipeline(_ vertex: String, _ fragment: String,
                      color: MTLPixelFormat, depth: MTLPixelFormat,
                      blend: Bool) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = color
            d.depthAttachmentPixelFormat = depth
            if blend, let a = d.colorAttachments[0] {
                a.isBlendingEnabled = true
                a.rgbBlendOperation = .add
                a.alphaBlendOperation = .add
                a.sourceRGBBlendFactor = .sourceAlpha
                a.destinationRGBBlendFactor = .oneMinusSourceAlpha
                a.sourceAlphaBlendFactor = .one
                a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try? device.makeRenderPipelineState(descriptor: d)
        }

        guard let bg = pipeline("cloth_fullscreen_vertex", "cloth_background_fragment",
                                color: Self.sceneFormat, depth: Self.depthFormat, blend: false),
              let surface = pipeline("cloth_surface_vertex", "cloth_surface_fragment",
                                     color: Self.sceneFormat, depth: Self.depthFormat, blend: true),
              let points = pipeline("cloth_points_vertex", "cloth_points_fragment",
                                    color: Self.sceneFormat, depth: Self.depthFormat, blend: true),
              let composite = pipeline("cloth_fullscreen_vertex", "cloth_composite_fragment",
                                       color: Self.drawableFormat, depth: .invalid, blend: false)
        else { return nil }

        let clothDesc = MTLDepthStencilDescriptor()
        clothDesc.depthCompareFunction = .less
        clothDesc.isDepthWriteEnabled = true

        let backdropDesc = MTLDepthStencilDescriptor()
        backdropDesc.depthCompareFunction = .always
        backdropDesc.isDepthWriteEnabled = false

        func sampler(_ mode: MTLSamplerAddressMode) -> MTLSamplerState? {
            let d = MTLSamplerDescriptor()
            d.minFilter = .linear
            d.magFilter = .linear
            d.mipFilter = .linear
            d.sAddressMode = mode
            d.tAddressMode = mode
            d.maxAnisotropy = 8
            return device.makeSamplerState(descriptor: d)
        }

        let blankDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                 width: 1, height: 1,
                                                                 mipmapped: false)
        blankDesc.usage = [.shaderRead]

        guard let cd = device.makeDepthStencilState(descriptor: clothDesc),
              let bd = device.makeDepthStencilState(descriptor: backdropDesc),
              let rs = sampler(.repeat), let cs = sampler(.clampToEdge),
              let blank = device.makeTexture(descriptor: blankDesc)
        else { return nil }

        var white: UInt32 = 0xFFFF_FFFF
        blank.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                      withBytes: &white, bytesPerRow: 4)

        self.device = device
        self.queue = queue
        self.backgroundPipeline = bg
        self.surfacePipeline = surface
        self.pointsPipeline = points
        self.compositePipeline = composite
        self.clothDepth = cd
        self.backdropDepth = bd
        self.repeatSampler = rs
        self.clampSampler = cs
        self.blankTexture = blank
    }
}
