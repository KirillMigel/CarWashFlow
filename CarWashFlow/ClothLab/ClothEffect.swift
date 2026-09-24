import SwiftUI
import simd

public enum ClothImageSource: ExpressibleByStringLiteral {
    case asset(String)
    case url(URL)
    case data(Data)
    case cgImage(CGImage)

    public init(stringLiteral value: String) { self = .asset(value) }
}

extension ClothImageSource: Equatable {
    public static func == (a: ClothImageSource, b: ClothImageSource) -> Bool {
        switch (a, b) {
        case let (.asset(x), .asset(y)): return x == y
        case let (.url(x), .url(y)): return x == y
        case let (.data(x), .data(y)): return x == y
        case let (.cgImage(x), .cgImage(y)): return x === y
        default: return false
        }
    }
}

public enum ClothFill: Equatable {
    case color(Color)
    case gradient([Color], angle: Angle)
    case image(ClothImageSource)

    public static let grey = ClothFill.color(ClothPalette.grey)

    public static func gradient(_ colors: [Color]) -> ClothFill { .gradient(colors, angle: .degrees(180)) }

    public static func image(named name: String) -> ClothFill { .image(.asset(name)) }
    public static func image(url: URL) -> ClothFill { .image(.url(url)) }
    public static func image(data: Data) -> ClothFill { .image(.data(data)) }
    public static func image(cgImage: CGImage) -> ClothFill { .image(.cgImage(cgImage)) }

    var isPicture: Bool { if case .image = self { return true }; return false }
}

public enum ClothPalette {
    public static let grey = Color(clothHex: 0xA7ABB2)
    public static let holo = Color(clothHex: 0x9AA0A8)
    public static let points = Color(clothHex: 0xC4C9D1)
}

public struct ClothWeave: Equatable {
    public var size: Int = 64
    public var step: Int = 4
    public var thread: Int = 2
    public var speck: Int = 900
    public var base: Double = 0.502
    public var warp: Double = 0.545
    public var weft: Double = 0.459
    public var tile: SIMD2<Float> = SIMD2(14, 18)

    public init(size: Int = 64, step: Int = 4, thread: Int = 2, speck: Int = 900,
                base: Double = 0.502, warp: Double = 0.545, weft: Double = 0.459,
                tile: SIMD2<Float> = SIMD2(14, 18)) {
        self.size = size; self.step = step; self.thread = thread; self.speck = speck
        self.base = base; self.warp = warp; self.weft = weft; self.tile = tile
    }
}

public struct ClothMaterial: Equatable {
    public var roughness: Float = 0.78
    public var metalness: Float = 0
    public var sheen: Float = 1
    public var sheenColor: Color = Color(clothHex: 0xE4E8EE)
    public var sheenRoughness: Float = 0.55
    public var iridescence: Float = 0
    public var iridescenceIOR: Float = 1.3
    public var iridescenceThickness: SIMD2<Float> = SIMD2(100, 400)
    public var envIntensity: Float = 0.55
    public var weave: ClothWeave? = ClothWeave()
    public var bumpScale: Float = 0.6
    public var whenWearingAnImage = ClothImageLook()

    public init(roughness: Float = 0.78, metalness: Float = 0,
                sheen: Float = 1, sheenColor: Color = Color(clothHex: 0xE4E8EE),
                sheenRoughness: Float = 0.55,
                iridescence: Float = 0, iridescenceIOR: Float = 1.3,
                iridescenceThickness: SIMD2<Float> = SIMD2(100, 400),
                envIntensity: Float = 0.55,
                weave: ClothWeave? = ClothWeave(), bumpScale: Float = 0.6,
                whenWearingAnImage: ClothImageLook = ClothImageLook()) {
        self.roughness = roughness; self.metalness = metalness
        self.sheen = sheen; self.sheenColor = sheenColor; self.sheenRoughness = sheenRoughness
        self.iridescence = iridescence; self.iridescenceIOR = iridescenceIOR
        self.iridescenceThickness = iridescenceThickness
        self.envIntensity = envIntensity
        self.weave = weave; self.bumpScale = bumpScale
        self.whenWearingAnImage = whenWearingAnImage
    }
}

public struct ClothImageLook: Equatable {
    public var emissive: Float = 0.55
    public var tint: Color = .white
    public var roughness: Float? = 0.95
    public var metalness: Float? = nil
    public var sheen: Float? = 0
    public var envIntensity: Float? = 0.12
    public var bumpScale: Float? = 0.12
    public var exposure: Float? = 1.05
    public var fit: ClothImageFit = .cover

