import DeployBarCore
import Foundation

enum DeploymentSnapshotFocus {
    static func focused(_ snapshots: [DeploymentSnapshot]) -> [DeploymentSnapshot] {
        var snapshotsByTarget: [String: DeploymentSnapshot] = [:]

        for snapshot in snapshots {
            let key = focusKey(for: snapshot)
            guard let existing = snapshotsByTarget[key] else {
                snapshotsByTarget[key] = snapshot
                continue
            }

            if shouldReplace(existing: existing, with: snapshot) {
                snapshotsByTarget[key] = snapshot
            }
        }

        return snapshotsByTarget.values
            .filter { !isLowSignalHistory($0) }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                return sortDate(for: lhs) > sortDate(for: rhs)
            }
    }

    private static func focusKey(for snapshot: DeploymentSnapshot) -> String {
        if snapshot.provider == .railway {
            return [
                snapshot.provider.rawValue,
                snapshot.projectName,
                snapshot.serviceName ?? "",
                snapshot.environmentName ?? ""
            ]
            .map { $0.lowercased() }
            .joined(separator: "|")
        }

        return [
            snapshot.provider.rawValue,
            snapshot.projectName,
            snapshot.serviceName ?? "",
            snapshot.environmentName ?? "",
            snapshot.branch ?? ""
        ]
        .map { $0.lowercased() }
        .joined(separator: "|")
    }

    private static func sortDate(for snapshot: DeploymentSnapshot) -> Date {
        snapshot.createdAt ?? snapshot.finishedAt ?? snapshot.startedAt ?? snapshot.lastUpdatedAt
    }

    private static func shouldReplace(existing: DeploymentSnapshot, with candidate: DeploymentSnapshot) -> Bool {
        if isLowSignalHistory(candidate), !isLowSignalHistory(existing) {
            return false
        }
        if !isLowSignalHistory(candidate), isLowSignalHistory(existing) {
            return true
        }
        let existingPriority = selectionPriority(for: existing)
        let candidatePriority = selectionPriority(for: candidate)
        if existingPriority != candidatePriority {
            return candidatePriority > existingPriority
        }
        return sortDate(for: candidate) > sortDate(for: existing)
    }

    private static func isLowSignalHistory(_ snapshot: DeploymentSnapshot) -> Bool {
        snapshot.provider == .railway && snapshot.status == .removed
    }

    private static func selectionPriority(for snapshot: DeploymentSnapshot) -> Int {
        switch snapshot.status {
        case .building, .deploying:
            return 90
        case .queued, .waiting, .initializing:
            return 80
        case .failed, .crashed, .error:
            return 70
        case .ready, .success:
            return 50
        case .canceled:
            return 40
        case .sleeping:
            return 30
        case .skipped:
            return snapshot.provider == .railway ? 10 : 40
        case .removed:
            return 0
        case .unknown:
            return 20
        }
    }
}
