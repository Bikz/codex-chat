import SwiftUI

struct CodexMonochromeMark: View {
    let color: Color

    init(color: Color = .primary) {
        self.color = color
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let xOffset = (proxy.size.width - side) / 2
            let yOffset = (proxy.size.height - side) / 2

            let point: (CGFloat, CGFloat) -> CGPoint = { relativeX, relativeY in
                CGPoint(x: xOffset + side * relativeX, y: yOffset + side * relativeY)
            }

            ZStack {
                Path { path in
                    path.move(to: point(0.5, 0.03))
                    path.addLine(to: point(0.06, 0.90))
                    path.addLine(to: point(0.50, 0.67))
                    path.addLine(to: point(0.94, 0.90))
                    path.closeSubpath()

                    path.move(to: point(0.5, 0.25))
                    path.addLine(to: point(0.29, 0.66))
                    path.addLine(to: point(0.71, 0.66))
                    path.closeSubpath()
                }
                .fill(color, style: FillStyle(eoFill: true))

                Path { path in
                    path.move(to: point(0.31, 0.66))
                    path.addLine(to: point(0.50, 0.56))
                    path.addLine(to: point(0.69, 0.66))
                }
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: side * 0.10,
                        lineCap: .square,
                        lineJoin: .miter
                    )
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
