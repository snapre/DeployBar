import AppKit
import DeployBarCore
import SwiftUI

enum DeploymentPopoverLayout {
    static let preferredWidth: CGFloat = 420
    static let listMinimumHeight: CGFloat = 520
    static let emptyHeight: CGFloat = 456
    static let headerHeight: CGFloat = 65
    static let footerHeight: CGFloat = 143
    static let issueStripHeight: CGFloat = 54
    static let contentHorizontalPadding: CGFloat = 12
    static let footerActionContentHorizontalPadding: CGFloat = 8
}

struct DeploymentPopoverView: View {
    static let preferredWidth: CGFloat = DeploymentPopoverLayout.preferredWidth

    @ObservedObject var store: DeploymentStore
    var usesScrollView = true
    var openSettings: (SettingsTab) -> Void = { _ in }
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.snapshots.isEmpty {
                PopoverEmptyState(
                    hasAccounts: store.hasConfiguredAccounts,
                    onOpenSettings: { openSettingsWindow(tab: .providers) },
                    onRefresh: { store.refresh(manual: true) }
                )
                .layoutPriority(1)
            } else {
                if usesScrollView {
                    ScrollView {
                        snapshotContent
                    }
                    .layoutPriority(1)
                } else {
                    snapshotContent
                        .layoutPriority(1)
                }
            }

            if !store.issues.isEmpty {
                Divider()
                issueStrip
            }

