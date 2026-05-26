import SwiftUI

@main
struct DeployBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.store, updateController: appDelegate.updateController)
                .frame(width: 720, height: 520)
        }
    }
}
