import SwiftUI

enum AppLogoVariant {
    case adaptive
    case light
    case dark
}

struct AppLogoView: View {
    @Environment(\.colorScheme) private var colorScheme

    var size: CGFloat = 28
    var statusColor: Color?
    var variant: AppLogoVariant = .adaptive

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(markColor)

                DeployBarGlyph()
                    .stroke(
                        .black,
                        style: StrokeStyle(
                            lineWidth: max(2, size * 0.095),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .blendMode(.destinationOut)
                    .frame(width: size * 0.62, height: size * 0.62)
            }
            .compositingGroup()

            if let statusColor {
                Circle()
                    .fill(statusColor)
                    .frame(width: max(6, size * 0.23), height: max(6, size * 0.23))
                    .overlay {
                        Circle()
                            .stroke(.background, lineWidth: max(1.5, size * 0.055))
                    }
                    .offset(x: size * 0.04, y: size * 0.04)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("DeployBar")
    }

    private var markColor: Color {
        switch variant {
        case .adaptive:
            colorScheme == .dark ? Self.lightMark : Self.darkMark
        case .light:
            Self.lightMark
        case .dark:
            Self.darkMark
        }
    }

    private static let darkMark = Color(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 20.0 / 255.0)
    private static let lightMark = Color(red: 244.0 / 255.0, green: 250.0 / 255.0, blue: 246.0 / 255.0)
}

private struct DeployBarGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(x: 0.08, y: 0.65, in: rect))
        path.addLine(to: point(x: 0.29, y: 0.34, in: rect))
        path.addLine(to: point(x: 0.50, y: 0.65, in: rect))
        path.addLine(to: point(x: 0.74, y: 0.29, in: rect))
        path.addLine(to: point(x: 0.92, y: 0.29, in: rect))
        return path
    }

    private func point(x: CGFloat, y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
}
