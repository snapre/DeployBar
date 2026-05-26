import SwiftUI

struct AboutView: View {
    @ObservedObject var updateController: SoftwareUpdateController
    private let info = AppBuildInfo.current

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                updates
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

    private var updates: some View {
        VStack(spacing: 14) {
            Toggle(
                "Check for updates automatically",
                isOn: Binding(
                    get: { updateController.automaticUpdatesEnabled },
                    set: { updateController.setAutomaticUpdatesEnabled($0) }
                )
            )
            .toggleStyle(.checkbox)
            .disabled(!updateController.isAvailable)

            HStack(alignment: .firstTextBaseline) {
                Text("Update Channel")
                    .font(.system(size: 17, weight: .medium))

                Spacer()

                Picker(
                    "",
                    selection: Binding(
                        get: { updateController.channel },
                        set: { updateController.setChannel($0) }
                    )
                ) {
                    ForEach(SoftwareUpdateChannel.allCases) { channel in
                        Text(channel.title).tag(channel)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 172)
                .disabled(!updateController.isAvailable)
            }

            Text(updateController.channel.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(updateButtonTitle) {
                if updateController.status.isReadyToInstall {
                    updateController.restartAndInstallDownloadedUpdate()
                } else {
                    updateController.checkForUpdates()
                }
            }
            .controlSize(.large)
            .disabled(!updateController.isAvailable || (!updateController.status.isReadyToInstall && !updateController.canCheckForUpdates))

            if case let .unavailable(message) = updateController.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if case let .failed(message) = updateController.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 430)
        .padding(.top, 4)
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

    private var updateButtonTitle: String {
        switch updateController.status {
        case .checking:
            "Checking..."
        case .downloading:
            "Downloading..."
        case .downloaded:
            "Update Downloaded"
        case .readyToInstall:
            "Restart to Update"
        case .installing:
            "Installing..."
        case .unavailable, .idle, .failed:
            "Check for Updates..."
        }
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
