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
