import Foundation

public struct ProviderTargetDiscoveryResult: Equatable, Sendable {
    public var targets: [MonitoredTarget]
    public var issues: [ProviderIssue]

    public init(targets: [MonitoredTarget] = [], issues: [ProviderIssue] = []) {
        self.targets = targets
        self.issues = issues
    }

    public func deduplicated(for provider: ProviderID) -> ProviderTargetDiscoveryResult {
        ProviderTargetDiscoveryResult(targets: targets.deduplicatedTargets(for: provider), issues: issues)
    }
}

public struct ProviderScopeDiscoveryResult: Equatable, Sendable {
    public var scopes: [ProviderScopeResource]
    public var issues: [ProviderIssue]

    public init(scopes: [ProviderScopeResource] = [], issues: [ProviderIssue] = []) {
        self.scopes = scopes
        self.issues = issues
    }
}

public struct ProviderScopeResource: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public extension Sequence where Element == MonitoredTarget {
    func deduplicatedTargets(for provider: ProviderID) -> [MonitoredTarget] {
        var unique: [MonitoredTarget] = []
        for target in self where !unique.contains(where: { $0.matchesScope(of: target, for: provider) }) {
            unique.append(target)
        }
        return unique
    }

    func excludingTargets(_ existingTargets: [MonitoredTarget], for provider: ProviderID) -> [MonitoredTarget] {
        deduplicatedTargets(for: provider).filter { target in
            !existingTargets.contains { $0.matchesScope(of: target, for: provider) }
        }
    }
}
