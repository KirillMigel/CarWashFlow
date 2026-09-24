import Foundation
import Metal
import MetalKit
import QuartzCore
import SwiftUI
import simd

final class ClothRenderer: NSObject, MTKViewDelegate {

    private let gpu: ClothGPU
    var device: MTLDevice { gpu.device }

    private var sceneTexture: MTLTexture?
    private var depthTexture: MTLTexture?
    private var drawableSize = CGSize(width: 1, height: 1)
    private var contentScale: Float = 2

    private static let inFlight = 3
    private let frameSemaphore = DispatchSemaphore(value: inFlight)
    private var positionBuffers: [MTLBuffer] = []
    private var normalBuffers: [MTLBuffer] = []
    private var uvBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount = 0
    private var vertexCount = 0
    private var frameIndex = 0

    private let simQueue = DispatchQueue(label: "clothlab.simulation", qos: .userInitiated)
    private let simGate = DispatchSemaphore(value: 1)
    private static let stepSeconds: Double = 1.0 / 120.0
    private static let batchBudget: Double = 0.012
    private static let settleBudget: Double = 0.012
    private static let maxStepsPerBatch = 16

    private var sim: ClothSimulation?
    private var simLast = CACurrentMediaTime()
    private var simAccumulator: Double = 0
    private var simSpeed: Double = 1
    private var dragPlaneZ: Float = 0
    private var dissolve: DissolveState?

    private let snapshotLock = NSLock()
    private var snapPositions: [Float] = []
    private var snapNormals: [Float] = []
    private var snapTime: Float = 0
    private var snapValid = false

    private(set) var effect: ClothEffect
    private var fill = ClothTextures.Fill()
    private var weaveTexture: MTLTexture?
    private var isDragging = false
    private let textureQueue = DispatchQueue(label: "clothlab.textures", qos: .userInitiated)
    private var textureToken = 0

    init?(device: MTLDevice, effect: ClothEffect) {
        guard let gpu = ClothGPU.shared(for: device) else { return nil }
        self.gpu = gpu
        self.effect = effect
        super.init()
        install(ClothSimulation(physics: effect.physics), behavior: effect.behavior)
        setSpeed(effect.speed)
        rebuildTextures()
    }

    func update(effect new: ClothEffect) {
        let old = effect
        effect = new
        if new.speed != old.speed { setSpeed(new.speed) }

        let physicsChanged = new.physics != old.physics
        if physicsChanged || new.behavior != old.behavior {
            install(ClothSimulation(physics: new.physics), behavior: new.behavior)
        }
        if physicsChanged
            || new.material.weave != old.material.weave
            || new.material.whenWearingAnImage.fit != old.material.whenWearingAnImage.fit
            || new.fill != old.fill {
            rebuildTextures()
        }
    }

    private func install(_ newSim: ClothSimulation, behavior: ClothBehavior) {
        let state = attachBehaviour(behavior, to: newSim)
        rebuildGeometry(for: newSim)

        snapshotLock.lock()
        let n3 = newSim.count * 3
        snapPositions = [Float](repeating: 0, count: n3)
        snapNormals = [Float](repeating: 0, count: n3)
        snapValid = false
        snapTime = 0
        snapshotLock.unlock()

        publish(newSim)

        simQueue.async { [weak self] in
            guard let self else { return }
            self.sim = newSim
            self.dissolve = state
            self.simLast = CACurrentMediaTime()
            self.simAccumulator = 0
            self.dragPlaneZ = 0
        }
    }

    private func setSpeed(_ speed: Float) {
        let value = Double(max(0, speed))
        simQueue.async { [weak self] in self?.simSpeed = value }
    }

