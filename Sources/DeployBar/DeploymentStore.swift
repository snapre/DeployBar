import DeployBarCore
import Foundation
import SwiftUI

@MainActor
final class DeploymentStore: ObservableObject {
    @Published private(set) var snapshots: [DeploymentSnapshot] = []
    @Published private(set) var issues: [ProviderIssue] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?
    @Published var settings: DeployBarSettings

    let providerDescriptors = ProviderRegistry.defaultDescriptors.filter { $0.id != .mock }

    private let settingsStore: SettingsStore
    private let refreshCoordinator: RefreshCoordinator
    private let tokenStore: any MutableTokenStore
    private let notificationController = NotificationController()
    private var refreshTask: Task<Void, Never>?
    private var schedulerTask: Task<Void, Never>?
    private var previousStatuses: [String: DeploymentStatus] = [:]
    private var consecutiveFailureCount = 0
    private var pendingRefresh = false

    var globalSeverity: DeploymentSeverity {
        let snapshotSeverity = DeploymentSnapshotFocus.focused(snapshots).map(\.severity).max() ?? .healthy
        return max(snapshotSeverity, issueSeverity)
    }

    var issueSeverity: DeploymentSeverity {
        if issues.contains(where: { $0.kind == .authentication }) {
            return .critical
        }
        if !issues.isEmpty {
            return .warning
        }
        return .healthy
    }

    var hasConfiguredAccounts: Bool {
        settings.showMockProvider || !settings.accounts.isEmpty
    }

    init(
        settingsStore: SettingsStore = SettingsStore(),
        tokenStore: any MutableTokenStore = SecureTokenStore()
    ) {
        self.settingsStore = settingsStore
        self.tokenStore = tokenStore
        self.settings = settingsStore.load()
        let registry = ProviderRegistry(providers: [
            MockProvider(),
            VercelProvider(),
            RailwayProvider(),
            NetlifyProvider(),
            RenderProvider(),
            CloudflarePagesProvider(),
            DigitalOceanProvider(),
            HerokuProvider(),
            FlyProvider(),
            GitHubDeploymentsProvider(),
            GitLabDeploymentsProvider()
        ])
        self.refreshCoordinator = RefreshCoordinator(registry: registry, tokenStore: tokenStore)
    }

    func start() {
        refresh(manual: true)
        restartScheduler()
    }

    func addAccount(_ account: ProviderAccount, token: String) {
        do {
            try tokenStore.save(token: token, for: account)
            updateSettings { settings in
                settings.accounts.append(account)
            }
            refresh(manual: true)
        } catch {
            issues.append(ProviderIssue(provider: account.provider, accountID: account.id, kind: .unknown, message: "Could not save token to Keychain."))
        }
    }

    func deleteAccount(_ account: ProviderAccount) {
        do {
            try tokenStore.deleteToken(for: account)
        } catch {
            issues.append(ProviderIssue(provider: account.provider, accountID: account.id, kind: .unknown, message: "Could not delete token from Keychain."))
        }

        updateSettings { settings in
            settings.accounts.removeAll { $0.id == account.id }
        }
    }

    func setAccountEnabled(accountID: String, isEnabled: Bool) {
        updateSettings { settings in
            guard let index = settings.accounts.firstIndex(where: { $0.id == accountID }) else { return }
            settings.accounts[index].isEnabled = isEnabled
        }
    }

    func addTarget(_ target: MonitoredTarget, to accountID: String) {
        var didAdd = false
        updateSettings { settings in
            guard let index = settings.accounts.firstIndex(where: { $0.id == accountID }) else { return }
            let provider = settings.accounts[index].provider
            guard !settings.accounts[index].monitoredTargets.contains(where: { $0.matchesScope(of: target, for: provider) }) else { return }
            settings.accounts[index].monitoredTargets.append(target)
            didAdd = true
        }
        if didAdd {
            refresh(manual: true)
        }
    }

    func deleteTarget(targetID: String, from accountID: String) {
        updateSettings { settings in
            guard let index = settings.accounts.firstIndex(where: { $0.id == accountID }) else { return }
            settings.accounts[index].monitoredTargets.removeAll { $0.id == targetID }
        }
        refresh(manual: true)
    }

    func clearTargets(from accountID: String) {
        updateSettings { settings in
            guard let index = settings.accounts.firstIndex(where: { $0.id == accountID }) else { return }
            settings.accounts[index].monitoredTargets.removeAll()
        }
        refresh(manual: true)
    }

