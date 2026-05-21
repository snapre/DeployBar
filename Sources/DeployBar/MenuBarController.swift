import AppKit
import Combine
import DeployBarCore
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: DeploymentStore
    private var cancellable: AnyCancellable?

    init(store: DeploymentStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.behavior = .transient
        let initialSize = preferredPopoverSize(relativeTo: nil)
        popover.contentSize = initialSize
        let contentViewController = NSHostingController(rootView: DeploymentPopoverView(store: store))
        contentViewController.preferredContentSize = initialSize
        popover.contentViewController = contentViewController

        configureButton()
        cancellable = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateIcon()
            }
        }
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
        let screen = button?.window?.screen ?? NSScreen.main
        let visibleHeight = screen?.visibleFrame.height ?? 650
        let maxHeight = floor(visibleHeight)
        let contentHeight = estimatedPopoverContentHeight()
        return NSSize(width: DeploymentPopoverLayout.preferredWidth, height: min(maxHeight, contentHeight))
    }

    private func estimatedPopoverContentHeight() -> CGFloat {
        let focusedSnapshots = DeploymentSnapshotFocus.focused(store.snapshots)
        let issueHeight: CGFloat = store.issues.isEmpty ? 0 : DeploymentPopoverLayout.issueStripHeight

        guard !store.snapshots.isEmpty else {
            return DeploymentPopoverLayout.emptyHeight + issueHeight
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
            + issueHeight
            + DeploymentPopoverLayout.footerHeight

        return max(DeploymentPopoverLayout.listMinimumHeight, estimated)
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
