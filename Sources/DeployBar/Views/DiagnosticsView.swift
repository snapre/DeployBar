import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var store: DeploymentStore

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
    }
}
