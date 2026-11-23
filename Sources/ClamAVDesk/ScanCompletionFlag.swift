import SwiftUI

struct ScanCompletionFlag: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let reveal: Double

    var body: some View {
        Canvas { context, size in
            let stripe = size.height / 13
            let canton = CGSize(width: size.width * 0.4, height: stripe * 7)
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(Color(red: 0.98, green: 0.95, blue: 0.89)))
            for index in stride(from: 0, to: 13, by: 2) {
                let rect = CGRect(x: 0, y: Double(index) * stripe, width: size.width, height: stripe)
                context.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.75, green: 0.22, blue: 0.26),
                                      Color(red: 0.51, green: 0.12, blue: 0.20)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            }
            let field = CGRect(origin: .zero, size: canton)
            context.fill(Path(field), with: .color(Color(red: 0.09, green: 0.17, blue: 0.32)))
            let stepX = canton.width / 12
            let stepY = canton.height / 10
            for row in 0..<9 {
                let offset = row.isMultiple(of: 2) ? 1 : 2
                for column in 0..<(offset == 1 ? 6 : 5) {
                    let center = CGPoint(x: Double(column * 2 + offset) * stepX, y: Double(row + 1) * stepY)
                    let radius = stepY * 0.32
                    let star = Path { path in
                        for point in 0..<10 {
                            let angle = Double(point) * .pi / 5 - .pi / 2
                            let distance = point.isMultiple(of: 2) ? radius : radius * 0.39
                            let vertex = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                            if point == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
                        }
                        path.closeSubpath()
                    }
                    context.fill(star, with: .color(.white))
                }
            }
        }
        .aspectRatio(1.9, contentMode: .fit)
        .frame(maxWidth: 290)
        .clipShape(.rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.2)) }
        .modifier(FlagMaterialization(progress: reveal, showShimmer: !reduceMotion))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: reveal)
        .accessibilityLabel("Stylized American flag")
    }
}

private struct FlagMaterialization: AnimatableModifier {
    var progress: Double
    let showShimmer: Bool

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .overlay {
                if showShimmer && progress > 0 && progress < 1 {
                    Canvas { context, size in
                        let strength = sin(progress * .pi) * 0.65
                        for spark in 0..<56 {
                            let x = Double((spark * 73 + 19) % 101) / 101 * size.width
                            let offset = Double((spark * 37 + 11) % 101) / 101
                            let y = (offset + progress * 0.18).truncatingRemainder(dividingBy: 1) * size.height
                            let length = CGFloat(2 + spark % 5)
                            let rect = CGRect(x: x, y: y, width: 1.4, height: length)
                            let tint: Color = spark.isMultiple(of: 3) ? .cyan : .white
                            context.fill(Path(roundedRect: rect, cornerRadius: 0.7),
                                         with: .color(tint.opacity(strength)))
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}

struct FlagFireworks: View {
    let start: Date
    @State private var finished = false

    var body: some View {
        if !finished {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(start)
                    guard elapsed >= 0, elapsed < 30 else { return }
                    let colors: [Color] = [.red, .cyan, .white, .yellow]
                    let burstInterval = 0.62
                    let latest = Int(elapsed / burstInterval)
                    let scale = min(size.width / 460, 1)
                    for burst in max(0, latest - 2)...latest {
                        let age = (elapsed - Double(burst) * burstInterval) / 1.45
                        guard age < 1 else { continue }
                        let side = burst.isMultiple(of: 2) ? -1.0 : 1.0
                        let spread = Double((burst * 7) % 13) / 13
                        let x = size.width / 2 + side * (97 + 82 * spread) * scale
                        let y = size.height * (0.19 + Double((burst * 5) % 11) / 20)
                        for spark in 0..<18 {
                            let angle = Double(spark) * .pi / 9 + Double(burst) * 0.47
                            let speed = 29 + Double((spark * 13 + burst * 7) % 30)
                            let distance = speed * (1 - pow(1 - age, 2)) * scale
                            let dx = cos(angle) * distance
                            let dy = sin(angle) * distance
                            let gravity = age * age * 28
                            let trail = Path { path in
                                path.move(to: CGPoint(x: x + dx * 0.80, y: y + dy * 0.80 + gravity))
                                path.addLine(to: CGPoint(x: x + dx, y: y + dy + gravity))
                            }
                            context.stroke(trail, with: .color(colors[burst % colors.count].opacity((1 - age) * 0.85)),
                                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        }
                    }
                }
            }
            .task {
                let remaining = max(0, 30 - Date().timeIntervalSince(start))
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return }
                finished = true
            }
        }
    }
}
