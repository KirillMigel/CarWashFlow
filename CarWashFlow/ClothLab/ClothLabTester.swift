import SwiftUI
import Metal

public struct ClothLabTester: View {

    static let imageFill: ClothFill = ClothTextures.hasImage(named: "im1")
        ? .image("im1")
        : .image("ClothLabDemo")

    public init() {}

    public static func warmImages() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let resolved = imageFill.resolved()
        let sheets = ClothEffect.all.map {
            ($0.material.whenWearingAnImage.fit,
             $0.physics.width / max($0.physics.height, 1e-4))
        }
        ClothTextures.prewarm(resolved, fits: sheets, device: device)
    }

    @State private var showGallery = false

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    ForEach(Array(ClothEffect.all.enumerated()), id: \.element.id) { index, effect in
                        NavigationLink {
                            ClothTestStage(startIndex: index)
                        } label: {
                            row(effect)
                        }
                        .buttonStyle(.plain)
                    }

                    Button { showGallery = true } label: {
                        Text("open the designed gallery instead →")
                            .font(.system(size: 11, design: .monospaced))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Color(clothHex: 0x6F747C))
                            .padding(.top, 30)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 60)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(Color(clothHex: 0x08090B).ignoresSafeArea())
            .fullScreenCoverCompat(isPresented: $showGallery) { ClothLabGallery() }
        }
        .tint(Color(clothHex: 0xC9CED6))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cloth Lab · test")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .tracking(3.6)
                .textCase(.uppercase)
                .foregroundStyle(Color(clothHex: 0xE6E9EE))
            Text("Open one, drag the cloth about, then use ‹ › to step to the next.")
                .font(.system(size: 12, design: .monospaced))
                .tracking(1.2)
                .lineSpacing(5)
                .foregroundStyle(Color(clothHex: 0x7D828B))
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
        }
        .padding(.bottom, 22)
    }

    private func row(_ e: ClothEffect) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(String(format: "%02d", e.number))
                .font(.system(size: 13, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color(clothHex: 0x63686F))
                .frame(width: 34, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 7) {
                Text(e.name)
                    .font(.system(size: 17, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color(clothHex: 0xE2E6EC))
                Text(e.blurb)
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.9)
                    .lineSpacing(5)
                    .foregroundStyle(Color(clothHex: 0x82878F))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("test →")
                .font(.system(size: 11, design: .monospaced))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Color(clothHex: 0x9AA0A8))
                .padding(.top, 2)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
        }
    }
}

struct ClothTestStage: View {

    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(startIndex: Int) {
        self.startIndex = startIndex
        _index = State(initialValue: startIndex)
    }

    private var effect: ClothEffect { ClothEffect.all[index] }
    private var fill: ClothFill { ClothLabTester.imageFill }

    var body: some View {
        ZStack {
            Color(clothHex: 0x060607).ignoresSafeArea()

            ClothView(effect, fill: fill)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
            }
        }
        #if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Text("← list")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color(clothHex: 0xC9CED6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 6)

                step("‹") { index = (index - 1 + ClothEffect.all.count) % ClothEffect.all.count }
                step("›") { index = (index + 1) % ClothEffect.all.count }
            }

            HStack(spacing: 10) {
                Text(String(format: "%02d", effect.number))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(clothHex: 0x8D939B))
                Text(effect.name)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Color(clothHex: 0xF2F5F9))
                Text("\(index + 1)/\(ClothEffect.all.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(clothHex: 0x8D939B))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.black.opacity(0.5)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func step(_ glyph: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(clothHex: 0xE6E9EE))
                .frame(width: 38, height: 32)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func fullScreenCoverCompat<C: View>(isPresented: Binding<Bool>,
                                        @ViewBuilder content: @escaping () -> C) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, content: content)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}

#Preview {
    ClothLabTester()
}
