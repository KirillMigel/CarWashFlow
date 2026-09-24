import Foundation
import Metal
import CoreGraphics
import ImageIO
import SwiftUI
import simd

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ClothTextures {

    static func weave(_ w: ClothWeave, device: MTLDevice) -> MTLTexture? {
        let size = max(4, w.size)
        let step = max(1, w.step)
        let thread = max(1, w.thread)
        var buf = [Float](repeating: Float(w.base), count: size * size)
        let warp = Float(w.warp), weft = Float(w.weft)

        var y = 0
        while y < size {
            let c = (y / step) % 2 == 1 ? warp : weft
            for row in y..<min(y + thread, size) {
                for x in 0..<size { buf[row * size + x] = c }
            }
            y += step
        }

        var x = 0
        while x < size {
            let c = (x / step) % 2 == 1 ? warp : weft
            for col in x..<min(x + thread, size) {
                for row in 0..<size {
                    let i = row * size + col
                    buf[i] = buf[i] * 0.5 + c * 0.5
                }
            }
            x += step
        }

        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(size &* 7919 &+ w.speck &* 104_729)))
        for _ in 0..<max(0, w.speck) {
            let v: Float = rng.next() > 0.5 ? 0.6 : 0.4
            let px = min(size - 1, Int(rng.next() * Float(size)))
            let py = min(size - 1, Int(rng.next() * Float(size)))
            let i = py * size + px
            buf[i] = buf[i] * 0.75 + v * 0.25
        }

        var bytes = [UInt8](repeating: 0, count: size * size)
        for i in 0..<buf.count { bytes[i] = UInt8(max(0, min(255, buf[i] * 255)).rounded()) }

        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,
                                                         width: size, height: size,
                                                         mipmapped: true)
        d.usage = [.shaderRead]
        #if os(macOS)
        d.storageMode = .managed
        #endif
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        upload(bytes, to: tex, width: size, height: size, componentsPerPixel: 1)
        return tex
    }

    struct Fill {
        var texture: MTLTexture?
        var tile: SIMD2<Float> = SIMD2(1, 1)
        var repeats = false
        var baseColor: SIMD3<Float> = SIMD3(repeating: 0.5)
        var isPicture = false
    }

    private static var cache: [String: MTLTexture] = [:]
    private static let cacheLock = NSLock()

    private static func cacheKey(_ fill: ResolvedClothFill, fit: ClothImageFit,
                                 width: Int, height: Int) -> String? {
        func fitKey() -> String {
            switch fit {
            case .cover: return "cover"
            case .contain: return "contain"
            case .stretch: return "stretch"
            case .tile(let t): return "tile\(t.x)x\(t.y)"
            }
        }
        switch fill.kind {
        case .color:
            return nil
        case .gradient(let colors, let angle):
            let stops = colors.map { "\($0.x),\($0.y),\($0.z),\($0.w)" }.joined(separator: ";")
            return "g|\(stops)|\(angle)|\(width)x\(height)"
        case .image(let source):
            let src: String
            switch source {
            case .asset(let n): src = "a:\(n)"
            case .url(let u): src = "u:\(u.absoluteString)"
            case .data(let d): src = "d:\(d.count):\(d.hashValue)"
            case .cgImage(let c): src = "c:\(ObjectIdentifier(c).hashValue)"
            }
            return "i|\(src)|\(fitKey())|\(width)x\(height)"
        }
    }

    private static func lookup(_ key: String?) -> MTLTexture? {
        guard let key else { return nil }
        cacheLock.lock(); defer { cacheLock.unlock() }
        return cache[key]
    }

    private static func store(_ texture: MTLTexture?, for key: String?) {
        guard let key, let texture else { return }
        cacheLock.lock()
        if cache.count > 12 { cache.removeAll() }
        cache[key] = texture
        cacheLock.unlock()
    }

    static func readyFill(_ fill: ResolvedClothFill, fit: ClothImageFit, sheetAspect: Float,
                          device: MTLDevice) -> Fill? {
        if case .color(let linear) = fill.kind {
            return Fill(texture: nil, baseColor: linear, isPicture: false)
        }
        if case .image(let source) = fill.kind, case .tile(let t) = fit {
            _ = source
            _ = t
            return nil
        }
        let (w, h) = canvasSize(aspect: sheetAspect)
        guard let hit = lookup(cacheKey(fill, fit: fit, width: w, height: h)) else { return nil }
        let isPicture: Bool = { if case .image = fill.kind { return true }; return false }()
        return Fill(texture: hit, baseColor: SIMD3(repeating: 1), isPicture: isPicture)
    }

    static func prewarm(_ fill: ResolvedClothFill, fits: [(ClothImageFit, Float)],
                        device: MTLDevice) {
        DispatchQueue.global(qos: .utility).async {
            for (fit, aspect) in fits {
                _ = self.fill(fill, fit: fit, sheetAspect: aspect, device: device)
            }
        }
    }

    static func fill(_ fill: ResolvedClothFill, fit: ClothImageFit, sheetAspect: Float,
                     device: MTLDevice) -> Fill {
        switch fill.kind {
        case .color(let linear):
            return Fill(texture: nil, baseColor: linear, isPicture: false)

        case .gradient(let colors, let angle):
            guard colors.count >= 2 else {
                return Fill(texture: nil, baseColor: fill.fallback)
            }
            let (w, h) = canvasSize(aspect: sheetAspect)
            let key = cacheKey(fill, fit: fit, width: w, height: h)
            if let hit = lookup(key) {
                return Fill(texture: hit, baseColor: SIMD3(repeating: 1), isPicture: false)
            }
            let tex = bake(width: w, height: h, device: device) { ctx in
                let space = CGColorSpaceCreateDeviceRGB()
                let comps = colors.flatMap { s -> [CGFloat] in
                    [CGFloat(s.x), CGFloat(s.y), CGFloat(s.z), CGFloat(s.w)]
                }
                let locs = (0..<colors.count).map { CGFloat($0) / CGFloat(colors.count - 1) }
                guard let g = CGGradient(colorSpace: space, colorComponents: comps,
                                         locations: locs, count: colors.count) else { return }
                let r = CGFloat(angle)
                let cx = CGFloat(w) / 2, cy = CGFloat(h) / 2
                let ext = (CGFloat(w) * abs(sin(r)) + CGFloat(h) * abs(cos(r))) / 2
                let dx = sin(r) * ext, dy = cos(r) * ext
                ctx.drawLinearGradient(g,
                                       start: CGPoint(x: cx - dx, y: cy + dy),
                                       end: CGPoint(x: cx + dx, y: cy - dy),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            store(tex, for: key)
            return Fill(texture: tex, baseColor: SIMD3(repeating: 1), isPicture: false)

        case .image(let source):
            let (w, h) = canvasSize(aspect: sheetAspect)
            let key = cacheKey(fill, fit: fit, width: w, height: h)
            if let hit = lookup(key) {
                return Fill(texture: hit, baseColor: SIMD3(repeating: 1), isPicture: true)
            }
            guard let cg = decode(source, targetPixels: max(w, h)) else {
                return Fill(texture: nil, baseColor: fill.fallback)
            }
            if case .tile(let t) = fit {
                let tex = bake(width: cg.width, height: cg.height, device: device) { ctx in
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                }
                return Fill(texture: tex, tile: t, repeats: true,
                            baseColor: SIMD3(repeating: 1), isPicture: true)
            }
            let tex = bake(width: w, height: h, device: device) { ctx in
                let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
                let ia = iw / ih, ca = CGFloat(w) / CGFloat(h)
                var r = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
                switch fit {
                case .cover:
                    if ia > ca { r.size.width = CGFloat(h) * ia; r.origin.x = (CGFloat(w) - r.width) / 2 }
                    else { r.size.height = CGFloat(w) / ia; r.origin.y = (CGFloat(h) - r.height) / 2 }
                case .contain:
                    if ia > ca { r.size.height = CGFloat(w) / ia; r.origin.y = (CGFloat(h) - r.height) / 2 }
                    else { r.size.width = CGFloat(h) * ia; r.origin.x = (CGFloat(w) - r.width) / 2 }
                default: break
                }
                ctx.draw(cg, in: r)
            }
            store(tex, for: key)
            return Fill(texture: tex, baseColor: SIMD3(repeating: 1), isPicture: true)
        }
    }

    private static func canvasSize(aspect: Float) -> (Int, Int) {
        let long = 1280
        return aspect >= 1
            ? (long, max(8, Int((Float(long) / aspect).rounded())))
            : (max(8, Int((Float(long) * aspect).rounded())), long)
    }

    private static func bake(width: Int, height: Int, device: MTLDevice,
                             _ draw: (CGContext) -> Void) -> MTLTexture? {
        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ok: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: rowBytes,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .medium
            draw(ctx)
            return true
        }
        guard ok else { return nil }

        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb,
                                                         width: width, height: height,
                                                         mipmapped: true)
        d.usage = [.shaderRead]
        #if os(macOS)
        d.storageMode = .managed
        #endif
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        upload(bytes, to: tex, width: width, height: height, componentsPerPixel: 4)
        return tex
    }

    private static func upload(_ level0: [UInt8], to texture: MTLTexture,
                               width: Int, height: Int, componentsPerPixel bpp: Int) {
        var src = level0
        var w = width, h = height, level = 0
        while level < texture.mipmapLevelCount {
            src.withUnsafeBytes { raw in
                texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: level,
                                withBytes: raw.baseAddress!, bytesPerRow: w * bpp)
            }
            if w == 1 && h == 1 { break }
            let nw = max(1, w / 2), nh = max(1, h / 2)
            var dst = [UInt8](repeating: 0, count: nw * nh * bpp)
            for y in 0..<nh {
                let y0 = min(2 * y, h - 1) * w, y1 = min(2 * y + 1, h - 1) * w
                for x in 0..<nw {
                    let x0 = min(2 * x, w - 1), x1 = min(2 * x + 1, w - 1)
                    let a = (y0 + x0) * bpp, b = (y0 + x1) * bpp
                    let c = (y1 + x0) * bpp, e = (y1 + x1) * bpp
                    let o = (y * nw + x) * bpp
                    for k in 0..<bpp {
                        dst[o + k] = UInt8((Int(src[a + k]) + Int(src[b + k])
                                          + Int(src[c + k]) + Int(src[e + k])) / 4)
                    }
                }
            }
            src = dst; w = nw; h = nh; level += 1
        }
    }

    static func hasImage(named name: String) -> Bool {
        #if canImport(UIKit)
        if UIImage(named: name) != nil { return true }
        #elseif canImport(AppKit)
        if NSImage(named: name) != nil { return true }
        #endif
        let ns = name as NSString
        let ext = ns.pathExtension.isEmpty ? nil : ns.pathExtension
        let base = ns.deletingPathExtension
        if Bundle.main.url(forResource: base, withExtension: ext) != nil { return true }
        if ext == nil {
            for e in ["png", "jpg", "jpeg", "heic", "webp"]
            where Bundle.main.url(forResource: base, withExtension: e) != nil { return true }
        }
        return false
    }

    private static func decode(_ source: ClothImageSource, targetPixels: Int = 0) -> CGImage? {
        func thumbnail(_ src: CGImageSource) -> CGImage? {
            guard targetPixels > 0 else { return CGImageSourceCreateImageAtIndex(src, 0, nil) }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: targetPixels
            ]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        switch source {
        case .cgImage(let c):
            return c
        case .data(let d):
            guard let src = CGImageSourceCreateWithData(d as CFData, nil) else { return nil }
            return thumbnail(src)
        case .url(let u):
            if let src = CGImageSourceCreateWithURL(u as CFURL, nil),
               let img = thumbnail(src) { return img }
            guard let d = try? Data(contentsOf: u),
                  let src = CGImageSourceCreateWithData(d as CFData, nil) else { return nil }
            return thumbnail(src)
        case .asset(let name):
            if let img = platformImage(named: name) { return img }
            let ns = name as NSString
            let ext = ns.pathExtension.isEmpty ? nil : ns.pathExtension
            let base = ns.deletingPathExtension
            var candidates: [URL] = []
            if let u = Bundle.main.url(forResource: base, withExtension: ext) { candidates.append(u) }
            if ext == nil {
                for e in ["png", "jpg", "jpeg", "heic", "webp"] {
                    if let u = Bundle.main.url(forResource: base, withExtension: e) { candidates.append(u) }
                }
            }
            for u in candidates {
                if let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                   let img = thumbnail(src) { return img }
            }
            return nil
        }
    }

    private static func platformImage(named name: String) -> CGImage? {
        #if canImport(UIKit)
        return UIImage(named: name)?.cgImage
        #elseif canImport(AppKit)
        guard let img = NSImage(named: name) else { return nil }
        var rect = CGRect(origin: .zero, size: img.size)
        return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return nil
        #endif
    }
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> Float {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Float(z >> 40) / Float(1 << 24)
    }
}