    func discoverVercelResources(for account: ProviderAccount) async -> VercelDiscoveryResult {
        do {
            guard let token = try tokenStore.token(for: account), !token.isEmpty else {
                return VercelDiscoveryResult(
                    issues: [ProviderIssue(provider: .vercel, accountID: account.id, kind: .notConfigured, message: "Vercel API token is not configured.")]
                )
            }
            return await VercelProvider().discoverResources(token: token, account: account)
        } catch {
            return VercelDiscoveryResult(
                issues: [ProviderIssue(provider: .vercel, accountID: account.id, kind: .unknown, message: "Could not read Vercel token from Keychain.")]
            )
        }
    }

    func discoverRailwayResources(token: String, tokenKind: RailwayTokenKind) async -> RailwayDiscoveryResult {
        await RailwayProvider().discoverResources(token: token, tokenKind: tokenKind)
    }

    func discoverCloudflareAccounts(token: String) async -> ProviderScopeDiscoveryResult {
        await CloudflarePagesProvider().discoverAccounts(token: token)
    }

    func discoverProviderTargets(
        provider: ProviderID,
        token: String,
        teamID: String? = nil,
        teamSlug: String? = nil,
        railwayTokenKind: RailwayTokenKind = .accountOrWorkspace,
        authHeader: ProviderAuthHeader? = nil
    ) async -> ProviderTargetDiscoveryResult {
        let account = ProviderAccount(
            provider: provider,
            displayName: provider.displayName,
            tokenReference: "discovery",
            teamID: teamID,
            teamSlug: teamSlug,
            railwayTokenKind: provider == .railway ? railwayTokenKind : nil,
            authHeader: authHeader
        )

        return await discoverProviderTargets(token: token, account: account)
    }

