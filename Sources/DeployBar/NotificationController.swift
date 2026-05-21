import DeployBarCore
import UserNotifications

struct NotificationController {
    func notifyTransitions(oldStatuses: [String: DeploymentStatus], snapshots: [DeploymentSnapshot]) {
        guard !oldStatuses.isEmpty else { return }

        for snapshot in snapshots {
            guard let oldStatus = oldStatuses[snapshot.id], oldStatus != snapshot.status else { continue }
            guard shouldNotify(snapshot: snapshot) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(snapshot.projectName) \(notificationTitle(for: snapshot.status))"
            content.body = snapshot.errorMessage ?? detail(for: snapshot)
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "deploybar.\(snapshot.id).\(snapshot.status.rawValue)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func shouldNotify(snapshot: DeploymentSnapshot) -> Bool {
        if snapshot.provider == .railway && snapshot.status == .removed {
            return false
        }

        switch snapshot.status {
        case .ready, .success, .failed, .error, .crashed, .canceled, .removed:
            return true
        default:
            return false
        }
    }

    private func notificationTitle(for status: DeploymentStatus) -> String {
        switch status {
        case .ready, .success: "deployed"
        case .failed, .error, .crashed: "failed"
        case .canceled: "was canceled"
        case .removed: "was removed"
        default: "changed"
        }
    }

    private func detail(for snapshot: DeploymentSnapshot) -> String {
        [snapshot.environmentName, snapshot.branch, snapshot.commitSha.map { String($0.prefix(7)) }]
            .compactMap { $0 }
            .joined(separator: " • ")
    }
}
