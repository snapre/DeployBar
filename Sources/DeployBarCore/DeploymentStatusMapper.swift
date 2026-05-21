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
        case "INITIALIZING": .initializing
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

    public static func netlifyStatus(_ rawValue: String) -> DeploymentStatus {
        switch normalized(rawValue) {
        case "new", "enqueued", "queued": .queued
        case "pending", "processing", "preparing": .initializing
        case "building", "uploading": .building
        case "ready": .ready
        case "error", "failed": .failed
        case "canceled", "cancelled": .canceled
        case "skipped": .skipped
        default: .unknown
        }
    }

    public static func renderStatus(_ rawValue: String) -> DeploymentStatus {
        switch normalized(rawValue) {
        case "created", "queued", "pending_update": .queued
        case "build_in_progress", "build_in_progress_with_failure": .building
        case "update_in_progress", "live_update_in_progress", "deploying": .deploying
        case "live": .success
        case "deactivated", "canceled", "cancelled": .canceled
        case "build_failed", "update_failed", "pre_deploy_failed": .failed
        default: .unknown
        }
    }

    public static func cloudflarePagesStatus(_ rawValue: String) -> DeploymentStatus {
        switch normalized(rawValue) {
        case "queued", "idle": .queued
        case "active", "building", "deploying": .building
        case "success": .success
        case "failure", "failed": .failed
        case "canceled", "cancelled": .canceled
        case "skipped": .skipped
        default: .unknown
        }
    }

    public static func digitalOceanStatus(_ rawValue: String) -> DeploymentStatus {
        switch normalized(rawValue) {
        case "pending", "queued": .queued
        case "building", "build": .building
        case "deploying", "deploy": .deploying
        case "active", "running", "success", "succeeded": .success
        case "error", "failed": .failed
        case "canceled", "cancelled": .canceled
        case "skipped": .skipped
        default: .unknown
        }
    }

    public static func herokuStatus(_ rawValue: String) -> DeploymentStatus {
        switch normalized(rawValue) {
        case "pending": .deploying
        case "succeeded", "success": .success
        case "failed", "error": .failed
        case "expired": .removed
        default: .unknown
        }
    }

    public static func githubDeploymentStatus(_ rawValue: String?) -> DeploymentStatus {
        switch normalized(rawValue ?? "") {
        case "queued": .queued
        case "pending": .waiting
        case "in_progress": .deploying
        case "success": .success
        case "failure", "failed": .failed
        case "error": .error
        case "inactive": .removed
        case "cancelled", "canceled": .canceled
        default: .unknown
        }
    }

    public static func gitlabDeploymentStatus(_ rawValue: String) -> DeploymentStatus {
        switch normalized(rawValue) {
        case "created": .queued
        case "running": .deploying
        case "success": .success
        case "failed": .failed
        case "canceled", "cancelled": .canceled
        case "blocked": .waiting
        default: .unknown
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
