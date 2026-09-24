import SwiftUI

struct ContentView: View {
    @State private var selection: RootTab = .home
    @State private var path: [CarRoute] = Self.initialPath

    var body: some View {
        NavigationStack(path: $path) {
            rootTabs
                .navigationDestination(for: CarRoute.self) { route in
                    switch route {
                    case .cleaning:
                        CarCleaningView()
                    case .carWashes:
                        CarWashMapView()
                    }
                }
        }
        .preferredColorScheme(.dark)
    }

    private var rootTabs: some View {
        GeometryReader { geo in
            let barHeight = geo.size.width * 464 / 1608

            ZStack(alignment: .bottom) {
                selectedTab

                MainTabBar(selection: $selection)
                    .frame(width: geo.size.width, height: barHeight)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private static var initialPath: [CarRoute] {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--map-preview") {
            return [.cleaning, .carWashes]
        }
        if arguments.contains("--cleaning-preview") {
            return [.cleaning]
        }
#endif
        return []
    }

    @ViewBuilder
    private var selectedTab: some View {
        switch selection {
        case .home:
            CarHomeView()
        case .payments:
            PlaceholderTab(title: "Платежи", icon: "creditcard.fill")
        case .city:
            PlaceholderTab(title: "Город", icon: "building.2.fill")
        case .chat:
            PlaceholderTab(title: "Чат", icon: "message.fill")
        case .more:
            PlaceholderTab(title: "Еще", icon: "ellipsis.circle.fill")
        }
    }
}

private enum RootTab: Hashable {
    case home, payments, city, chat, more
}

enum CarRoute: Hashable {
    case cleaning
    case carWashes
}

private struct PlaceholderTab: View {
    let title: String
    let icon: String

    var body: some View {
        ZStack {
            Color.carWashBackground
                .ignoresSafeArea()

            ContentUnavailableView(title, systemImage: icon)
                .foregroundStyle(.white)
                .padding(.bottom, 96)
        }
    }
}

private struct MainTabBar: View {
    @Binding var selection: RootTab

    var body: some View {
        Image("MainTabBar")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .overlay {
                HStack(spacing: 0) {
                    tabButton(.home, label: "Главная")
                    tabButton(.payments, label: "Платежи")
                    tabButton(.city, label: "Город")
                    tabButton(.chat, label: "Чат")
                    tabButton(.more, label: "Еще")
                }
                .padding(.horizontal, 8)
            }
    }

    private func tabButton(_ tab: RootTab, label: String) -> some View {
        Button {
            selection = tab
        } label: {
            Color.clear
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

#Preview {
    ContentView()
}
