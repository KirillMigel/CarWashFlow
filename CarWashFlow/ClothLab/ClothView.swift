import SwiftUI
import MetalKit

public struct ClothView: View {

    private let effect: ClothEffect
    private let showsHint: Bool
    @State private var host = ClothHost()

    public init(_ effect: ClothEffect = .greyCloth,
                fill: ClothFill? = nil,
                showsHint: Bool = false) {
        self.effect = fill.map { effect.fill($0) } ?? effect
        self.showsHint = showsHint
    }

    public init(_ imageName: String,
                effect: ClothEffect = .greyCloth,
                showsHint: Bool = false) {
        self.init(effect, fill: .image(named: imageName), showsHint: showsHint)
    }

    public var body: some View {
        GeometryReader { geo in
            ClothMetalView(effect: effect, host: host)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !host.dragging {
                                host.dragging = true
                                host.renderer?.pointerDown(at: value.startLocation, in: geo.size)
                            }
                            host.renderer?.pointerMoved(to: value.location, in: geo.size)
                        }
                        .onEnded { _ in
                            host.dragging = false
                            host.renderer?.pointerUp()
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { host.renderer?.resetCloth() }
                )
                .overlay(alignment: .bottom) {
                    if showsHint, !effect.hint.isEmpty { ClothHintLabel(text: effect.hint) }
                }
        }
    }
}

public extension View {
    func clothEffect(_ effect: ClothEffect = .greyCloth, fill: ClothFill? = nil) -> some View {
        background(ClothView(effect, fill: fill))
    }

    func clothOverlay(_ effect: ClothEffect = .greyCloth, fill: ClothFill? = nil) -> some View {
        overlay(ClothView(effect, fill: fill).allowsHitTesting(true))
    }

    func clothEffect(_ imageName: String, effect: ClothEffect = .greyCloth) -> some View {
        background(ClothView(imageName, effect: effect))
    }

    func clothOverlay(_ imageName: String, effect: ClothEffect = .greyCloth) -> some View {
        overlay(ClothView(imageName, effect: effect).allowsHitTesting(true))
    }
}

final class ClothHost {
    var renderer: ClothRenderer?
    var dragging = false
}

#if os(macOS)
typealias ClothViewRepresentable = NSViewRepresentable
#else
typealias ClothViewRepresentable = UIViewRepresentable
#endif

struct ClothMetalView {
    let effect: ClothEffect
    let host: ClothHost

    private func makeView() -> MTKView {
        let view = MTKView()
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        let transparent = effect.scene.background == .clear
        #if os(macOS)
        view.layer?.isOpaque = !transparent
        #else
        view.isOpaque = !transparent
        view.backgroundColor = .clear
        #endif

        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = ClothRenderer(device: device, effect: effect) else { return view }
        view.device = device
        view.delegate = renderer
        host.renderer = renderer
        return view
    }

    private func update(_ view: MTKView) {
        host.renderer?.update(effect: effect)
        let transparent = effect.scene.background == .clear
        #if os(macOS)
        view.layer?.isOpaque = !transparent
        #else
        view.isOpaque = !transparent
        #endif
    }
}

extension ClothMetalView: ClothViewRepresentable {
    #if os(macOS)
    func makeNSView(context: Context) -> MTKView { makeView() }
    func updateNSView(_ nsView: MTKView, context: Context) { update(nsView) }
    #else
    func makeUIView(context: Context) -> MTKView { makeView() }
    func updateUIView(_ uiView: MTKView, context: Context) { update(uiView) }
    #endif
}

struct ClothHintLabel: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(Color(clothHex: 0x7D828B))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.bottom, 26)
            .opacity(shown ? 1 : 0)
            .animation(.easeInOut(duration: 1.2), value: shown)
            .allowsHitTesting(false)
            .task {
                try? await Task.sleep(for: .milliseconds(600))
                shown = true
                try? await Task.sleep(for: .seconds(7))
                shown = false
            }
    }
}
