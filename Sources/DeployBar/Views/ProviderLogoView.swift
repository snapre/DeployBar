import DeployBarCore
import SwiftUI

struct ProviderLogoView: View {
    var provider: ProviderID
    var size: CGFloat = 24
    var badge: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if badge {
                ZStack {
                    RoundedRectangle(cornerRadius: max(5, size * 0.2))
                        .fill(backgroundColor)
                    logo
                        .frame(width: size * 0.66, height: size * 0.66)
                }
                .frame(width: size, height: size)
            } else {
                logo
                    .frame(width: size, height: size)
            }
        }
        .accessibilityLabel(provider.displayName)
    }

    @ViewBuilder
    private var logo: some View {
        switch provider {
        case .mock:
            Image(systemName: "square.grid.2x2")
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(foregroundColor)
        case .vercel:
            VercelTriangle()
                .fill(foregroundColor)
                .aspectRatio(1.05, contentMode: .fit)
                .padding(size * 0.08)
        case .railway:
            Image(systemName: "tram.fill")
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(foregroundColor)
        }
    }

    private var backgroundColor: Color {
        switch provider {
        case .mock:
            return .secondary.opacity(0.12)
        case .vercel:
            return colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
        case .railway:
            return .indigo.opacity(0.14)
        }
    }

    private var foregroundColor: Color {
        switch provider {
        case .mock:
            return .secondary
        case .vercel:
            return .primary
        case .railway:
            return .indigo
        }
    }
}

private struct VercelTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct ProviderPickerLabel: View {
    var provider: ProviderID
    var title: String

    var body: some View {
        HStack(spacing: 6) {
            ProviderLogoView(provider: provider, size: 15, badge: false)
            Text(title)
        }
    }
}
