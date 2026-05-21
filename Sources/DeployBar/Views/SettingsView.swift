import DeployBarCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: DeploymentStore

    var body: some View {
        TabView {
            ProviderSettingsView(store: store)
                .tabItem {
                    Label("Providers", systemImage: "cloud")
                }

            DiagnosticsView(store: store)
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
        }
        .padding(16)
    }
}
