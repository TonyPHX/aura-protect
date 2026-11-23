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
        .mask(alignment: .leading) {
            GeometryReader { geometry in
                Rectangle().frame(width: geometry.size.width * reveal)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: reveal)
        .accessibilityLabel("Stylized American flag")
    }
}
