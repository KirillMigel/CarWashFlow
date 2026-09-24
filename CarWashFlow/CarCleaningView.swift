import SwiftUI
import UIKit

struct CarCleaningView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var clothPosition = CGPoint.zero
    @State private var dragOrigin: CGPoint?
    @State private var strokes: [[CGPoint]] = []
    @State private var cleanedCells: Set<Int> = []
    @State private var isRecordingStroke = false
    @State private var isComplete = {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--completed-preview")
#else
        false
#endif
    }()

    private let gridColumns = 24
    private let gridRows = 10

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let designScale = width / 375
            let safeTop = geo.safeAreaInsets.top
            let dirtyHeight = width * 225 / 405
            let dirtyFrame = CGRect(x: 0, y: safeTop + 205, width: width, height: dirtyHeight)
            let clothWidth = width * 0.64
            let clothHeight = clothWidth * 0.84

            ZStack(alignment: .top) {
                Color.carWashBackground

                Button(action: { dismiss() }) {
                    Image("BackNavigationButton")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48 * designScale, height: 48 * designScale)
                        .clipShape(.circle)
                }
                .buttonStyle(.plain)
                .position(x: 37 * designScale, y: safeTop + 24 * designScale)
                .accessibilityLabel("Назад")

                header
                    .padding(.horizontal, 12)
                    .position(x: width / 2, y: safeTop + 108)

                CleanableCarView(strokes: strokes, dirtyOpacity: isComplete ? 0 : 1)
                    .frame(width: dirtyFrame.width, height: dirtyFrame.height)
                    .position(x: dirtyFrame.midX, y: dirtyFrame.midY)
                    .opacity(isComplete ? 0 : 1)
                    .animation(.smooth(duration: 0.7), value: isComplete)
                    .accessibilityLabel(isComplete ? "Чистый синий Porsche Cayenne" : "Грязный синий Porsche Cayenne")

                if isComplete {
                    CleanCarCelebrationView(reduceMotion: reduceMotion)
                        .frame(width: width * 0.90, height: dirtyHeight * 1.05)
                        .position(x: width / 2, y: safeTop + 388)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }

                if !isComplete {
                    ClothView(clothEffect)
                        .frame(width: clothWidth, height: clothHeight)
                        .position(clothPosition == .zero
                                  ? CGPoint(x: width / 2, y: geo.size.height * 0.73)
                                  : clothPosition)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    moveCloth(
                                        translation: value.translation,
                                        in: geo.size,
                                        clothSize: CGSize(width: clothWidth, height: clothHeight),
                                        carFrame: dirtyFrame
                                    )
                                }
                                .onEnded { _ in
                                    dragOrigin = nil
                                    isRecordingStroke = false
                                }
                        )
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .accessibilityLabel("Тряпка")
                        .accessibilityHint("Перетаскивайте по машине, чтобы очистить её")
                }

                if isComplete {
                    NavigationLink(value: CarRoute.carWashes) {
                        Text("Заглянуть в автомойки")
                            .font(.body)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color("TUIAccent"), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.bottom, max(16, geo.safeAreaInsets.bottom + 2))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
            .onAppear {
                guard clothPosition == .zero else { return }
                clothPosition = CGPoint(x: width / 2, y: geo.size.height * 0.73)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 14) {
            Text(isComplete ? "Выглядит как новая" : "Авто загрязнилось")
                .font(.system(size: 30, weight: .bold))
                .tracking(0.36)
                .multilineTextAlignment(.center)

            Text(isComplete
                 ? "Не забывайте заглядывать в автомойки"
                 : "Протрите его тряпочкой")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.92))
        }
        .foregroundStyle(Color(red: 0.965, green: 0.969, blue: 0.973))
        .animation(.smooth(duration: 0.45), value: isComplete)
    }

    private var clothEffect: ClothEffect {
        ClothEffect.greyCloth
            .image("ClothTexture")
            .imageFit(.contain)
            .imageBrightness(0.9)
            .grid(cols: 54, rows: 44)
            .size(width: 3, height: 2.5)
            .pins(.none)
            .wind(0.18)
            .damping(0.994)
            .stiffness(shear: 0.94, bend: 0.62, iterations: 4)
            .grab(radius: 0.7, lift: 0.24, strength: 0.62)
            .roughness(0.9)
            .sheen(0.22, color: .white, roughness: 0.65)
            .camera(distance: 5.1, fov: 38)
            .rotation(x: 0.05, y: -0.1)
            .scale(1.23)
            .speed(4)
            .transparentBackground()
            .grain(nil)
    }

    private func moveCloth(
        translation: CGSize,
        in canvasSize: CGSize,
        clothSize: CGSize,
        carFrame: CGRect
    ) {
        if dragOrigin == nil {
            dragOrigin = clothPosition
        }
        guard let dragOrigin else { return }

        let marginX = clothSize.width * 0.2
        let marginY = clothSize.height * 0.2
        let proposed = CGPoint(
            x: dragOrigin.x + translation.width,
            y: dragOrigin.y + translation.height
        )
        let next = CGPoint(
            x: min(max(proposed.x, marginX), canvasSize.width - marginX),
            y: min(max(proposed.y, marginY), canvasSize.height - marginY)
        )
        clothPosition = next

        if carFrame.insetBy(dx: carFrame.width * 0.02, dy: carFrame.height * 0.08).contains(next) {
            recordWipe(at: next, in: carFrame)
        } else {
            isRecordingStroke = false
        }
    }

    private func recordWipe(at point: CGPoint, in carFrame: CGRect) {
        let normalized = CGPoint(
            x: min(max((point.x - carFrame.minX) / carFrame.width, 0), 1),
            y: min(max((point.y - carFrame.minY) / carFrame.height, 0), 1)
        )

        if !isRecordingStroke {
            strokes.append([])
            isRecordingStroke = true
        }

        if let last = strokes.indices.last {
            let previous = strokes[last].last
            let farEnough = previous.map {
                hypot($0.x - normalized.x, $0.y - normalized.y) > 0.012
            } ?? true
            if farEnough {
                strokes[last].append(normalized)
            }
        }

        let targetCells = cleaningTargetCells
        var cells = cleanedCells
        for row in 0..<gridRows {
            for column in 0..<gridColumns {
                let index = row * gridColumns + column
                guard targetCells.contains(index) else { continue }

                let center = CGPoint(
                    x: (CGFloat(column) + 0.5) / CGFloat(gridColumns),
                    y: (CGFloat(row) + 0.5) / CGFloat(gridRows)
                )
                let dx = (center.x - normalized.x) / 0.08
                let dy = (center.y - normalized.y) / 0.15
                if dx * dx + dy * dy <= 1 {
                    cells.insert(index)
                }
            }
        }
        cleanedCells = cells

        let cleanedTarget = cells.intersection(targetCells)
        let totalCoverage = Double(cleanedTarget.count) / Double(targetCells.count)
        let horizontalCoverage = (0..<3).map { section in
            let lowerColumn = section * gridColumns / 3
            let upperColumn = (section + 1) * gridColumns / 3
            let sectionTargets = targetCells.filter { index in
                let column = index % gridColumns
                return column >= lowerColumn && column < upperColumn
            }
            let sectionCleaned = cleanedTarget.intersection(sectionTargets)
            return Double(sectionCleaned.count) / Double(max(sectionTargets.count, 1))
        }

        if totalCoverage >= 0.94 && horizontalCoverage.allSatisfy({ $0 >= 0.88 }) {
            finishCleaning()
        }
    }

    private var cleaningTargetCells: Set<Int> {
        var result: Set<Int> = []

        for row in 0..<gridRows {
            for column in 0..<gridColumns {
                let x = (CGFloat(column) + 0.5) / CGFloat(gridColumns)
                let y = (CGFloat(row) + 0.5) / CGFloat(gridRows)

                let body = x >= 0.05 && x <= 0.96 && y >= 0.39 && y <= 0.76
                let roof = x >= 0.19 && x <= 0.73 && y >= 0.16 && y < 0.48
                let rear = x >= 0.05 && x < 0.27 && y >= 0.29 && y < 0.63
                let hood = x > 0.70 && x <= 0.96 && y >= 0.34 && y < 0.62
                let rearWheel = pow((x - 0.25) / 0.13, 2) + pow((y - 0.76) / 0.20, 2) <= 1
                let frontWheel = pow((x - 0.78) / 0.13, 2) + pow((y - 0.76) / 0.20, 2) <= 1

                if body || roof || rear || hood || rearWheel || frontWheel {
                    result.insert(row * gridColumns + column)
                }
            }
        }

        return result
    }

    private func finishCleaning() {
        guard !isComplete else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.7)) {
            isComplete = true
        }
    }
}

