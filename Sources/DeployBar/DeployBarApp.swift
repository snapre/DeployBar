import SwiftUI

@main
struct DeployBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.store)
                .frame(width: 720, height: 520)
        }
    }
}