    public init(emissive: Float = 0.55, tint: Color = .white,
                roughness: Float? = 0.95, metalness: Float? = nil, sheen: Float? = 0,
                envIntensity: Float? = 0.12, bumpScale: Float? = 0.12,
                exposure: Float? = 1.05, fit: ClothImageFit = .cover) {
        self.emissive = emissive; self.tint = tint
        self.roughness = roughness; self.metalness = metalness; self.sheen = sheen
        self.envIntensity = envIntensity; self.bumpScale = bumpScale
        self.exposure = exposure; self.fit = fit
    }
}

public enum ClothImageFit: Equatable {
    case cover
    case contain
    case stretch
    case tile(SIMD2<Float>)
}

public enum ClothPins: Equatable {
    case none
    case top
    case topCorners
    case left
    case corners
    case custom([SIMD2<Int>])
}

public struct ClothPhysics: Equatable {
    public var cols: Int = 42
    public var rows: Int = 54
    public var width: Float = 2.35
    public var height: Float = 3.05
    public var pins: ClothPins = .none
    public var gravity: Float = 0
    public var restSpring: Float = 3
    public var relax: Float = 0.006
    public var wind: Float = 0
    public var windScale: Float = 1
    public var damping: Float = 0.992
    public var iterations: Int = 3
    public var shear: Float = 0.8
    public var bend: Float = 0.45
    public var settle: Int = 0
    public var grabRadius: Float = 0.34
    public var grabLift: Float = 0.35
    public var grabStrength: Float = 0.32

    public init(cols: Int = 42, rows: Int = 54, width: Float = 2.35, height: Float = 3.05,
                pins: ClothPins = .none, gravity: Float = 0, restSpring: Float = 3,
                relax: Float = 0.006, wind: Float = 0, windScale: Float = 1,
                damping: Float = 0.992, iterations: Int = 3,
                shear: Float = 0.8, bend: Float = 0.45, settle: Int = 0,
                grabRadius: Float = 0.34, grabLift: Float = 0.35, grabStrength: Float = 0.32) {
        self.cols = cols; self.rows = rows; self.width = width; self.height = height
        self.pins = pins; self.gravity = gravity; self.restSpring = restSpring
        self.relax = relax; self.wind = wind; self.windScale = windScale
        self.damping = damping; self.iterations = iterations
        self.shear = shear; self.bend = bend; self.settle = settle
        self.grabRadius = grabRadius; self.grabLift = grabLift; self.grabStrength = grabStrength
    }
}

public enum ClothBackground: Equatable {
    case clear
    case color(Color)
    case radial(inner: Color, mid: Color, outer: Color,
                center: UnitPoint = UnitPoint(x: 0.5, y: 0.45),
                extent: SIMD2<Float> = SIMD2(1.2, 0.9))
}

public struct ClothGrain: Equatable {
    public var overlay: Float = 0.55
    public var screen: Float = 0.05
    public var scale: Float = 1
    public init(overlay: Float = 0.55, screen: Float = 0.05, scale: Float = 1) {
        self.overlay = overlay; self.screen = screen; self.scale = scale
    }
}

public struct ClothScene: Equatable {
    public var fov: Float = 38
    public var cameraDistance: Float = 5.4
    public var rotation: SIMD3<Float> = SIMD3(0.05, -0.12, 0)
    public var exposure: Float = 1.12
    public var scale: Float = 0.7
    public var environment: Bool = true
    public var environmentBlur: Float = 0.04
    public var lights: Bool = true
    public var background: ClothBackground = .radial(inner: Color(clothHex: 0x17191E),
                                                     mid: Color(clothHex: 0x0C0D10),
                                                     outer: Color(clothHex: 0x060607),
                                                     center: UnitPoint(x: 0.46, y: 0.46),
                                                     extent: SIMD2(1.2, 0.9))
    public var grain: ClothGrain? = ClothGrain()

