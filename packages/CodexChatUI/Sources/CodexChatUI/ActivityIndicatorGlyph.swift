import SwiftUI

public struct ActivityIndicatorGlyph: View {
    public enum Size {
        case mini
        case small
        case regular

        fileprivate var pointSize: CGFloat {
            switch self {
            case .mini:
                10
            case .small:
                12
            case .regular:
                14
            }
        }
    }

    private let size: Size
    private let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    public init(size: Size = .small, color: Color = .secondary) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: size.pointSize, weight: .semibold))
            .foregroundStyle(color)
            .symbolRenderingMode(.hierarchical)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                reduceMotion ? nil : .linear(duration: 1.0).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = !reduceMotion
            }
            .onChange(of: reduceMotion) { shouldReduceMotion in
                isAnimating = !shouldReduceMotion
            }
    }
}
