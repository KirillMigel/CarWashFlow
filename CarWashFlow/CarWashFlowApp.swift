import SwiftUI
import Metal

@main
struct CarWashFlowApp: App {

    init() {
        ClothGPU.warmUp()
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let fill = ClothFill.image(named: "ClothTexture").resolved()
        ClothTextures.prewarm(fill, fits: [(.contain, 1.2)], device: device)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
