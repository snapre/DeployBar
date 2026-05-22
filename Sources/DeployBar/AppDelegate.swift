import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DeploymentStore()
    private var menuBarController: MenuBarController?
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

        menuBarController = MenuBarController(store: store)
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