    private func rebuildGeometry(for s: ClothSimulation) {
        let n3 = s.count * 3
        vertexCount = s.count
        indexCount = s.indices.count
        positionBuffers = (0..<Self.inFlight).compactMap { _ in
            device.makeBuffer(length: n3 * MemoryLayout<Float>.stride, options: .storageModeShared)
        }
        normalBuffers = (0..<Self.inFlight).compactMap { _ in
            device.makeBuffer(length: n3 * MemoryLayout<Float>.stride, options: .storageModeShared)
        }
        uvBuffer = device.makeBuffer(bytes: s.uv,
                                     length: s.count * 2 * MemoryLayout<Float>.stride,
                                     options: .storageModeShared)
        indexBuffer = s.indices.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        }
    }

    private func rebuildTextures() {
        let aspect = effect.physics.width / max(effect.physics.height, 1e-4)
        let request = effect.fill.resolved()
        let fit = effect.material.whenWearingAnImage.fit
        let weave = effect.material.weave
        let device = self.device

        textureToken += 1
        let token = textureToken

        weaveTexture = weave.flatMap { ClothTextures.weave($0, device: device) }

        if let ready = ClothTextures.readyFill(request, fit: fit, sheetAspect: aspect,
                                               device: device) {
            fill = ready
            return
        }

        textureQueue.async { [weak self] in
            let baked = ClothTextures.fill(request, fit: fit, sheetAspect: aspect, device: device)
            DispatchQueue.main.async {
                guard let self, self.textureToken == token else { return }
                self.fill = baked
            }
        }
    }

    private final class DissolveState { var burst: Float = -99 }

    private func attachBehaviour(_ behavior: ClothBehavior, to s: ClothSimulation) -> DissolveState? {
        switch behavior {
        case .none:
            s.onStep = nil
            return nil
        case .dissolve(let cfg):
            let state = DissolveState()
            var seeds = [Float](repeating: 0, count: s.count * 2)
            for k in 0..<s.count {
                let a = sin(Double(k) * 12.9898) * 43758.5453
                let b = sin(Double(k) * 78.233) * 12345.6789
                seeds[2 * k] = Float(a - a.rounded(.down) - 0.5)
                seeds[2 * k + 1] = Float(b - b.rounded(.down) - 0.5)
            }
            s.onStep = { sim, t in
                let cyc = t.truncatingRemainder(dividingBy: cfg.cycle)
                var scatter: Float = 0
                if cyc > cfg.scatterStart && cyc < cfg.scatterEnd {
                    scatter = min(1, (cyc - cfg.scatterStart) / cfg.rampIn)
                           * min(1, (cfg.scatterEnd - cyc) / cfg.rampOut)
                }
                let age = t - state.burst
                if age >= 0 && age < cfg.burst { scatter = max(scatter, 1 - age / cfg.burst) }
                guard scatter > 0 else { return }
                let f = scatter * cfg.strength
                for k in 0..<sim.count {
                    let k3 = 3 * k
                    let s0 = seeds[2 * k], s1 = seeds[2 * k + 1]
                    sim.prev[k3] -= (s0 * 2.2 + sim.flat[k3] * 0.35) * f
                    sim.prev[k3 + 1] -= (s1 * 2.2 + sim.flat[k3 + 1] * 0.35) * f
                    sim.prev[k3 + 2] -= (s0 + s1) * f * 2.4
                }
            }
            return state
        }
    }

    private func pumpSimulation() {
        guard simGate.wait(timeout: .now()) == .success else { return }
        let gate = simGate
        simQueue.async { [weak self] in
            self?.advanceSimulation()
            gate.signal()
        }
    }

    private func advanceSimulation() {
        guard let sim else { return }
        let now = CACurrentMediaTime()
        let elapsed = min(now - simLast, 0.05)
        simLast = now
        if sim.needsSettle {
            let settleDeadline = now + Self.settleBudget
            var stepped = false
            repeat {
                sim.settleSlice(maxSteps: 8)
                stepped = true
            } while sim.needsSettle && CACurrentMediaTime() < settleDeadline
            simAccumulator = 0
            if stepped {
                sim.refreshNormals()
                publish(sim)
            }
            return
        }

        let deadline = now + Self.batchBudget
        simAccumulator += elapsed * simSpeed
        let maxBacklog = Double(Self.maxStepsPerBatch) * Self.stepSeconds
        if simAccumulator > maxBacklog { simAccumulator = maxBacklog }

        var stepped = 0
        while simAccumulator >= Self.stepSeconds {
            sim.advanceRaw(steps: 1)
            simAccumulator -= Self.stepSeconds
            stepped += 1
            if CACurrentMediaTime() >= deadline { break }
        }
        guard stepped > 0 else { return }
        sim.refreshNormals()
        publish(sim)
    }

    private func publish(_ s: ClothSimulation) {
        let n3 = s.count * 3
        snapshotLock.lock()
        if snapPositions.count == n3 {
            _ = snapPositions.withUnsafeMutableBytes { memcpy($0.baseAddress!, s.pos, n3 * 4) }
            _ = snapNormals.withUnsafeMutableBytes { memcpy($0.baseAddress!, s.normal, n3 * 4) }
            snapTime = s.time
            snapValid = true
        }
        snapshotLock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        sceneTexture = nil
        depthTexture = nil
    }

    private func ensureTargets() -> Bool {
        let w = Int(drawableSize.width), h = Int(drawableSize.height)
        guard w > 0, h > 0 else { return false }
        if let t = sceneTexture, t.width == w, t.height == h, depthTexture != nil { return true }
        let color = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ClothGPU.sceneFormat,
                                                             width: w, height: h, mipmapped: false)
        color.usage = [.renderTarget, .shaderRead]
        color.storageMode = .private
        let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ClothGPU.depthFormat,
                                                             width: w, height: h, mipmapped: false)
        depth.usage = [.renderTarget]
        depth.storageMode = .private
        sceneTexture = device.makeTexture(descriptor: color)
        depthTexture = device.makeTexture(descriptor: depth)
        return sceneTexture != nil && depthTexture != nil
    }

    func draw(in view: MTKView) {
        if view.bounds.width > 0 {
            contentScale = max(1, Float(view.drawableSize.width / view.bounds.width))
        }
        if view.drawableSize.width > 0, view.drawableSize.height > 0,
           view.drawableSize != drawableSize {
            drawableSize = view.drawableSize
            sceneTexture = nil
            depthTexture = nil
        }
        guard ensureTargets(),
              let scene = sceneTexture, let depth = depthTexture,
              let drawable = view.currentDrawable,
              positionBuffers.count == Self.inFlight
        else { return }

        pumpSimulation()

        frameSemaphore.wait()
        frameIndex = (frameIndex + 1) % Self.inFlight
        let posBuf = positionBuffers[frameIndex]
        let nrmBuf = normalBuffers[frameIndex]

        snapshotLock.lock()
        let haveCloth = snapValid && snapPositions.count == vertexCount * 3
        let time = snapTime
        if haveCloth {
            let bytes = vertexCount * 3 * MemoryLayout<Float>.stride
            _ = snapPositions.withUnsafeBytes { memcpy(posBuf.contents(), $0.baseAddress!, bytes) }
            _ = snapNormals.withUnsafeBytes { memcpy(nrmBuf.contents(), $0.baseAddress!, bytes) }
        }
        snapshotLock.unlock()

        var uniforms = makeUniforms(time: time)

        guard let cb = gpu.queue.makeCommandBuffer() else { frameSemaphore.signal(); return }
        cb.addCompletedHandler { [sem = frameSemaphore] _ in sem.signal() }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = scene
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .dontCare

        if let enc = cb.makeRenderCommandEncoder(descriptor: pass) {
            if effect.scene.background != .clear {
                enc.setRenderPipelineState(gpu.backgroundPipeline)
                enc.setDepthStencilState(gpu.backdropDepth)
                enc.setFragmentBytes(&uniforms, length: MemoryLayout<ClothUniforms>.stride, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }

            if haveCloth, let uvBuffer {
                enc.setDepthStencilState(gpu.clothDepth)
                enc.setCullMode(.none)
                enc.setFrontFacing(.counterClockwise)
                enc.setVertexBytes(&uniforms, length: MemoryLayout<ClothUniforms>.stride, index: 0)
                enc.setVertexBuffer(posBuf, offset: 0, index: 1)
                enc.setVertexBuffer(nrmBuf, offset: 0, index: 2)
                enc.setVertexBuffer(uvBuffer, offset: 0, index: 3)
                enc.setFragmentBytes(&uniforms, length: MemoryLayout<ClothUniforms>.stride, index: 0)
                enc.setFragmentTexture(fill.texture ?? gpu.blankTexture, index: 0)
                enc.setFragmentSamplerState(fill.repeats ? gpu.repeatSampler : gpu.clampSampler,
                                            index: 0)

                if effect.points != nil {
                    enc.setRenderPipelineState(gpu.pointsPipeline)
                    enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertexCount)
                } else if let indexBuffer {
                    enc.setRenderPipelineState(gpu.surfacePipeline)
                    enc.setFragmentTexture(weaveTexture ?? gpu.blankTexture, index: 1)
                    enc.setFragmentSamplerState(gpu.repeatSampler, index: 1)
                    enc.drawIndexedPrimitives(type: .triangle,
                                              indexCount: indexCount,
                                              indexType: .uint32,
                                              indexBuffer: indexBuffer,
                                              indexBufferOffset: 0)
                }
            }
            enc.endEncoding()
        }

        if let rpd = view.currentRenderPassDescriptor {
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            rpd.depthAttachment.texture = nil
            rpd.stencilAttachment.texture = nil
            if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
                enc.setRenderPipelineState(gpu.compositePipeline)
                enc.setFragmentBytes(&uniforms, length: MemoryLayout<ClothUniforms>.stride, index: 0)
                enc.setFragmentTexture(scene, index: 0)
                enc.setFragmentSamplerState(gpu.clampSampler, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
        }

        cb.present(drawable)
        cb.commit()
    }

    private var aspect: Float {
        Float(drawableSize.width / max(drawableSize.height, 1))
    }

    private var modelMatrix: simd_float4x4 {
        ClothMath.eulerXYZ(effect.scene.rotation, scale: max(effect.scene.scale, 0.001))
    }

    private func makeUniforms(time: Float) -> ClothUniforms {
        let s = effect.scene
        let m = effect.material
        let wearing = effect.fill.isPicture
        let look = m.whenWearingAnImage

        var u = ClothUniforms()
        u.model = modelMatrix
        u.viewProj = ClothMath.perspective(fovDegrees: s.fov, aspect: aspect, near: 0.1, far: 50)
            * ClothMath.translation(SIMD3(0, 0, -s.cameraDistance))

        let exposure = wearing ? (look.exposure ?? s.exposure) : s.exposure
        u.camera = SIMD4(0, 0, s.cameraDistance, exposure)

        let roughness = wearing ? (look.roughness ?? m.roughness) : m.roughness
        let metalness = wearing ? (look.metalness ?? m.metalness) : m.metalness
        let sheen = wearing ? (look.sheen ?? m.sheen) : m.sheen
        let envIntensity = wearing ? (look.envIntensity ?? m.envIntensity) : m.envIntensity
        let bumpScale = wearing ? (look.bumpScale ?? m.bumpScale) : m.bumpScale

        u.base = SIMD4(fill.baseColor.x, fill.baseColor.y, fill.baseColor.z, roughness)
        let sheenLinear = m.sheenColor.clothLinear * sheen
        u.sheenC = SIMD4(sheenLinear.x, sheenLinear.y, sheenLinear.z, sheen)
        let tint = look.tint.clothLinear
        u.tint = SIMD4(tint.x, tint.y, tint.z, look.emissive)

        let pointStyle = effect.points ?? ClothPointsStyle()
        let pointColor: SIMD3<Float> = fill.texture == nil
            ? fill.baseColor
            : (pointStyle.takesColourFromFill ? SIMD3<Float>(repeating: 1)
                                              : ClothPalette.grey.clothLinear)
        u.pointC = SIMD4(pointColor.x, pointColor.y, pointColor.z, pointStyle.opacity)

        u.m0 = SIMD4(metalness, m.sheenRoughness, envIntensity, bumpScale)
        u.m1 = SIMD4(m.iridescence, m.iridescenceIOR,
                     m.iridescenceThickness.x, m.iridescenceThickness.y)
        u.m2 = SIMD4(weaveTexture != nil ? 1 : 0,
                     fill.texture != nil ? 1 : 0,
                     wearing ? 1 : 0,
                     s.lights ? 1 : 0)
        let tile = m.weave?.tile ?? SIMD2(1, 1)
        u.tiles = SIMD4(tile.x, tile.y, fill.tile.x, fill.tile.y)
        u.env = SIMD4(s.environment ? 1 : 0, s.environmentBlur, time,
                      pointStyle.size * max(s.scale, 0.001))

        let fixedPointPx: Float = pointStyle.sizeAttenuation
            ? 0
            : max(1, pointStyle.size * max(s.scale, 0.001) * 0.5
                     * Float(drawableSize.height) / max(s.cameraDistance, 0.01))
        u.view = SIMD4(Float(drawableSize.width), Float(drawableSize.height),
                       pointStyle.round ? 1 : 0,
                       pointStyle.takesColourFromFill ? 1 : 0)
        let grain = s.grain
        u.grain = SIMD4(grain?.overlay ?? 0, grain?.screen ?? 0,
                        max(1, (grain?.scale ?? 1) * contentScale), fixedPointPx)

        switch s.background {
        case .clear:
            u.bgM = SIMD4(0, aspect, 0, 0)
        case .color(let c):
            u.bg0 = c.clothSRGB
            u.bgM = SIMD4(1, aspect, 0, 0)
        case .radial(let inner, let mid, let outer, let center, let extent):
            u.bg0 = inner.clothSRGB
            u.bg1 = mid.clothSRGB
            u.bg2 = outer.clothSRGB
            u.bgP = SIMD4(Float(center.x), Float(center.y), extent.x, extent.y)
            u.bgM = SIMD4(2, aspect, 0, 0)
        }
        return u
    }

    private struct Camera {
        var fov: Float
        var distance: Float
        var aspect: Float
        var model: simd_float3x3
        var inverse: simd_float3x3

        func ray(_ n: SIMD2<Float>) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
            let tanHalf = tan(fov * .pi / 180 / 2)
            let dir = simd_normalize(SIMD3(n.x * tanHalf * aspect, n.y * tanHalf, -1))
            return (SIMD3(0, 0, distance), dir)
        }

        func project(_ local: SIMD3<Float>) -> SIMD2<Float> {
            let tanHalf = tan(fov * .pi / 180 / 2)
            let world = model * local
            let viewZ = world.z - distance
            guard viewZ < -1e-4 else { return SIMD2(1e9, 1e9) }
            return SIMD2(world.x / (-viewZ * tanHalf * aspect), world.y / (-viewZ * tanHalf))
        }
    }

    private var camera: Camera {
        let scale = max(effect.scene.scale, 0.001)
        let rotation = ClothMath.upperLeft(ClothMath.eulerXYZ(effect.scene.rotation, scale: 1))
        return Camera(fov: effect.scene.fov,
                      distance: effect.scene.cameraDistance,
                      aspect: aspect,
                      model: rotation * scale,
                      inverse: simd_transpose(rotation) * (1 / scale))
    }

    private func ndc(_ p: CGPoint, in size: CGSize) -> SIMD2<Float> {
        SIMD2(Float(p.x / max(size.width, 1)) * 2 - 1,
              1 - Float(p.y / max(size.height, 1)) * 2)
    }

    func pointerDown(at point: CGPoint, in size: CGSize) {
        isDragging = true
        let n = ndc(point, in: size)
        let cam = camera
        let bursts: Bool = { if case .dissolve = effect.behavior { return true }; return false }()

        simQueue.async { [weak self] in
            guard let self, let sim = self.sim else { return }
            if bursts { self.dissolve?.burst = sim.time }

            let r = cam.ray(n)
            let localOrigin = cam.inverse * r.origin
            let localDir = simd_normalize(cam.inverse * r.direction)

            let hitLocal: SIMD3<Float>
            if let h = sim.raycastLocal(origin: localOrigin, direction: localDir) {
                hitLocal = h
            } else {
                hitLocal = sim.nearestVertex(toNDC: n) { cam.project($0) }
            }

            self.dragPlaneZ = (cam.model * hitLocal).z
            let lift = simd_normalize(cam.inverse * SIMD3(0, 0, cam.distance))
            sim.beginGrab(atLocal: hitLocal, liftDirection: lift)
        }
    }

    func pointerMoved(to point: CGPoint, in size: CGSize) {
        guard isDragging else { return }
        let n = ndc(point, in: size)
        let cam = camera
        simQueue.async { [weak self] in
            guard let self, let sim = self.sim else { return }
            let r = cam.ray(n)
            guard abs(r.direction.z) > 1e-6 else { return }
            let t = (self.dragPlaneZ - r.origin.z) / r.direction.z
            guard t > 0 else { return }
            let world = r.origin + r.direction * t
            sim.moveGrab(toLocal: cam.inverse * world)
        }
    }

    func pointerUp() {
        isDragging = false
        simQueue.async { [weak self] in self?.sim?.endGrab() }
    }

    func resetCloth() {
        simQueue.async { [weak self] in
            guard let self, let sim = self.sim else { return }
            sim.reset()
            self.publish(sim)
        }
    }
}

