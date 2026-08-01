import AppKit
import DeployBarCore
import SwiftUI

struct DeploymentRowView: View {
    var snapshot: DeploymentSnapshot

    var body: some View {
        HStack(spacing: 0) {
            statusRail

            HStack(alignment: .top, spacing: 12) {
                ProviderLogoView(provider: snapshot.provider, size: 28)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 10) {
                        titleBlock
                            .layoutPriority(1)

                        Spacer(minLength: 10)

                        StatusPill(status: snapshot.status, severity: snapshot.severity, isStale: snapshot.isStale)
                            .fixedSize()
                    }

                    timingLine
                    sourceLine
                    commitLine

                    if let errorMessage = snapshot.errorMessage, snapshot.severity >= .critical {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text(errorMessage)
                                .lineLimit(1)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 13)
        }
        .frame(maxWidth: .infinity, minHeight: minimumRowHeight, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusRail: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 3)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 10)
            .padding(.leading, 4)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            if snapshot.provider != .railway, let serviceName = snapshot.serviceName {
                Text(serviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var title: String {
        snapshot.provider == .railway
            ? snapshot.projectAndServiceDisplayName
            : snapshot.projectName
    }

    private var timingLine: some View {
        HStack(spacing: 10) {
            Text(timeSummary)
                .foregroundStyle(.tertiary)

            if let environmentName = snapshot.environmentName {
                InlineMeta(systemImage: "server.rack", text: environmentName)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    @ViewBuilder
    private var sourceLine: some View {
        if hasSourceMeta {
            HStack(spacing: 10) {
                if let branch = snapshot.branch {
                    InlineMeta(systemImage: "arrow.triangle.branch", text: branch)
                }
                if let commitSha = snapshot.commitSha {
                    Text(String(commitSha.prefix(7)))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if snapshot.dashboardURL != nil || snapshot.deploymentURL != nil {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var commitLine: some View {
        if let commitSummary {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .foregroundStyle(.tertiary)
                Text(commitSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption2)
        }
    }

    private var hasSourceMeta: Bool {
        snapshot.branch != nil
            || snapshot.commitSha != nil
            || snapshot.dashboardURL != nil
            || snapshot.deploymentURL != nil
    }

    private var color: Color {
        if usesLowEmphasisStatusStyle {
            return .secondary
        }
        return DeploymentSeverityStyle.color(for: snapshot.severity)
    }

    private var minimumRowHeight: CGFloat {
        snapshot.errorMessage != nil && snapshot.severity >= .critical ? 122 : 96
    }

    private var timeSummary: String {
        if snapshot.isStale {
            return "stale \(DisplayTimestampFormatter.string(from: snapshot.lastUpdatedAt))"
        }
        if let displayDate = snapshot.finishedAt ?? snapshot.createdAt ?? snapshot.startedAt {
            let time = DisplayTimestampFormatter.string(from: displayDate)
            if let duration = snapshot.duration {
                return "\(time) / \(compactDuration(duration))"
            }
            return time
        }
        if let duration = snapshot.duration {
            return compactDuration(duration)
        }
        return "Updated \(DisplayTimestampFormatter.string(from: snapshot.lastUpdatedAt))"
    }

    private func compactDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private var commitSummary: String? {
        guard let message = snapshot.commitMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return nil
        }

        let title = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
        guard !title.isEmpty else { return nil }

        if let actor = snapshot.actor?.trimmingCharacters(in: .whitespacesAndNewlines), !actor.isEmpty {
            return "\(title) by \(actor)"
        }
        return title
    }

    private var rowBackground: Color {
        if usesLowEmphasisStatusStyle {
            return Color(nsColor: .controlBackgroundColor).opacity(0.74)
        }

        switch snapshot.severity {
        case .healthy:
            return Color(nsColor: .controlBackgroundColor).opacity(0.74)
        case .pending, .active:
            return .blue.opacity(0.07)
        case .warning:
            return .orange.opacity(0.09)
        case .critical:
            return .red.opacity(0.09)
        }
    }

    private var usesLowEmphasisStatusStyle: Bool {
        !snapshot.isStale && snapshot.status == .canceled
    }
}

private struct InlineMeta: View {
    var systemImage: String
    var text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct StatusPill: View {
    var status: DeploymentStatus
    var severity: DeploymentSeverity
    var isStale: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(isStale ? "stale" : status.rawValue)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
    }

    private var color: Color {
        if !isStale && status == .canceled {
            return .secondary
        }
        return DeploymentSeverityStyle.color(for: severity)
    }
}
