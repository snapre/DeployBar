import DeployBarCore
import SwiftUI

enum SettingsTab: String {
    case providers
    case diagnostics
    case about

    static let storageKey = "settings.selectedTab"
}

struct SettingsView: View {
    @ObservedObject var store: DeploymentStore
    @ObservedObject var updateController: SoftwareUpdateController
    @AppStorage(SettingsTab.storageKey) private var selectedTab = SettingsTab.providers.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            ProviderSettingsView(store: store)
                .tabItem {
                    Label("Providers", systemImage: "cloud")
                }
                .tag(SettingsTab.providers.rawValue)

            DiagnosticsView(store: store)
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
                .tag(SettingsTab.diagnostics.rawValue)

            AboutView(updateController: updateController)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about.rawValue)
        }
        .padding(16)
    }
}
