import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var store: DeploymentStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Global status")
                    Text(store.globalSeverity.displayName)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Snapshots")
                    Text("\(store.snapshots.count)")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Issues")
                    Text("\(store.issues.count)")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Keychain service")
                    Text(SecureTokenStore.service)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Notifications")
                    notificationStatus
                }
            }

            if let errorMessage = store.notificationAuthorization.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !store.issues.isEmpty {
                Divider()
                List(store.issues) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.kind.rawValue)
                            .font(.body.weight(.medium))
                        Text(issue.message)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer()
        }
        .onAppear {
            store.refreshNotificationAuthorizationStatus()
        }
    }

    @ViewBuilder
    private var notificationStatus: some View {
        HStack(spacing: 8) {
            Text(store.notificationAuthorization.state.displayName)
                .foregroundStyle(.secondary)

            switch store.notificationAuthorization.state {
            case .notDetermined:
                Button {
                    store.requestNotificationAuthorization()
                } label: {
                    Label("Enable", systemImage: "bell.badge")
                }
                .controlSize(.small)
            case .denied:
                Button {
                    openNotificationSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
                .controlSize(.small)
            case .authorized, .provisional, .ephemeral:
                Button {
                    store.sendTestNotification()
                } label: {
                    Label("Test", systemImage: "bell")
                }
                .controlSize(.small)
            case .unknown:
                EmptyView()
            }
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        openURL(url)
    }
}

private extension NotificationAuthorizationState {
    var displayName: String {
        switch self {
        case .notDetermined:
            "Not requested"
        case .denied:
            "Denied"
        case .authorized:
            "Allowed"
        case .provisional:
            "Provisional"
        case .ephemeral:
            "Ephemeral"
        case .unknown:
            "Unknown"
        }
    }
}
