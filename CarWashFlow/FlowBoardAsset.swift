import SwiftUI
import UIKit

enum FlowBoardCrop {
    case mainDirtyCar
    case cleaningDirtyCar
    case map

    fileprivate var rect: CGRect {
        switch self {
        case .mainDirtyCar:
            CGRect(x: 261, y: 396, width: 329, height: 183)
        case .cleaningDirtyCar:
            CGRect(x: 659, y: 453, width: 405, height: 225)
        case .map:
            CGRect(x: 1997, y: 190, width: 375, height: 812)
        }
    }
}

struct FlowBoardImage: View {
    let crop: FlowBoardCrop

    init(_ crop: FlowBoardCrop) {
        self.crop = crop
    }

    var body: some View {
        if let source = UIImage(named: "FlowBoard")?.cgImage,
           let cropped = source.cropping(to: crop.rect) {
            Image(decorative: cropped, scale: 1)
                .resizable()
        } else {
            Color.clear
        }
    }
}
