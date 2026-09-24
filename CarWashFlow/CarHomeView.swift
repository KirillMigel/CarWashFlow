import SwiftUI

struct CarHomeView: View {
    private let designSize = CGSize(width: 375, height: 782)

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / designSize.width
            let safeTop = geo.safeAreaInsets.top
            let renderedHeight = designSize.height * scale

            ZStack(alignment: .topLeading) {
                Color.carWashBackground

                Image("MainHomeBackground")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: geo.size.width, height: renderedHeight)
                    .position(x: geo.size.width / 2, y: safeTop + renderedHeight / 2)
                    .accessibilityHidden(true)

                Image("TransportAuto")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: 24 * scale, height: 24 * scale)
                    .position(x: 338 * scale, y: safeTop + 23 * scale)
                    .accessibilityLabel("Автомобиль")

                NavigationLink(value: CarRoute.cleaning) {
                    Color.clear
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .frame(width: 230 * scale, height: 56 * scale)
                .position(x: designSize.width * scale / 2, y: safeTop + 189 * scale)
                .accessibilityLabel("Пора помыть авто")
                .accessibilityHint("Открывает экран очистки автомобиля")
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        CarHomeView()
            .navigationDestination(for: CarRoute.self) { _ in
                CarCleaningView()
            }
    }
}