struct ClothUniforms {
    var model = matrix_identity_float4x4
    var viewProj = matrix_identity_float4x4
    var camera = SIMD4<Float>(repeating: 0)
    var base = SIMD4<Float>(repeating: 0)
    var sheenC = SIMD4<Float>(repeating: 0)
    var tint = SIMD4<Float>(repeating: 0)
    var pointC = SIMD4<Float>(repeating: 0)
    var m0 = SIMD4<Float>(repeating: 0)
    var m1 = SIMD4<Float>(repeating: 0)
    var m2 = SIMD4<Float>(repeating: 0)
    var tiles = SIMD4<Float>(1, 1, 1, 1)
    var env = SIMD4<Float>(repeating: 0)
    var view = SIMD4<Float>(repeating: 0)
    var grain = SIMD4<Float>(repeating: 0)
    var bg0 = SIMD4<Float>(repeating: 0)
    var bg1 = SIMD4<Float>(repeating: 0)
    var bg2 = SIMD4<Float>(repeating: 0)
    var bgP = SIMD4<Float>(repeating: 0)
    var bgM = SIMD4<Float>(repeating: 0)
}

enum ClothMath {

    static func eulerXYZ(_ e: SIMD3<Float>, scale: Float = 1) -> simd_float4x4 {
        let sx = sin(e.x), cx = cos(e.x)
        let sy = sin(e.y), cy = cos(e.y)
        let sz = sin(e.z), cz = cos(e.z)
        let r = simd_float3x3(rows: [
            SIMD3(cy * cz, -cy * sz, sy),
            SIMD3(sx * sy * cz + cx * sz, -sx * sy * sz + cx * cz, -sx * cy),
            SIMD3(-cx * sy * cz + sx * sz, cx * sy * sz + sx * cz, cx * cy)
        ])
        let c0 = r.columns.0 * scale, c1 = r.columns.1 * scale, c2 = r.columns.2 * scale
        return simd_float4x4(SIMD4<Float>(c0.x, c0.y, c0.z, 0),
                             SIMD4<Float>(c1.x, c1.y, c1.z, 0),
                             SIMD4<Float>(c2.x, c2.y, c2.z, 0),
                             SIMD4<Float>(0, 0, 0, 1))
    }

    static func upperLeft(_ m: simd_float4x4) -> simd_float3x3 {
        simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                      SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                      SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
    }

    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t.x, t.y, t.z, 1)
        return m
    }

    static func perspective(fovDegrees: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let f = 1 / tan(fovDegrees * .pi / 180 / 2)
        let a = max(aspect, 1e-4)
        return simd_float4x4(SIMD4(f / a, 0, 0, 0),
                             SIMD4(0, f, 0, 0),
                             SIMD4(0, 0, far / (near - far), -1),
                             SIMD4(0, 0, far * near / (near - far), 0))
    }
}
