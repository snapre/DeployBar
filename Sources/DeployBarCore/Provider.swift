import Foundation

public struct ProviderAccount: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var provider: ProviderID
    public var displayName: String
    public var tokenReference: String
    public var teamID: String?
    public var teamSlug: String?
    public var railwayTokenKind: RailwayTokenKind?
    public var isEnabled: Bool
    public var monitoredTargets: [MonitoredTarget]

    public init(
        id: String = UUID().uuidString,
        provider: ProviderID,
        displayName: String,
        tokenReference: String,
        teamID: String? = nil,
        teamSlug: String? = nil,
        railwayTokenKind: RailwayTokenKind? = nil,
        isEnabled: Bool = true,
        monitoredTargets: [MonitoredTarget] = []
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.tokenReference = tokenReference
        self.teamID = teamID
        self.teamSlug = teamSlug
        self.railwayTokenKind = railwayTokenKind
        self.isEnabled = isEnabled
        self.monitoredTargets = monitoredTargets
    }
}

public enum RailwayTokenKind: String, Codable, CaseIterable, Sendable {
    case accountOrWorkspace
    case project

    public var displayName: String {
        switch self {
        case .accountOrWorkspace: "Account / Workspace"
        case .project: "Project"
        }
    }
}

public struct MonitoredTarget: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var projectID: String?
    public var projectName: String?
    public var serviceID: String?
    public var serviceName: String?
    public var environmentID: String?
    public var environmentName: String?
    public var branch: String?

    public init(
        id: String = UUID().uuidString,
        projectID: String? = nil,
        projectName: String? = nil,
        serviceID: String? = nil,
        serviceName: String? = nil,
        environmentID: String? = nil,
        environmentName: String? = nil,
        branch: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.projectName = projectName
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.environmentID = environmentID
        self.environmentName = environmentName
        self.branch = branch
    }

    public func displayName(for provider: ProviderID) -> String {
        switch provider {
        case .mock:
            return "Mock target"
        case .vercel:
            let project = projectName ?? projectID ?? "All projects"
            let environment = environmentName ?? "All environments"
            return [project, environment, branch].compactMap { $0 }.joined(separator: " / ")
        case .railway:
            let project = projectName ?? projectID ?? "Project"
            let service = serviceName ?? serviceID ?? "Service"
            let environment = environmentName ?? environmentID ?? "Environment"
            return [project, service, environment].joined(separator: " / ")
        }
    }

    public func matchesScope(of other: MonitoredTarget, for provider: ProviderID) -> Bool {
        switch provider {
        case .mock:
            return true
        case .vercel:
            return sameResource(projectID, projectName, other.projectID, other.projectName)
                && sameText(environmentName, other.environmentName)
                && sameText(branch, other.branch)
        case .railway:
            return sameResource(projectID, projectName, other.projectID, other.projectName)
                && sameResource(serviceID, serviceName, other.serviceID, other.serviceName)
                && sameResource(environmentID, environmentName, other.environmentID, other.environmentName)
        }
    }
}

private func sameResource(_ lhsID: String?, _ lhsName: String?, _ rhsID: String?, _ rhsName: String?) -> Bool {
    let lhs = Set([normalized(lhsID), normalized(lhsName)].compactMap { $0 })
    let rhs = Set([normalized(rhsID), normalized(rhsName)].compactMap { $0 })

    if lhs.isEmpty && rhs.isEmpty {
        return true
    }
    if lhs.isEmpty || rhs.isEmpty {
        return false
    }
    return !lhs.isDisjoint(with: rhs)
}

private func sameText(_ lhs: String?, _ rhs: String?) -> Bool {
    normalized(lhs) == normalized(rhs)
}

private func normalized(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let trimmed, !trimmed.isEmpty else { return nil }
    return trimmed.lowercased()
}

public struct ProviderContext: Sendable {
    public var account: ProviderAccount
    public var token: String?
    public var now: @Sendable () -> Date

    public init(
        account: ProviderAccount,
        token: String?,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.account = account
        self.token = token
        self.now = now
    }
}

public struct ProviderRefreshResult: Sendable {
    public var snapshots: [DeploymentSnapshot]
    public var issues: [ProviderIssue]

    public init(snapshots: [DeploymentSnapshot], issues: [ProviderIssue] = []) {
        self.snapshots = snapshots
        self.issues = issues
    }
}

public protocol DeploymentProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }

    func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult
}

public protocol TokenStore: Sendable {
    func token(for account: ProviderAccount) throws -> String?
}

public protocol MutableTokenStore: TokenStore {
    func save(token: String, for account: ProviderAccount) throws
    func deleteToken(for account: ProviderAccount) throws
}

public enum ProviderAuthHeader: Equatable, Sendable {
    case bearer
    case railwayProjectToken
}

public struct ProviderDescriptor: Identifiable, Equatable, Sendable {
    public var id: ProviderID
    public var displayName: String
    public var defaultEnabled: Bool
    public var requiresToken: Bool
    public var supportsTeamScope: Bool
    public var supportsMonitoredTargets: Bool
    public var requiresMonitoredTargets: Bool
    public var dashboardURL: URL?

    public init(
        id: ProviderID,
        displayName: String,
        defaultEnabled: Bool,
        requiresToken: Bool,
        supportsTeamScope: Bool,
        supportsMonitoredTargets: Bool,
        requiresMonitoredTargets: Bool,
        dashboardURL: URL? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.defaultEnabled = defaultEnabled
        self.requiresToken = requiresToken
        self.supportsTeamScope = supportsTeamScope
        self.supportsMonitoredTargets = supportsMonitoredTargets
        self.requiresMonitoredTargets = requiresMonitoredTargets
        self.dashboardURL = dashboardURL
    }
}
