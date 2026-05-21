import Foundation

public actor RefreshCoordinator {
    private let registry: ProviderRegistry
    private let tokenStore: any TokenStore
    private var snapshotsByID: [String: DeploymentSnapshot] = [:]
    private var isRefreshing = false
    private var failureCountByAccountID: [String: Int] = [:]

    public init(registry: ProviderRegistry, tokenStore: any TokenStore) {
        self.registry = registry
        self.tokenStore = tokenStore
    }

    public func refresh(settings: DeployBarSettings, now: @escaping @Sendable () -> Date = Date.init) async -> ProviderRefreshResult {
        guard !isRefreshing else {
            return ProviderRefreshResult(
                snapshots: sortedSnapshots(),
                issues: [
                    ProviderIssue(provider: .mock, kind: .unknown, message: "Refresh already in progress.")
                ]
            )
        }

        isRefreshing = true
        defer { isRefreshing = false }

        var allSnapshots: [DeploymentSnapshot] = []
        var allIssues: [ProviderIssue] = []

        pruneDisabledSnapshots(settings: settings)

        if settings.showMockProvider, let mockProvider = registry[.mock] {
            removeStoredSnapshots(provider: .mock)
            let mockAccount = ProviderAccount(provider: .mock, displayName: "Mock", tokenReference: "mock")
            let result = await mockProvider.fetchDeployments(context: ProviderContext(account: mockAccount, token: nil, now: now))
            allSnapshots.append(contentsOf: result.snapshots)
            allIssues.append(contentsOf: result.issues)
        }

        for account in settings.accounts where account.isEnabled {
            guard let provider = registry[account.provider] else {
                allIssues.append(ProviderIssue(provider: account.provider, accountID: account.id, kind: .unknown, message: "Provider is not registered."))
                continue
            }

            do {
                let token = try tokenStore.token(for: account)
                guard token?.isEmpty == false else {
                    markExistingSnapshotsStale(provider: account.provider, accountID: account.id, now: now(), failureKind: .notConfigured)
                    allIssues.append(ProviderIssue(provider: account.provider, accountID: account.id, kind: .notConfigured, message: "API token is not configured."))
                    continue
                }

                let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: token, now: now))
                if result.issues.isEmpty {
                    failureCountByAccountID[account.id] = 0
                    removeStoredSnapshots(provider: account.provider, accountID: account.id)
                } else {
                    failureCountByAccountID[account.id, default: 0] += 1
                    if result.snapshots.isEmpty {
                        markExistingSnapshotsStale(
                            provider: account.provider,
                            accountID: account.id,
                            now: now(),
                            failureKind: result.issues.first?.kind ?? .unknown
                        )
                    }
                }
                allSnapshots.append(contentsOf: result.snapshots)
                allIssues.append(contentsOf: result.issues)
            } catch {
                failureCountByAccountID[account.id, default: 0] += 1
                markExistingSnapshotsStale(provider: account.provider, accountID: account.id, now: now(), failureKind: .unknown)
                allIssues.append(ProviderIssue(provider: account.provider, accountID: account.id, kind: .unknown, message: "Could not read API token."))
            }
        }

        for snapshot in allSnapshots {
            snapshotsByID[snapshot.id] = snapshot
        }

        return ProviderRefreshResult(snapshots: sortedSnapshots(), issues: allIssues)
    }

    public func backoffDelay(for accountID: String, base: TimeInterval = 60, max: TimeInterval = 900) -> TimeInterval {
        let failures = failureCountByAccountID[accountID, default: 0]
        guard failures > 0 else { return 0 }
        return min(max, base * pow(2, Double(failures - 1)))
    }

    private func sortedSnapshots() -> [DeploymentSnapshot] {
        snapshotsByID.values.sorted { lhs, rhs in
            lhs.createdAt ?? lhs.lastUpdatedAt > rhs.createdAt ?? rhs.lastUpdatedAt
        }
    }

    private func removeStoredSnapshots(provider: ProviderID, accountID: String) {
        let idPrefix = "\(provider.rawValue):\(accountID):"
        snapshotsByID = snapshotsByID.filter { id, snapshot in
            snapshot.provider != provider || !id.hasPrefix(idPrefix)
        }
    }

    private func removeStoredSnapshots(provider: ProviderID) {
        snapshotsByID = snapshotsByID.filter { _, snapshot in
            snapshot.provider != provider
        }
    }

    private func pruneDisabledSnapshots(settings: DeployBarSettings) {
        if !settings.showMockProvider {
            removeStoredSnapshots(provider: .mock)
        }

        let enabledAccountPrefixes = Set(
            settings.accounts
                .filter(\.isEnabled)
                .map { "\($0.provider.rawValue):\($0.id):" }
        )

        snapshotsByID = snapshotsByID.filter { id, snapshot in
            if snapshot.provider == .mock {
                return settings.showMockProvider
            }
            return enabledAccountPrefixes.contains { id.hasPrefix($0) }
        }
    }

    private func markExistingSnapshotsStale(provider: ProviderID, accountID _: String, now: Date, failureKind: ProviderFailureKind) {
        snapshotsByID = snapshotsByID.mapValues { snapshot in
            guard snapshot.provider == provider else { return snapshot }
            var staleSnapshot = snapshot
            staleSnapshot.isStale = true
            staleSnapshot.lastUpdatedAt = now
            staleSnapshot.severity = DeploymentStatusMapper.severity(for: snapshot.status, isStale: true, failureKind: failureKind)
            return staleSnapshot
        }
    }
}

public final class InMemoryTokenStore: MutableTokenStore, @unchecked Sendable {
    private var tokens: [String: String]
    private let lock = NSLock()

    public init(tokens: [String: String] = [:]) {
        self.tokens = tokens
    }

    public func token(for account: ProviderAccount) throws -> String? {
        lock.withLock {
            tokens[account.tokenReference]
        }
    }

    public func save(token: String, for account: ProviderAccount) throws {
        lock.withLock {
            tokens[account.tokenReference] = token
        }
    }

    public func deleteToken(for account: ProviderAccount) throws {
        _ = lock.withLock {
            tokens.removeValue(forKey: account.tokenReference)
        }
    }
}
