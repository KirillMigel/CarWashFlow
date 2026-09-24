import SwiftUI
import PhotosUI

public struct ClothLabGallery: View {

    public init() {}

    private let ink = Color(clothHex: 0xC9CED6)
    private let dim = Color(clothHex: 0x82878F)

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    NavigationLink { stage(.greyCloth) } label: {
                        featureCard(.greyCloth)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 34)

                    sectionRule("Material studies", note: "same physics, different cloth")
                    grid(of: [.holoSheet])

                    sectionRule("Motion studies", note: "same cloth, different behaviour")
                    grid(of: [.dissolvePoints])
                }
                .padding(.horizontal, 26)
                .padding(.top, 44)
                .padding(.bottom, 60)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
            .background(galleryBackdrop.ignoresSafeArea())
        }
        .tint(ink)
    }

    private var galleryBackdrop: some View {
        RadialGradient(colors: [Color(clothHex: 0x191C22),
                                Color(clothHex: 0x0C0D10),
                                Color(clothHex: 0x060708)],
                       center: UnitPoint(x: 0.3, y: 0),
                       startRadius: 0, endRadius: 900)
        .background(Color(clothHex: 0x08090B))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cloth Lab")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .tracking(4.2)
                .textCase(.uppercase)
                .foregroundStyle(Color(clothHex: 0xE6E9EE))
            Text("Interactive fabric simulations. Grab any of them from anywhere on screen and pull.")
                .font(.system(size: 12, design: .monospaced))
                .tracking(1.4)
                .lineSpacing(6)
                .foregroundStyle(Color(clothHex: 0x7D828B))
                .frame(maxWidth: 460, alignment: .leading)
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
        }
    }

    private func label(_ n: Int) -> String { String(format: "%02d", n) }

    private func featureCard(_ e: ClothEffect) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(label(e.number)) — image ready")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .tracking(2.4)
                .textCase(.uppercase)
                .foregroundStyle(Color(clothHex: 0x6F747C))
            Text(e.name)
                .font(.system(size: 26, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Color(clothHex: 0xEEF1F5))
                .padding(.top, 14)
            Text("\(e.blurb) Drop in any photo and the cloth wears it.")
                .font(.system(size: 12, design: .monospaced))
                .tracking(1.2)
                .lineSpacing(6)
                .foregroundStyle(dim)
                .frame(maxWidth: 460, alignment: .leading)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 34)
        .padding(.horizontal, 30)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.015)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func sectionRule(_ title: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .tracking(2.4)
                .textCase(.uppercase)
                .foregroundStyle(dim)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            Text(note)
                .font(.system(size: 10, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(Color(clothHex: 0x5D6269))
        }
        .padding(.top, 44)
        .padding(.bottom, 16)
    }

    private func grid(of effects: [ClothEffect]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 244), spacing: 18)], spacing: 18) {
            ForEach(effects) { e in
                NavigationLink { stage(e) } label: { card(e) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func card(_ e: ClothEffect) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label(e.number))
                .font(.system(size: 10, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(Color(clothHex: 0x63686F))
            Text(e.name)
                .font(.system(size: 17, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Color(clothHex: 0xE2E6EC))
                .padding(.top, 12)
            Text(e.blurb)
                .font(.system(size: 11, design: .monospaced))
                .tracking(1.1)
                .lineSpacing(6)
                .foregroundStyle(dim)
                .padding(.top, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 24, leading: 22, bottom: 22, trailing: 22))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.022))
        .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func stage(_ e: ClothEffect) -> some View {
        ClothStage(effect: e)
    }
}

struct ClothStage: View {

    let effect: ClothEffect

    @Environment(\.dismiss) private var dismiss
    @State private var fill: ClothFill = .grey
    @State private var pick: PhotosPickerItem?

    private struct Swatch: Identifiable {
        let id: String
        let fill: ClothFill
    }

    private let swatches: [Swatch] = [
        Swatch(id: "grey", fill: .grey),
        Swatch(id: "ink", fill: .color(Color(clothHex: 0x2B2F36))),
        Swatch(id: "rust", fill: .color(Color(clothHex: 0xB4552F))),
        Swatch(id: "sea", fill: .color(Color(clothHex: 0x2C6E7F))),
        Swatch(id: "dusk", fill: .gradient([Color(clothHex: 0xE9C46A), Color(clothHex: 0x9B3B6E)],
                                           angle: .degrees(160))),
        Swatch(id: "image", fill: .image("ClothLabDemo"))
    ]

    var body: some View {
        ClothView(effect, fill: fill, showsHint: true)
            .overlay(alignment: .topLeading) { backLink }
            .overlay(alignment: .bottom) { controls }
            .background(Color(clothHex: 0x060607))
            .ignoresSafeArea()
            #if !os(macOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onChange(of: pick) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        fill = .image(data: data)
                    }
                }
            }
    }

    private var backLink: some View {
        Button { dismiss() } label: {
            Text("← all effects")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Color(clothHex: 0x7D828B))
        }
        .buttonStyle(.plain)
        .padding(.leading, 26)
        .padding(.top, 22)
    }

    private var controls: some View {
        HStack(spacing: 9) {
            ForEach(swatches) { swatch in
                let on = fill == swatch.fill
                Button { fill = swatch.fill } label: {
                    Text(swatch.id)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(on ? Color(clothHex: 0xE6E9EE) : Color(clothHex: 0x9AA0A8))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(on ? 0.1 : 0.04)))
                        .overlay(Capsule().stroke(Color.white.opacity(on ? 0.26 : 0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            PhotosPicker(selection: $pick, matching: .images) {
                Text("photo")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(fill.isPicture ? Color(clothHex: 0xE6E9EE) : Color(clothHex: 0x9AA0A8))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(fill.isPicture ? 0.1 : 0.04)))
                    .overlay(Capsule().stroke(Color.white.opacity(fill.isPicture ? 0.26 : 0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 54)
    }
}

#Preview {
    ClothLabGallery()
}
