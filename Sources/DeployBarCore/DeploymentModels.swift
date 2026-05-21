import Foundation

public enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case mock
    case vercel
    case railway

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mock: "Mock"
        case .vercel: "Vercel"
        case .railway: "Railway"
        }
    }
}

public enum DeploymentStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case waiting
    case initializing
    case building
    case deploying
    case ready
    case success
    case error
    case failed
    case crashed
    case canceled
    case removed
    case sleeping
    case skipped
    case unknown
}

public enum DeploymentSeverity: Int, Codable, CaseIterable, Comparable, Sendable {
    case healthy = 0
    case pending = 1
    case active = 2
    case warning = 3
    case critical = 4

    public static func < (lhs: DeploymentSeverity, rhs: DeploymentSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .healthy: "Healthy"
        case .pending: "Pending"
        case .active: "Active"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

public struct DeploymentSnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var provider: ProviderID
    public var projectName: String
    public var serviceName: String?
    public var environmentName: String?
    public var branch: String?
    public var commitSha: String?
    public var commitMessage: String?
    public var actor: String?
    public var status: DeploymentStatus
    public var severity: DeploymentSeverity
    public var createdAt: Date?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var duration: TimeInterval?
    public var dashboardURL: URL?
    public var deploymentURL: URL?
    public var errorMessage: String?
    public var lastUpdatedAt: Date
    public var isStale: Bool

    public init(
        id: String,
        provider: ProviderID,
        projectName: String,
        serviceName: String? = nil,
        environmentName: String? = nil,
        branch: String? = nil,
        commitSha: String? = nil,
        commitMessage: String? = nil,
        actor: String? = nil,
        status: DeploymentStatus,
        severity: DeploymentSeverity? = nil,
        createdAt: Date? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        duration: TimeInterval? = nil,
        dashboardURL: URL? = nil,
        deploymentURL: URL? = nil,
        errorMessage: String? = nil,
        lastUpdatedAt: Date = Date(),
        isStale: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.projectName = projectName
        self.serviceName = serviceName
        self.environmentName = environmentName
        self.branch = branch
        self.commitSha = commitSha
        self.commitMessage = commitMessage
        self.actor = actor
        self.status = status
        self.severity = severity ?? DeploymentStatusMapper.severity(for: status, isStale: isStale, failureKind: nil)
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.duration = duration
        self.dashboardURL = dashboardURL
        self.deploymentURL = deploymentURL
        self.errorMessage = errorMessage
        self.lastUpdatedAt = lastUpdatedAt
        self.isStale = isStale
    }
}

public enum ProviderFailureKind: String, Codable, Equatable, Sendable {
    case notConfigured
    case network
    case authentication
    case rateLimited
    case apiChanged
    case decoding
    case unknown
}

public struct ProviderIssue: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var provider: ProviderID
    public var accountID: String?
    public var kind: ProviderFailureKind
    public var message: String
    public var occurredAt: Date

    public init(
        id: String = UUID().uuidString,
        provider: ProviderID,
        accountID: String? = nil,
        kind: ProviderFailureKind,
        message: String,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.accountID = accountID
        self.kind = kind
        self.message = message
        self.occurredAt = occurredAt
    }
}

public enum RefreshCadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case seconds30
    case minute1
    case minutes5
    case minutes15

    public var id: String { rawValue }

    public var interval: TimeInterval? {
        switch self {
        case .manual: nil
        case .seconds30: 30
        case .minute1: 60
        case .minutes5: 300
        case .minutes15: 900
        }
    }

    public var displayName: String {
        switch self {
        case .manual: "Manual"
        case .seconds30: "30s"
        case .minute1: "1m"
        case .minutes5: "5m"
        case .minutes15: "15m"
        }
    }
}
