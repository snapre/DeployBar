import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private var hasCenteredWindow = false

    init(store: DeploymentStore, updateController: SoftwareUpdateController) {
        let contentViewController = NSHostingController(
            rootView: SettingsView(store: store, updateController: updateController)
                .frame(width: 720, height: 520)
        )
        let window = NSWindow(contentViewController: contentViewController)
        window.title = "DeployBar Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 640, height: 460)
        window.isReleasedWhenClosed = false

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show(tab: SettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey)

        if !hasCenteredWindow {
            window?.center()
            hasCenteredWindow = true
        }

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
