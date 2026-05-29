import AppKit
import Combine
import DeployBarCore
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: DeploymentStore
    private let updateController: SoftwareUpdateController
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: DeploymentStore,
        updateController: SoftwareUpdateController,
        openSettings: @escaping (SettingsTab) -> Void
    ) {
        self.store = store
        self.updateController = updateController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.behavior = .transient
        let initialSize = preferredPopoverSize(relativeTo: nil)
        popover.contentSize = initialSize
        let contentViewController = NSHostingController(
            rootView: DeploymentPopoverView(store: store, updateController: updateController) { [weak self] tab in
                self?.popover.performClose(nil)
                openSettings(tab)
            }
        )
        contentViewController.preferredContentSize = initialSize
        popover.contentViewController = contentViewController

        configureButton()
        store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateIcon()
            }
        }
        .store(in: &cancellables)
        updateController.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.applyPreferredPopoverSize(relativeTo: self?.statusItem.button)
            }
        }
        .store(in: &cancellables)
        updateIcon()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.imagePosition = .imageLeading
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = StatusIconRenderer.image(for: store.globalSeverity, isRefreshing: store.isRefreshing)
        button.toolTip = "DeployBar - \(store.globalSeverity.displayName)"
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            applyPreferredPopoverSize(relativeTo: sender)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func applyPreferredPopoverSize(relativeTo button: NSStatusBarButton?) {
        let size = preferredPopoverSize(relativeTo: button)
        popover.contentSize = size
        popover.contentViewController?.preferredContentSize = size
    }

    private func preferredPopoverSize(relativeTo button: NSStatusBarButton?) -> NSSize {
        let contentHeight = estimatedPopoverContentHeight()
        let maxHeight = availablePopoverContentHeight(relativeTo: button)
        return NSSize(width: DeploymentPopoverLayout.preferredWidth, height: min(maxHeight, contentHeight))
    }

    private func availablePopoverContentHeight(relativeTo button: NSStatusBarButton?) -> CGFloat {
        let screen = button?.window?.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return 650 - DeploymentPopoverLayout.popoverChromeHeightAllowance
        }

        let availableOuterHeight: CGFloat
        if let buttonWindow = button?.window {
            let anchorY = min(buttonWindow.frame.minY, visibleFrame.maxY)
            availableOuterHeight = anchorY - visibleFrame.minY
        } else {
            availableOuterHeight = visibleFrame.height
        }

        return max(
            DeploymentPopoverLayout.minimumUsableContentHeight,
            floor(availableOuterHeight - DeploymentPopoverLayout.popoverChromeHeightAllowance)
        )
    }

    private func estimatedPopoverContentHeight() -> CGFloat {
        let focusedSnapshots = DeploymentSnapshotFocus.focused(store.snapshots)
        let issueHeight: CGFloat = store.issues.isEmpty ? 0 : DeploymentPopoverLayout.issueStripHeight

        guard !store.snapshots.isEmpty else {
            return DeploymentPopoverLayout.emptyHeight + issueHeight + updateNoticeHeight
        }

        let sectionCount = CGFloat(sectionCount(for: focusedSnapshots))
        let rowCount = CGFloat(visibleRowCount(for: focusedSnapshots))
        let scrollPadding: CGFloat = 24
        let summaryHeight: CGFloat = 104
        let sectionTitleHeight: CGFloat = sectionCount * 28
        let rowHeight: CGFloat = rowCount * 106
        let scrollSpacing: CGFloat = sectionCount > 0 ? max(0, sectionCount - 1) * 6 : 0
        let estimated = DeploymentPopoverLayout.headerHeight
            + scrollPadding
            + summaryHeight
            + sectionTitleHeight
            + rowHeight
            + scrollSpacing
            + updateNoticeHeight
            + issueHeight
            + DeploymentPopoverLayout.footerHeight

        return max(DeploymentPopoverLayout.listMinimumHeight, estimated)
    }

    private var updateNoticeHeight: CGFloat {
        updateController.status.isReadyToInstall ? 74 : 0
    }

    private func visibleRowCount(for focusedSnapshots: [DeploymentSnapshot]) -> Int {
        let attention = focusedSnapshots.filter { $0.severity >= .warning }
        let inProgress = focusedSnapshots.filter { $0.severity == .active || $0.severity == .pending }
        let recent = focusedSnapshots.filter(isLowEmphasisHistory)
        let healthy = focusedSnapshots.filter { $0.severity == .healthy && !isLowEmphasisHistory($0) }
        let visibleHealthy = min(healthy.count, attention.isEmpty && inProgress.isEmpty && recent.isEmpty ? 6 : 2)
        return attention.count + inProgress.count + recent.count + visibleHealthy
    }

    private func sectionCount(for focusedSnapshots: [DeploymentSnapshot]) -> Int {
        let attention = focusedSnapshots.contains { $0.severity >= .warning }
        let inProgress = focusedSnapshots.contains { $0.severity == .active || $0.severity == .pending }
        let recent = focusedSnapshots.contains(where: isLowEmphasisHistory)
        let healthy = focusedSnapshots.contains { $0.severity == .healthy && !isLowEmphasisHistory($0) }
        return [attention, inProgress, recent, healthy].filter { $0 }.count
    }

    private func isLowEmphasisHistory(_ snapshot: DeploymentSnapshot) -> Bool {
        !snapshot.isStale && snapshot.status == .canceled
    }
}