    public init(fov: Float = 38, cameraDistance: Float = 5.4,
                rotation: SIMD3<Float> = SIMD3(0.05, -0.12, 0),
                exposure: Float = 1.12, scale: Float = 0.7,
                environment: Bool = true, environmentBlur: Float = 0.04,
                lights: Bool = true,
                background: ClothBackground = .radial(inner: Color(clothHex: 0x17191E),
                                                      mid: Color(clothHex: 0x0C0D10),
                                                      outer: Color(clothHex: 0x060607),
                                                      center: UnitPoint(x: 0.46, y: 0.46),
                                                      extent: SIMD2(1.2, 0.9)),
                grain: ClothGrain? = ClothGrain()) {
        self.fov = fov; self.cameraDistance = cameraDistance; self.rotation = rotation
        self.exposure = exposure; self.scale = scale
        self.environment = environment; self.environmentBlur = environmentBlur
        self.lights = lights; self.background = background; self.grain = grain
    }
}

public struct ClothPointsStyle: Equatable {
    public var size: Float = 0.03
    public var opacity: Float = 0.95
    public var round: Bool = true
    public var sizeAttenuation: Bool = true
    public var takesColourFromFill: Bool = true

    public init(size: Float = 0.03, opacity: Float = 0.95, round: Bool = true,
                sizeAttenuation: Bool = true, takesColourFromFill: Bool = true) {
        self.size = size; self.opacity = opacity; self.round = round
        self.sizeAttenuation = sizeAttenuation; self.takesColourFromFill = takesColourFromFill
    }
}

public struct ClothDissolve: Equatable {
    public var cycle: Float = 13
    public var scatterStart: Float = 7
    public var scatterEnd: Float = 11
    public var rampIn: Float = 1.1
    public var rampOut: Float = 1.4
    public var strength: Float = 0.024
    public var burst: Float = 1.1

    public init(cycle: Float = 13, scatterStart: Float = 7, scatterEnd: Float = 11,
                rampIn: Float = 1.1, rampOut: Float = 1.4,
                strength: Float = 0.024, burst: Float = 1.1) {
        self.cycle = cycle; self.scatterStart = scatterStart; self.scatterEnd = scatterEnd
        self.rampIn = rampIn; self.rampOut = rampOut
        self.strength = strength; self.burst = burst
    }
}

public enum ClothBehavior: Equatable {
    case none
    case dissolve(ClothDissolve)
}

public struct ClothEffect: Identifiable, Equatable {
    public var number: Int
    public var name: String
    public var blurb: String
    public var hint: String
    public var fill: ClothFill
    public var physics: ClothPhysics
    public var material: ClothMaterial
    public var scene: ClothScene
    public var points: ClothPointsStyle?
    public var behavior: ClothBehavior
    public var speed: Float = 6

    public var id: Int { number }

    public init(number: Int = 0,
                name: String = "Cloth",
                blurb: String = "",
                hint: String = "",
                fill: ClothFill = .grey,
                physics: ClothPhysics = ClothPhysics(),
                material: ClothMaterial = ClothMaterial(),
                scene: ClothScene = ClothScene(),
                points: ClothPointsStyle? = nil,
                behavior: ClothBehavior = .none,
                speed: Float = 6) {
        self.number = number; self.name = name; self.blurb = blurb; self.hint = hint
        self.fill = fill; self.physics = physics; self.material = material
        self.scene = scene; self.points = points; self.behavior = behavior
        self.speed = speed
    }
}

public extension ClothEffect {

    static let greyCloth = ClothEffect(
        number: 1,
        name: "Grey Cloth",
        blurb: "Flat colour that breathes on its own, and folds when you touch it.",
        hint: "grab anywhere and pull",
        physics: ClothPhysics(cols: 42, rows: 54, width: 2.35, height: 3.05,
                              pins: .none, gravity: 0, restSpring: 3, relax: 0.006, wind: 0.14),
        material: ClothMaterial(roughness: 1, metalness: 0,
                                sheen: 0,
                                envIntensity: 0,
                                weave: nil, bumpScale: 0),
        scene: ClothScene(cameraDistance: 5.4, exposure: 1,
                          environment: false, lights: false, grain: nil)
    )

