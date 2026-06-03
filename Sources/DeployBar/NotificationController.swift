import DeployBarCore
import Foundation
import OSLog
import UserNotifications

struct NotificationAuthorizationSnapshot: Equatable, Sendable {
    var state: NotificationAuthorizationState
    var errorMessage: String?
}

enum NotificationAuthorizationState: String, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unknown
        }
    }
}

struct NotificationController {
    private static let logger = Logger(subsystem: "com.deploybar.app", category: "notifications")

    func authorizationSnapshot() async -> NotificationAuthorizationSnapshot {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationAuthorizationSnapshot(state: NotificationAuthorizationState(settings.authorizationStatus))
    }

    func requestAuthorization() async -> NotificationAuthorizationSnapshot {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            return await authorizationSnapshot()
        } catch {
            Self.logger.error("Notification authorization request failed: \(error.localizedDescription, privacy: .public)")
            var snapshot = await authorizationSnapshot()
            snapshot.errorMessage = error.localizedDescription
            return snapshot
        }
    }

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "DeployBar notifications are working"
        content.body = "macOS can show DeployBar alerts."
        content.sound = .default
        content.threadIdentifier = "deploybar"

        let request = UNNotificationRequest(
            identifier: "deploybar.test.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        add(request: request)
    }

    func notifyTransitions(oldStatuses: [String: DeploymentStatus], snapshots: [DeploymentSnapshot]) {
        guard !oldStatuses.isEmpty else { return }

        for snapshot in snapshots {
            guard let event = notificationEvent(oldStatus: oldStatuses[snapshot.id], snapshot: snapshot) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(snapshot.projectName) \(event.titleSuffix)"
            content.body = snapshot.errorMessage ?? detail(for: snapshot)
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "deploybar.\(snapshot.id).\(event.identifierSuffix)",
                content: content,
                trigger: nil
            )
            add(request: request)
        }
    }

    private func add(request: UNNotificationRequest) {
        let identifier = request.identifier
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
            } else {
                Self.logger.info("Notification submitted: \(identifier, privacy: .public)")
            }
        }
    }

    private func notificationEvent(oldStatus: DeploymentStatus?, snapshot: DeploymentSnapshot) -> NotificationEvent? {
        if snapshot.provider == .railway && snapshot.status == .removed {
            return nil
        }

        if let oldStatus {
            guard oldStatus != snapshot.status else { return nil }
            if let terminalEvent = NotificationEvent(terminalStatus: snapshot.status) {
                return terminalEvent
            }
            if !oldStatus.isDeploymentInFlight && snapshot.status.isDeploymentInFlight {
                return .started
            }
            return nil
        }

        if snapshot.status.isDeploymentInFlight {
            return .started
        }
        return NotificationEvent(terminalStatus: snapshot.status)
    }

    private func detail(for snapshot: DeploymentSnapshot) -> String {
        [snapshot.environmentName, snapshot.branch, snapshot.commitSha.map { String($0.prefix(7)) }]
            .compactMap { $0 }
            .joined(separator: " • ")
    }
}

private enum NotificationEvent {
    case started
    case completed
    case failed
    case canceled
    case removed

    init?(terminalStatus status: DeploymentStatus) {
        switch status {
        case .ready, .success:
            self = .completed
        case .failed, .error, .crashed:
            self = .failed
        case .canceled:
            self = .canceled
        case .removed:
            self = .removed
        default:
            return nil
        }
    }

    var identifierSuffix: String {
        switch self {
        case .started:
            "started"
        case .completed:
            "completed"
        case .failed:
            "failed"
        case .canceled:
            "canceled"
        case .removed:
            "removed"
        }
    }

    var titleSuffix: String {
        switch self {
        case .started:
            "started deploying"
        case .completed:
            "deployed"
        case .failed:
            "failed"
        case .canceled:
            "was canceled"
        case .removed:
            "was removed"
        }
    }
}

private extension DeploymentStatus {
    var isDeploymentInFlight: Bool {
        switch self {
        case .queued, .waiting, .initializing, .building, .deploying:
            true
        default:
            false
        }
    }
}