            footerActions
        }
        .frame(width: Self.preferredWidth)
        .frame(
            minHeight: store.snapshots.isEmpty ? DeploymentPopoverLayout.emptyHeight : DeploymentPopoverLayout.listMinimumHeight,
            maxHeight: .infinity,
            alignment: .top
        )
    }

    private var snapshotContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            focusSummary

            ForEach(sectionedSnapshots) { section in
                SnapshotSection(title: section.title, snapshots: section.snapshots) { snapshot in
                    open(snapshot)
                }
            }
        }
        .padding(DeploymentPopoverLayout.contentHorizontalPadding)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppLogoView(
                size: 28,
                statusColor: DeploymentSeverityStyle.color(for: store.globalSeverity)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("DeployBar")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var footerActions: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 0) {
                FooterActionRow(
                    title: store.isRefreshing ? "Refreshing..." : "Refresh",
                    systemImage: store.isRefreshing ? "arrow.triangle.2.circlepath.circle" : "arrow.clockwise",
                    shortcut: "⌘R",
                    accentColor: DeploymentSeverityStyle.color(for: store.globalSeverity),
                    isDisabled: store.isRefreshing
                ) {
                    store.refresh(manual: true)
                }
                FooterActionRow(title: "Settings...", systemImage: "gearshape", shortcut: "⌘,", accentColor: DeploymentSeverityStyle.color(for: store.globalSeverity)) {
                    openSettingsWindow(tab: .providers)
                }
                FooterActionRow(title: "About DeployBar", systemImage: "info.circle", accentColor: DeploymentSeverityStyle.color(for: store.globalSeverity)) {
                    openSettingsWindow(tab: .about)
                }
                FooterActionRow(title: "Quit", systemImage: "power", shortcut: "⌘Q", accentColor: DeploymentSeverityStyle.color(for: store.globalSeverity)) {
                    NSApp.terminate(nil)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
    }

    private var focusSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                if let rollupText {
                    Text(rollupText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                InlineCounter(title: "Active", value: inProgressCount, color: .blue)
                InlineCounter(title: "Waiting", value: waitingCount, color: .cyan)
                InlineCounter(title: "Attention", value: attentionTargetCount, color: attentionTargetCount > 0 ? .orange : .secondary)
                InlineCounter(title: "Issues", value: store.issues.count, color: DeploymentSeverityStyle.color(for: store.issueSeverity))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var subtitle: String {
        if store.isRefreshing {
            return "Refreshing..."
        }
        if let lastRefreshAt = store.lastRefreshAt {
            return "Updated \(DisplayTimestampFormatter.string(from: lastRefreshAt))"
        }
        return "Waiting for first refresh"
    }

    private var attentionCount: Int {
        attentionTargetCount + store.issues.count
    }

    private var attentionTargetCount: Int {
        focusedSnapshots.filter { $0.severity >= .warning }.count
    }

    private var inProgressCount: Int {
        focusedSnapshots.filter { $0.severity == .active }.count
    }

    private var waitingCount: Int {
        focusedSnapshots.filter { $0.severity == .pending }.count
    }

    private var headline: String {
        if store.issueSeverity >= .critical {
            return "\(attentionCount) critical"
        }
        if attentionCount > 0 {
            return "\(attentionCount) need attention"
        }
        if inProgressCount > 0 {
            return "\(inProgressCount) deploying"
        }
        if waitingCount > 0 {
            return "\(waitingCount) waiting"
        }
        return "All clear"
    }

    private var rollupText: String? {
        guard store.snapshots.count != focusedSnapshots.count else { return nil }
        if focusedSnapshots.isEmpty {
            return "History hidden"
        }
        return "Showing \(focusedSnapshots.count) watched services"
    }

    private var focusedSnapshots: [DeploymentSnapshot] {
        DeploymentSnapshotFocus.focused(store.snapshots)
    }

    private var sectionedSnapshots: [SnapshotGroup] {
        let attention = focusedSnapshots.filter { $0.severity >= .warning }
        let inProgress = focusedSnapshots.filter { $0.severity == .active || $0.severity == .pending }
        let recent = focusedSnapshots.filter(isLowEmphasisHistory)
        let healthy = focusedSnapshots.filter { $0.severity == .healthy && !isLowEmphasisHistory($0) }
        let visibleHealthy = Array(healthy.prefix(attention.isEmpty && inProgress.isEmpty && recent.isEmpty ? 6 : 2))
        let hiddenHealthyCount = healthy.count - visibleHealthy.count

        return [
            SnapshotGroup(title: "Needs attention", snapshots: attention),
            SnapshotGroup(title: "In progress", snapshots: inProgress),
            SnapshotGroup(title: "Recent", snapshots: recent),
            SnapshotGroup(title: hiddenHealthyCount > 0 ? "Healthy +\(hiddenHealthyCount) hidden" : "Healthy", snapshots: visibleHealthy)
        ].filter { !$0.snapshots.isEmpty }
    }

    private func isLowEmphasisHistory(_ snapshot: DeploymentSnapshot) -> Bool {
        !snapshot.isStale && snapshot.status == .canceled
    }

    private var issueStrip: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(store.issues.prefix(3)) { issue in
                HStack(spacing: 7) {
                    Image(systemName: issue.kind == .authentication ? "lock.trianglebadge.exclamationmark" : "exclamationmark.triangle")
                    Text(issue.message)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(issue.kind == .authentication ? .red : .secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open(_ snapshot: DeploymentSnapshot) {
        if let url = snapshot.dashboardURL ?? snapshot.deploymentURL {
            openURL(url)
        }
    }

    private func openSettingsWindow(tab: SettingsTab) {
        openSettings(tab)
    }

}

private struct InlineCounter: View {
    var title: String
    var value: Int
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(value)")
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.10), in: Capsule())
    }
}

private struct FooterActionRow: View {
    var title: String
    var systemImage: String
    var shortcut: String?
    var accentColor: Color
    var isDisabled = false
    var action: () -> Void

    @State private var isHovering = false

    init(
        title: String,
        systemImage: String,
        shortcut: String? = nil,
        accentColor: Color,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.accentColor = accentColor
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(foregroundColor)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(foregroundColor)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(shortcutColor)
                }
            }
            .padding(.horizontal, DeploymentPopoverLayout.footerActionContentHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .padding(.horizontal, DeploymentPopoverLayout.contentHorizontalPadding)
        .onHover { isHovering = $0 && !isDisabled }
    }

    private var backgroundColor: Color {
        isHovering ? accentColor.opacity(0.88) : .clear
    }

    private var foregroundColor: Color {
        if isDisabled {
            return .secondary.opacity(0.55)
        }
        return isHovering ? .white : .primary
    }

    private var shortcutColor: Color {
        if isDisabled {
            return .secondary.opacity(0.35)
        }
        return isHovering ? .white.opacity(0.85) : .secondary.opacity(0.65)
    }
}

private struct SnapshotGroup: Identifiable {
    var title: String
    var snapshots: [DeploymentSnapshot]

    var id: String { title }
}

private struct SnapshotSection: View {
    var title: String
    var snapshots: [DeploymentSnapshot]
    var onOpen: (DeploymentSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 10) {
                ForEach(snapshots) { snapshot in
                    Button {
                        onOpen(snapshot)
                    } label: {
                        DeploymentRowView(snapshot: snapshot)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PopoverEmptyState: View {
    var hasAccounts: Bool
    var onOpenSettings: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: hasAccounts ? "tray" : "key")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(hasAccounts ? "No deployments yet" : "Connect a provider")
                    .font(.headline)
                Text(hasAccounts ? "Refresh or adjust monitored targets." : "Add Vercel or Railway from Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Settings", action: onOpenSettings)
                Button("Refresh", action: onRefresh)
                    .disabled(!hasAccounts)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}
