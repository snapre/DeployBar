import SwiftUI

struct AppLogoView: View {
    var size: CGFloat = 28
    var statusColor: Color?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(.primary)

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
