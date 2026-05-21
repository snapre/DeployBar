import SwiftUI

struct AboutView: View {
    private let info = AppBuildInfo.current

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                links
                Divider()
                privacy
                Spacer(minLength: 0)
                copyright
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 42)
            .padding(.horizontal, 44)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            AppLogoView(size: 96)
                .padding(.bottom, 10)

            Text(info.name)
                .font(.system(size: 28, weight: .semibold))

            Text("Version \(info.version) (\(info.build))")
                .font(.title3)
                .foregroundStyle(.secondary)

            if let builtAt = info.builtAt {
                Text("Built \(builtAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Local-first deployment status for the macOS menu bar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 16) {
            AboutLink(systemImage: "shippingbox", title: "Native Swift app", value: "No Electron shell. No backend service.")
            AboutLink(systemImage: "lock.shield", title: "Local secrets", value: "Tokens stay in Keychain.")
            AboutLink(systemImage: "heart.text.square", title: "Inspired by CodexBar", url: URL(string: "https://github.com/steipete/CodexBar"))
        }
        .frame(maxWidth: 360)
        .padding(.top, 22)
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Privacy", systemImage: "hand.raised")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("DeployBar stores non-secret settings locally and never writes API tokens to JSON settings, logs, or diagnostics.")
                Text("Keychain service: \(SecureTokenStore.service)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var copyright: some View {
        Text("© 2026 DeployBar contributors. MIT License.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
    }
}

private struct AboutLink: View {
    var systemImage: String
    var title: String
    var value: String?
    var url: URL?

    @Environment(\.openURL) private var openURL

    init(systemImage: String, title: String, value: String) {
        self.systemImage = systemImage
        self.title = title
        self.value = value
        self.url = nil
    }

    init(systemImage: String, title: String, url: URL?) {
        self.systemImage = systemImage
        self.title = title
        self.value = nil
        self.url = url
    }

    var body: some View {
        Button {
            if let url {
                openURL(url)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .frame(width: 28)
                    .foregroundStyle(url == nil ? Color.secondary : Color.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(url == nil ? Color.primary : Color.blue)

                    if let value {
                        Text(value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }
}

private struct AppBuildInfo {
    var name: String
    var version: String
    var build: String
    var builtAt: Date?

    static var current: AppBuildInfo {
        let bundle = Bundle.main
        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "DeployBar"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let builtAt = bundle.executableURL.flatMap { executableURL in
            try? FileManager.default
                .attributesOfItem(atPath: executableURL.path)[.modificationDate] as? Date
        }

        return AppBuildInfo(name: name, version: version, build: build, builtAt: builtAt)
    }
}
