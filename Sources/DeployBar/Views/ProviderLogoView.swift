import AppKit
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
        if let assetName = provider.logoAssetName,
           let image = ProviderLogoAssets.image(named: assetName)
        {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(foregroundColor)
        } else {
            fallbackLogo
        }
    }

    @ViewBuilder
    private var fallbackLogo: some View {
        switch provider {
        case .mock:
            Image(systemName: "square.grid.2x2")
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(foregroundColor)
        case .vercel:
            Image(systemName: "triangle.fill")
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(foregroundColor)
        case .railway:
            Image(systemName: "tram.fill")
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(foregroundColor)
        case .netlify:
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(foregroundColor)
        case .render:
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: size * 0.56, weight: .semibold))
                .foregroundStyle(foregroundColor)
        case .cloudflarePages, .cloudflareWorkers:
            Image(systemName: "cloud.fill")
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(foregroundColor)
        case .digitalOcean:
            Image(systemName: "drop.fill")
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(foregroundColor)
        case .heroku:
            Image(systemName: "h.square.fill")
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(foregroundColor)
        case .flyio:
            Image(systemName: "balloon.fill")
                .font(.system(size: size * 0.56, weight: .semibold))
                .foregroundStyle(foregroundColor)
        case .github:
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(foregroundColor)
        case .gitlab:
            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.56, weight: .semibold))
                .foregroundStyle(foregroundColor)
        }
    }

    private var backgroundColor: Color {
        switch provider {
        case .mock:
            return .secondary.opacity(0.12)
        case .vercel:
            return .black
        case .railway:
            return .black
        case .netlify:
            return Color(red: 0.00, green: 0.68, blue: 0.62)
        case .render:
            return Color(red: 0.27, green: 0.89, blue: 0.72)
        case .cloudflarePages, .cloudflareWorkers:
            return Color(red: 0.95, green: 0.50, blue: 0.13)
        case .digitalOcean:
            return Color(red: 0.00, green: 0.50, blue: 1.00)
        case .heroku:
            return Color(red: 0.26, green: 0.00, blue: 0.60)
        case .flyio:
            return Color(red: 0.49, green: 0.30, blue: 1.00)
        case .github:
            return colorScheme == .dark ? Color(nsColor: .controlBackgroundColor) : .black
        case .gitlab:
            return Color(red: 0.99, green: 0.43, blue: 0.15)
        }
    }

    private var foregroundColor: Color {
        switch provider {
        case .mock:
            return .secondary
        case .vercel, .railway, .netlify, .render, .cloudflarePages, .cloudflareWorkers, .digitalOcean, .heroku, .flyio, .gitlab:
            return .white
        case .github:
            return colorScheme == .dark ? .primary : .white
        }
    }
}

@MainActor
private enum ProviderLogoAssets {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(named name: String) -> NSImage? {
        let key = name as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let url = resourceURL(named: name),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.isTemplate = true
        cache.setObject(image, forKey: key)
        return image
    }

    private static func resourceURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "svg")
            ?? Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "ProviderLogos")
            ?? Bundle.module.url(forResource: name, withExtension: "svg")
            ?? Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "ProviderLogos")
    }
}

private extension ProviderID {
    var logoAssetName: String? {
        switch self {
        case .mock:
            return nil
        case .vercel:
            return "vercel"
        case .railway:
            return "railway"
        case .netlify:
            return "netlify"
        case .render:
            return "render"
        case .cloudflarePages:
            return "cloudflare-pages"
        case .cloudflareWorkers:
            return "cloudflare-workers"
        case .digitalOcean:
            return "digital-ocean"
        case .heroku:
            return "heroku"
        case .flyio:
            return "flyio"
        case .github:
            return "github"
        case .gitlab:
            return "gitlab"
        }
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
