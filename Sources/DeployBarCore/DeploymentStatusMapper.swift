import Foundation

public enum DeploymentStatusMapper {
    public static func severity(
        for status: DeploymentStatus,
        isStale: Bool = false,
        failureKind: ProviderFailureKind? = nil
    ) -> DeploymentSeverity {
        if isStale {
            return failureKind == .authentication ? .critical : .warning
        }

        switch status {
        case .failed, .crashed, .error:
            return .critical
        case .removed, .unknown:
            return .warning
        case .canceled:
            return .healthy
        case .queued, .waiting, .initializing:
            return .pending
        case .building, .deploying:
            return .active
        case .success, .ready, .sleeping, .skipped:
            return .healthy
        }
    }

    public static func vercelStatus(_ rawValue: String) -> DeploymentStatus {
        switch rawValue.uppercased() {
        case "QUEUED": .queued
        case "INITIALIZING": .initializing
        case "BUILDING": .building
        case "READY": .ready
        case "ERROR": .error
        case "CANCELED": .canceled
        default: .unknown
        }
    }

    public static func railwayStatus(_ rawValue: String) -> DeploymentStatus {
        switch rawValue.uppercased() {
        case "QUEUED": .queued
        case "WAITING": .waiting
        case "BUILDING": .building
        case "DEPLOYING": .deploying
        case "SUCCESS": .success
        case "FAILED": .failed
        case "CRASHED": .crashed
        case "REMOVED": .removed
        case "SLEEPING": .sleeping
        case "SKIPPED": .skipped
        default: .unknown
        }
    }
}