    static let holoSheet = ClothEffect(
        number: 6,
        name: "Holo Sheet",
        blurb: "Thin-film iridescence on polished metal. Every fold shifts the light.",
        hint: "thin-film sheet · grab anywhere to catch the light",
        physics: ClothPhysics(cols: 44, rows: 56, width: 2.4, height: 3.1,
                              pins: .none, gravity: 0, restSpring: 3, relax: 0.006, wind: 0.22),
        material: ClothMaterial(roughness: 0.16, metalness: 0.85,
                                sheen: 0, sheenRoughness: 0.55,
                                iridescence: 1, iridescenceIOR: 1.9,
                                iridescenceThickness: SIMD2(110, 520),
                                envIntensity: 1.5,
                                weave: nil, bumpScale: 0,
                                whenWearingAnImage: ClothImageLook(emissive: 0.3,
                                                                   roughness: 0.28,
                                                                   metalness: 0.6,
                                                                   sheen: 0,
                                                                   envIntensity: 0.9,
                                                                   bumpScale: nil,
                                                                   exposure: 1.05)),
        scene: ClothScene(cameraDistance: 5.3, exposure: 1.05, environmentBlur: 0.02,
                          background: .radial(inner: Color(clothHex: 0x12141A),
                                              mid: Color(clothHex: 0x08090C),
                                              outer: Color(clothHex: 0x040405),
                                              center: UnitPoint(x: 0.5, y: 0.45),
                                              extent: SIMD2(1.1, 0.85)),
                          grain: nil)
    )

    static let dissolvePoints = ClothEffect(
        number: 21,
        name: "Dissolve Points",
        blurb: "A point cloud that scatters apart and reassembles. Tap to burst it.",
        hint: "tap to burst · it comes back together on its own",
        physics: ClothPhysics(cols: 44, rows: 54, width: 2.4, height: 3.1,
                              pins: .none, gravity: 0, restSpring: 3.4, relax: 0.012,
                              wind: 0.1, damping: 0.994),
        material: ClothMaterial(roughness: 1, metalness: 0, sheen: 0,
                                envIntensity: 0, weave: nil, bumpScale: 0,
                                whenWearingAnImage: ClothImageLook(emissive: 1, roughness: nil,
                                                                   metalness: nil, sheen: nil,
                                                                   envIntensity: nil, bumpScale: nil,
                                                                   exposure: nil)),
        scene: ClothScene(cameraDistance: 5.4, exposure: 1,
                          environment: false, lights: false,
                          background: .radial(inner: Color(clothHex: 0x12141A),
                                              mid: Color(clothHex: 0x08090C),
                                              outer: Color(clothHex: 0x040405),
                                              center: UnitPoint(x: 0.5, y: 0.45),
                                              extent: SIMD2(1.1, 0.85)),
                          grain: nil),
        points: ClothPointsStyle(),
        behavior: .dissolve(ClothDissolve())
    )

    static let all: [ClothEffect] = [.greyCloth, .holoSheet, .dissolvePoints]
}

public extension ClothEffect {

    private func with(_ edit: (inout ClothEffect) -> Void) -> ClothEffect {
        var copy = self; edit(&copy); return copy
    }

    func fill(_ f: ClothFill) -> ClothEffect { with { $0.fill = f } }
    func color(_ c: Color) -> ClothEffect { with { $0.fill = .color(c) } }
    func image(_ source: ClothImageSource) -> ClothEffect { with { $0.fill = .image(source) } }
    func gradient(_ colors: [Color], angle: Angle = .degrees(180)) -> ClothEffect {
        with { $0.fill = .gradient(colors, angle: angle) }
    }
    func imageFit(_ fit: ClothImageFit) -> ClothEffect { with { $0.material.whenWearingAnImage.fit = fit } }
    func imageBrightness(_ emissive: Float) -> ClothEffect { with { $0.material.whenWearingAnImage.emissive = emissive } }
    func imageTint(_ c: Color) -> ClothEffect { with { $0.material.whenWearingAnImage.tint = c } }

    func roughness(_ v: Float) -> ClothEffect { with { $0.material.roughness = v } }
    func metalness(_ v: Float) -> ClothEffect { with { $0.material.metalness = v } }
    func sheen(_ v: Float, color: Color? = nil, roughness: Float? = nil) -> ClothEffect {
        with {
            $0.material.sheen = v
            if let color { $0.material.sheenColor = color }
            if let roughness { $0.material.sheenRoughness = roughness }
        }
    }
    func iridescence(_ v: Float, ior: Float? = nil, thickness: SIMD2<Float>? = nil) -> ClothEffect {
        with {
            $0.material.iridescence = v
            if let ior { $0.material.iridescenceIOR = ior }
            if let thickness { $0.material.iridescenceThickness = thickness }
        }
    }
    func weave(_ w: ClothWeave?) -> ClothEffect { with { $0.material.weave = w } }
    func bumpScale(_ v: Float) -> ClothEffect { with { $0.material.bumpScale = v } }
    func environmentIntensity(_ v: Float) -> ClothEffect { with { $0.material.envIntensity = v } }
    func material(_ edit: (inout ClothMaterial) -> Void) -> ClothEffect { with { edit(&$0.material) } }

