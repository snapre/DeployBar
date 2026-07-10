import SwiftUI

enum AppLogoVariant {
    case adaptive
    case light
    case dark
}

struct AppLogoView: View {
    var size: CGFloat = 28
    var statusColor: Color?
    var variant: AppLogoVariant = .adaptive

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            icon

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

    private var icon: some View {
        ZStack {
            statusStripes
                .frame(width: size * 0.78, height: size * 0.78)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.19, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                        .stroke(.black.opacity(0.12), lineWidth: max(0.5, size * 0.008))
                }

            Circle()
                .fill(badgeColor)
                .frame(width: size * 0.586, height: size * 0.586)

            ZStack {
                Circle()
                    .fill(markColor)

                DeployBarGlyph()
                    .stroke(
                        .black,
                        style: StrokeStyle(
                            lineWidth: max(1.6, size * 0.072),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .blendMode(.destinationOut)
                    .frame(width: size * 0.38, height: size * 0.38)
            }
            .frame(width: size * 0.43, height: size * 0.43)
            .compositingGroup()
        }
        .scaleEffect(1.0 / 0.78)
    }

    private var statusStripes: some View {
        VStack(spacing: 0) {
            ForEach(Self.statusColors.indices, id: \.self) { index in
                Rectangle()
                    .fill(Self.statusColors[index])
            }
        }
    }

    private var badgeColor: Color {
        Self.lightMark
    }

    private var markColor: Color {
        Self.darkMark
    }

    private static let darkMark = Color(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 20.0 / 255.0)
    private static let lightMark = Color(red: 244.0 / 255.0, green: 250.0 / 255.0, blue: 246.0 / 255.0)
    private static let statusColors = [
        Color(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0),
        Color(red: 0.0 / 255.0, green: 192.0 / 255.0, blue: 232.0 / 255.0),
        Color(red: 0.0 / 255.0, green: 136.0 / 255.0, blue: 255.0 / 255.0),
        Color(red: 255.0 / 255.0, green: 141.0 / 255.0, blue: 40.0 / 255.0),
        Color(red: 255.0 / 255.0, green: 56.0 / 255.0, blue: 60.0 / 255.0)
    ]
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
