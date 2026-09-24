import SwiftUI

struct CarWashMapView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            FlowBoardImage(.map)
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Button(action: { dismiss() }) {
                        Color.clear
                            .frame(width: 52, height: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 44)
                    .padding(.trailing, 4)
                    .accessibilityLabel("Закрыть карту")
                }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .preferredColorScheme(.light)
    }
}