    func grid(cols: Int, rows: Int) -> ClothEffect { with { $0.physics.cols = cols; $0.physics.rows = rows } }
    func size(width: Float, height: Float) -> ClothEffect { with { $0.physics.width = width; $0.physics.height = height } }
    func pins(_ p: ClothPins) -> ClothEffect { with { $0.physics.pins = p } }
    func gravity(_ v: Float) -> ClothEffect { with { $0.physics.gravity = v } }
    func wind(_ v: Float) -> ClothEffect { with { $0.physics.wind = v } }
    func damping(_ v: Float) -> ClothEffect { with { $0.physics.damping = v } }
    func stiffness(shear: Float? = nil, bend: Float? = nil, iterations: Int? = nil) -> ClothEffect {
        with {
            if let shear { $0.physics.shear = shear }
            if let bend { $0.physics.bend = bend }
            if let iterations { $0.physics.iterations = iterations }
        }
    }
    func grab(radius: Float? = nil, lift: Float? = nil, strength: Float? = nil) -> ClothEffect {
        with {
            if let radius { $0.physics.grabRadius = radius }
            if let lift { $0.physics.grabLift = lift }
            if let strength { $0.physics.grabStrength = strength }
        }
    }
    func physics(_ edit: (inout ClothPhysics) -> Void) -> ClothEffect { with { edit(&$0.physics) } }

    func camera(distance: Float? = nil, fov: Float? = nil) -> ClothEffect {
        with {
            if let distance { $0.scene.cameraDistance = distance }
            if let fov { $0.scene.fov = fov }
        }
    }
    func rotation(x: Float = 0, y: Float = 0, z: Float = 0) -> ClothEffect {
        with { $0.scene.rotation = SIMD3(x, y, z) }
    }
    func exposure(_ v: Float) -> ClothEffect { with { $0.scene.exposure = v } }
    func scale(_ v: Float) -> ClothEffect { with { $0.scene.scale = v } }
    func background(_ b: ClothBackground) -> ClothEffect { with { $0.scene.background = b } }
    func transparentBackground() -> ClothEffect { with { $0.scene.background = .clear } }
    func grain(_ g: ClothGrain?) -> ClothEffect { with { $0.scene.grain = g } }
    func lighting(lights: Bool? = nil, environment: Bool? = nil) -> ClothEffect {
        with {
            if let lights { $0.scene.lights = lights }
            if let environment { $0.scene.environment = environment }
        }
    }
    func scene(_ edit: (inout ClothScene) -> Void) -> ClothEffect { with { edit(&$0.scene) } }

    func asPoints(_ style: ClothPointsStyle = ClothPointsStyle()) -> ClothEffect { with { $0.points = style } }
    func asSurface() -> ClothEffect { with { $0.points = nil } }
    func pointSize(_ v: Float) -> ClothEffect {
        with {
            var s = $0.points ?? ClothPointsStyle(); s.size = v; $0.points = s
        }
    }
    func behavior(_ b: ClothBehavior) -> ClothEffect { with { $0.behavior = b } }

    func speed(_ v: Float) -> ClothEffect { with { $0.speed = max(0, v) } }
}

struct ResolvedClothFill {
    enum Kind {
        case color(SIMD3<Float>)
        case gradient([SIMD4<Float>], Double)
        case image(ClothImageSource)
    }
    var kind: Kind
    var fallback: SIMD3<Float>
}

extension ClothFill {
    func resolved() -> ResolvedClothFill {
        let fallback = ClothPalette.grey.clothLinear
        switch self {
        case .color(let c):
            return ResolvedClothFill(kind: .color(c.clothLinear), fallback: fallback)
        case .gradient(let colors, let angle):
            return ResolvedClothFill(kind: .gradient(colors.map { $0.clothSRGB }, angle.radians),
                                     fallback: fallback)
        case .image(let source):
            return ResolvedClothFill(kind: .image(source), fallback: fallback)
        }
    }
}

public extension Color {
    init(clothHex hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Color {
    var clothLinear: SIMD3<Float> {
        let r = resolve(in: EnvironmentValues())
        return SIMD3(r.linearRed, r.linearGreen, r.linearBlue)
    }
    var clothSRGB: SIMD4<Float> {
        let r = resolve(in: EnvironmentValues())
        return SIMD4(r.red, r.green, r.blue, r.opacity)
    }
}
