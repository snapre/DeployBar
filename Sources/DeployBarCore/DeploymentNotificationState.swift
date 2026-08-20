import Foundation

public struct DeploymentNotificationState: Equatable, Sendable {
    public let statusesByID: [String: DeploymentStatus]
    public let scopeKeys: Set<String>

    public init(snapshots: [DeploymentSnapshot] = []) {
        let focusedSnapshots = DeploymentSnapshotFocus.focused(snapshots)
        self.statusesByID = Dictionary(uniqueKeysWithValues: focusedSnapshots.map { ($0.id, $0.status) })
        self.scopeKeys = Set(focusedSnapshots.map(DeploymentSnapshotFocus.scopeKey))
    }

    public func candidates(from snapshots: [DeploymentSnapshot]) -> [DeploymentSnapshot] {
        guard !scopeKeys.isEmpty else { return [] }

        return DeploymentSnapshotFocus.focused(snapshots).filter { snapshot in
            scopeKeys.contains(DeploymentSnapshotFocus.scopeKey(for: snapshot))
        }
    }
}
