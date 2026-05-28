import Foundation

public struct ProviderAccount: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var provider: ProviderID
    public var displayName: String
    public var tokenReference: String
    public var teamID: String?
    public var teamSlug: String?
    public var railwayTokenKind: RailwayTokenKind?
    public var authHeader: ProviderAuthHeader?
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
        authHeader: ProviderAuthHeader? = nil,
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
        self.authHeader = authHeader
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
        displayName(using: provider.targetBehavior)
    }

    public func matchesScope(of other: MonitoredTarget, for provider: ProviderID) -> Bool {
        matchesScope(of: other, using: provider.targetBehavior)
    }

    public func displayName(using behavior: ProviderTargetBehavior) -> String {
        let parts = behavior.displayFields.map { displayValue(for: $0, fallback: behavior.fallbackName(for: $0)) }
        let display = parts.compactMap { $0.nilIfBlank }.joined(separator: " / ")
        return display.isEmpty ? behavior.emptyTargetName : display
    }

    public func matchesScope(of other: MonitoredTarget, using behavior: ProviderTargetBehavior) -> Bool {
        guard !behavior.matchFields.isEmpty else { return true }
        return behavior.matchFields.allSatisfy { field in
            switch field {
            case .project:
                sameResource(projectID, projectName, other.projectID, other.projectName)
            case .service:
                sameResource(serviceID, serviceName, other.serviceID, other.serviceName)
            case .environment:
                sameResource(environmentID, environmentName, other.environmentID, other.environmentName)
            case .branch:
                sameText(branch, other.branch)
            }
        }
    }

    public func satisfiesRequiredFields(for provider: ProviderID) -> Bool {
        satisfiesRequiredFields(using: provider.targetBehavior)
    }

    public func satisfiesRequiredFields(using behavior: ProviderTargetBehavior) -> Bool {
        behavior.requiredFields.allSatisfy { value(for: $0) != nil }
    }

    public var hasAnyScopeValue: Bool {
        projectID.nilIfBlank != nil ||
            projectName.nilIfBlank != nil ||
            serviceID.nilIfBlank != nil ||
            serviceName.nilIfBlank != nil ||
            environmentID.nilIfBlank != nil ||
            environmentName.nilIfBlank != nil ||
            branch.nilIfBlank != nil
    }

    private func value(for field: ProviderTargetField) -> String? {
        switch field {
        case .project:
            return projectID.nilIfBlank ?? projectName.nilIfBlank
        case .service:
            return serviceID.nilIfBlank ?? serviceName.nilIfBlank
        case .environment:
            return environmentID.nilIfBlank ?? environmentName.nilIfBlank
        case .branch:
            return branch.nilIfBlank
        }
    }

    private func displayValue(for field: ProviderTargetField, fallback: String) -> String {
        switch field {
        case .project:
            return projectName.nilIfBlank ?? projectID.nilIfBlank ?? fallback
        case .service:
            return serviceName.nilIfBlank ?? serviceID.nilIfBlank ?? fallback
        case .environment:
            return environmentName.nilIfBlank ?? environmentID.nilIfBlank ?? fallback
        case .branch:
            return branch.nilIfBlank ?? fallback
        }
    }
}

public enum ProviderTargetField: String, Codable, CaseIterable, Sendable {
    case project
    case service
    case environment
    case branch
}

public struct ProviderTargetBehavior: Equatable, Sendable {
    public var displayFields: [ProviderTargetField]
    public var matchFields: [ProviderTargetField]
    public var requiredFields: [ProviderTargetField]
    public var emptyTargetName: String
    public var fallbackNames: [ProviderTargetField: String]

    public init(
        displayFields: [ProviderTargetField],
        matchFields: [ProviderTargetField],
        requiredFields: [ProviderTargetField] = [],
        emptyTargetName: String,
        fallbackNames: [ProviderTargetField: String] = [:]
    ) {
        self.displayFields = displayFields
        self.matchFields = matchFields
        self.requiredFields = requiredFields
        self.emptyTargetName = emptyTargetName
        self.fallbackNames = fallbackNames
    }

    public func fallbackName(for field: ProviderTargetField) -> String {
        fallbackNames[field] ?? field.defaultDisplayName
    }
}

public extension ProviderTargetField {
    var defaultDisplayName: String {
        switch self {
        case .project: "Project"
        case .service: "Service"
        case .environment: "Environment"
        case .branch: "Branch"
        }
    }
}

public extension ProviderID {
    var targetBehavior: ProviderTargetBehavior {
        switch self {
        case .mock:
            ProviderTargetBehavior(displayFields: [], matchFields: [], emptyTargetName: "Mock target")
        case .vercel:
            ProviderTargetBehavior(
                displayFields: [.project, .environment, .branch],
                matchFields: [.project, .environment, .branch],
                emptyTargetName: "All latest deployments",
                fallbackNames: [.project: "All projects", .environment: "All environments", .branch: "All branches"]
            )
        case .railway:
            ProviderTargetBehavior(
                displayFields: [.project, .service, .environment],
                matchFields: [.project, .service, .environment],
                requiredFields: [.service, .environment],
                emptyTargetName: "Railway target"
            )
        case .netlify:
            ProviderTargetBehavior(
                displayFields: [.project, .environment, .branch],
                matchFields: [.project, .environment, .branch],
                emptyTargetName: "All Netlify sites",
                fallbackNames: [.project: "All sites", .environment: "All contexts", .branch: "All branches"]
            )
        case .render:
            ProviderTargetBehavior(
                displayFields: [.service, .environment, .branch],
                matchFields: [.service, .environment, .branch],
                emptyTargetName: "All Render services",
                fallbackNames: [.service: "All services", .environment: "All environments", .branch: "All branches"]
            )
        case .cloudflarePages:
            ProviderTargetBehavior(
                displayFields: [.project, .environment, .branch],
                matchFields: [.project, .environment, .branch],
                emptyTargetName: "All Pages projects",
                fallbackNames: [.project: "All projects", .environment: "All environments", .branch: "All branches"]
            )
        case .digitalOcean:
            ProviderTargetBehavior(
                displayFields: [.project, .service, .environment],
                matchFields: [.project, .service, .environment],
                emptyTargetName: "All apps",
                fallbackNames: [.project: "All apps", .service: "All components", .environment: "All phases"]
            )
        case .heroku:
            ProviderTargetBehavior(
                displayFields: [.project],
                matchFields: [.project],
                emptyTargetName: "All Heroku apps",
                fallbackNames: [.project: "All apps"]
            )
        case .flyio:
            ProviderTargetBehavior(
                displayFields: [.project],
                matchFields: [.project],
                emptyTargetName: "All Fly apps",
                fallbackNames: [.project: "All apps"]
            )
        case .github, .gitlab:
            ProviderTargetBehavior(
                displayFields: [.project, .environment],
                matchFields: [.project, .environment],
                requiredFields: [.project],
                emptyTargetName: "Repository deployments",
                fallbackNames: [.project: "Repository", .environment: "All environments"]
            )
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

private extension String? {
    var nilIfBlank: String? {
        let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
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

public enum ProviderAuthHeader: String, Codable, Equatable, Sendable {
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
