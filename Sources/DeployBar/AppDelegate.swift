import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DeploymentStore()
    let updateController = SoftwareUpdateController()
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private let notificationDelegate = NotificationCenterDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if WebsiteScreenshotRenderer.renderIfRequested() {
            return
        }
        #endif

        NSApp.setActivationPolicy(.accessory)

        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = notificationDelegate
        Task.detached {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }

        let settingsWindowController = SettingsWindowController(store: store, updateController: updateController)
        self.settingsWindowController = settingsWindowController
        menuBarController = MenuBarController(store: store, updateController: updateController) { tab in
            settingsWindowController.show(tab: tab)
        }
        store.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

}

private final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