private struct CleanableCarView: View {
    let strokes: [[CGPoint]]
    let dirtyOpacity: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("CleanCar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width * 0.93)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.57)

                FlowBoardImage(.cleaningDirtyCar)
                    .scaledToFill()
                    .mask(WipeMask(strokes: strokes))
                    .opacity(dirtyOpacity)
                    .blendMode(.darken)
            }
        }
    }
}

private struct CleanCarCelebrationView: View {
    let reduceMotion: Bool

    @State private var glowExpanded = false
    @State private var shinePhase: CGFloat = -1.2
    @State private var starsVisible = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                carImage
                    .saturation(1.45)
                    .brightness(0.18)
                    .blur(radius: 16)
                    .blendMode(.screen)
                    .scaleEffect(reduceMotion ? 1.02 : (glowExpanded ? 1.035 : 1.01))
                    .opacity(reduceMotion ? 0.20 : (glowExpanded ? 0.30 : 0.12))

                carImage

                carImage
                    .saturation(0.2)
                    .brightness(0.55)
                    .blendMode(.screen)
                    .mask {
                        LinearGradient(
                            colors: [.clear, .clear, .white, .clear, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .rotationEffect(.degrees(-16))
                        .offset(x: shinePhase * geo.size.width)
                    }

                sparkle(size: 22, x: 0.11, y: 0.25, delay: 0)
                sparkle(size: 17, x: 0.75, y: 0.18, delay: 0.05)
                sparkle(size: 14, x: 0.93, y: 0.54, delay: 0.10)
                sparkle(size: 12, x: 0.30, y: 0.78, delay: 0.15)
            }
            .compositingGroup()
            .task {
                guard !reduceMotion else {
                    shinePhase = 1.2
                    starsVisible = true
                    return
                }

                withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                    glowExpanded = true
                }
                withAnimation(.easeInOut(duration: 1.45)) {
                    shinePhase = 1.2
                }
                starsVisible = true

                try? await Task.sleep(for: .milliseconds(1450))
                guard !Task.isCancelled else { return }
                starsVisible = false
            }
        }
        .accessibilityHidden(true)
    }

    private var carImage: some View {
        Image("CleanCar")
            .resizable()
            .scaledToFit()
    }

    private func sparkle(
        size: CGFloat,
        x: CGFloat,
        y: CGFloat,
        delay: Double
    ) -> some View {
        GeometryReader { geo in
            Image(systemName: "sparkle")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.80), radius: 8)
                .scaleEffect(starsVisible ? 1 : 0.92)
                .opacity(starsVisible ? 1 : 0)
                .position(x: geo.size.width * x, y: geo.size.height * y)
                .animation(
                    starsVisible
                        ? .spring(duration: 0.5, bounce: 0.2).delay(delay)
                        : .easeOut(duration: 0.2),
                    value: starsVisible
                )
        }
    }
}

private struct WipeMask: View {
    let strokes: [[CGPoint]]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            context.blendMode = .destinationOut

            let lineWidth = size.height * 0.30
            for stroke in strokes where !stroke.isEmpty {
                var path = Path()
                let first = CGPoint(x: stroke[0].x * size.width, y: stroke[0].y * size.height)
                path.move(to: first)
                for point in stroke.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                }
                context.stroke(
                    path,
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )

                for point in stroke {
                    let center = CGPoint(x: point.x * size.width, y: point.y * size.height)
                    let rect = CGRect(
                        x: center.x - lineWidth / 2,
                        y: center.y - lineWidth / 2,
                        width: lineWidth,
                        height: lineWidth
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
        }
    }
}
