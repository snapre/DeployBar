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

        UNUserNotificationCenter.current().delegate = notificationDelegate

        let settingsWindowController = SettingsWindowController(store: store, updateController: updateController)
        self.settingsWindowController = settingsWindowController
        menuBarController = MenuBarController(store: store, updateController: updateController) { tab in
            settingsWindowController.show(tab: tab)
        }
        store.prepareNotifications()
        store.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
            self?.menuBarController?.showPopover()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarController?.showPopover()
        return true
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