    func discoverProviderTargets(for account: ProviderAccount) async -> ProviderTargetDiscoveryResult {
        do {
            guard let token = try tokenStore.token(for: account), !token.isEmpty else {
                return ProviderTargetDiscoveryResult(
                    issues: [ProviderIssue(provider: account.provider, accountID: account.id, kind: .notConfigured, message: "\(account.provider.displayName) API token is not configured.")]
                )
            }
            return await discoverProviderTargets(token: token, account: account)
        } catch {
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: account.provider, accountID: account.id, kind: .unknown, message: "Could not read \(account.provider.displayName) token from Keychain.")]
            )
        }
    }

    private func discoverProviderTargets(token: String, account: ProviderAccount) async -> ProviderTargetDiscoveryResult {
        let provider = account.provider
        switch provider {
        case .vercel:
            let result = await VercelProvider().discoverResources(token: token, account: account)
            return ProviderTargetDiscoveryResult(
                targets: result.projects.map { MonitoredTarget(projectID: $0.id, projectName: $0.name) },
                issues: result.issues
            ).deduplicated(for: provider)
        case .railway:
            let result = await RailwayProvider().discoverResources(token: token, tokenKind: account.railwayTokenKind ?? .accountOrWorkspace)
            return ProviderTargetDiscoveryResult(
                targets: result.projects.flatMap { project in
                    let services = project.services.isEmpty ? [RailwayServiceResource(id: "", name: "")] : project.services
                    let environments = project.environments.isEmpty ? [RailwayEnvironmentResource(id: "", name: "")] : project.environments
                    return services.flatMap { service in
                        environments.map { environment in
                            MonitoredTarget(
                                projectID: project.id,
                                projectName: project.name,
                                serviceID: service.id.nilIfEmpty,
                                serviceName: service.name.nilIfEmpty,
                                environmentID: environment.id.nilIfEmpty,
                                environmentName: environment.name.nilIfEmpty
                            )
                        }
                    }
                },
                issues: result.issues
            ).deduplicated(for: provider)
        case .netlify:
            return await NetlifyProvider().discoverTargets(token: token, account: account).deduplicated(for: provider)
        case .render:
            return await RenderProvider().discoverTargets(token: token, account: account).deduplicated(for: provider)
        case .cloudflarePages:
            return await CloudflarePagesProvider().discoverTargets(token: token, account: account).deduplicated(for: provider)
        case .digitalOcean:
            return await DigitalOceanProvider().discoverTargets(token: token, account: account).deduplicated(for: provider)
        case .heroku:
            return await HerokuProvider().discoverTargets(token: token, account: account).deduplicated(for: provider)
        case .flyio:
            return await FlyProvider().discoverTargets(token: token, account: account).deduplicated(for: provider)
        case .github:
            return await GitHubDeploymentsProvider().discoverTargets(token: token, account: account).deduplicated(for: provider)
        case .gitlab:
            return await GitLabDeploymentsProvider().discoverTargets(token: token, account: account).deduplicated(for: provider)
        case .mock:
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: provider, kind: .notConfigured, message: "\(provider.displayName) discovery is not supported yet.")]
            )
        }
    }

    func discoverRailwayResources(for account: ProviderAccount) async -> RailwayDiscoveryResult {
        do {
            guard let token = try tokenStore.token(for: account), !token.isEmpty else {
                return RailwayDiscoveryResult(
                    issues: [ProviderIssue(provider: .railway, accountID: account.id, kind: .notConfigured, message: "Railway API token is not configured.")]
                )
            }
            return await RailwayProvider().discoverResources(token: token, tokenKind: account.railwayTokenKind ?? .accountOrWorkspace)
        } catch {
            return RailwayDiscoveryResult(
                issues: [ProviderIssue(provider: .railway, accountID: account.id, kind: .unknown, message: "Could not read Railway token from Keychain.")]
            )
        }
    }

    func refresh(manual: Bool = false) {
        guard refreshTask == nil else {
            pendingRefresh = true
            return
        }
        pendingRefresh = false
        isRefreshing = true

        let currentSettings = settings
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let result = await refreshCoordinator.refresh(settings: currentSettings)
            await MainActor.run {
                self.apply(result: result, manual: manual)
                self.isRefreshing = false
                self.lastRefreshAt = Date()
                self.refreshTask = nil
                if self.pendingRefresh {
                    self.refresh(manual: manual)
                }
            }
        }
    }

    func updateSettings(_ transform: (inout DeployBarSettings) -> Void) {
        var copy = settings
        transform(&copy)
        settings = copy

        do {
            try settingsStore.save(copy)
        } catch {
            issues.append(ProviderIssue(provider: .mock, kind: .unknown, message: "Could not save settings."))
        }

        restartScheduler()
    }

    private func restartScheduler() {
        schedulerTask?.cancel()
        guard let interval = settings.refreshCadence.interval else { return }

        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = await MainActor.run {
                    self?.nextSchedulerDelay(defaultInterval: interval) ?? interval
                }
                try? await Task.sleep(for: .seconds(delay))
                await MainActor.run {
                    self?.refresh()
                }
            }
        }
    }

    private func apply(result: ProviderRefreshResult, manual _: Bool) {
        let oldStatuses = previousStatuses
        snapshots = result.snapshots
        issues = result.issues
        consecutiveFailureCount = result.issues.isEmpty ? 0 : min(consecutiveFailureCount + 1, 6)
        previousStatuses = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0.status) })
        notificationController.notifyTransitions(oldStatuses: oldStatuses, snapshots: snapshots)
    }

    private func nextSchedulerDelay(defaultInterval: TimeInterval) -> TimeInterval {
        let baseInterval = hasLiveDeployments ? min(defaultInterval, Self.liveDeploymentRefreshInterval) : defaultInterval
        guard consecutiveFailureCount > 0 else { return baseInterval }
        let multiplier = pow(2, Double(consecutiveFailureCount - 1))
        return min(900, max(baseInterval, baseInterval * multiplier))
    }

    private var hasLiveDeployments: Bool {
        snapshots.contains { snapshot in
            snapshot.severity == .active || snapshot.severity == .pending
        }
    }

    private static let liveDeploymentRefreshInterval: TimeInterval = 10
}

#if DEBUG
extension DeploymentStore {
    func loadWebsitePreview(
        snapshots: [DeploymentSnapshot],
        issues: [ProviderIssue] = [],
        lastRefreshAt: Date = Date()
    ) {
        self.snapshots = snapshots
        self.issues = issues
        self.isRefreshing = false
        self.lastRefreshAt = lastRefreshAt
        self.settings = DeployBarSettings(
            refreshCadence: .manual,
            accounts: Array(Set(snapshots.map(\.provider))).sorted { $0.rawValue < $1.rawValue }.map { provider in
                ProviderAccount(provider: provider, displayName: provider.displayName, tokenReference: "website-preview")
            },
            showMockProvider: false
        )
    }
}
#endif
