import DeployBarCore
import XCTest

final class RefreshCoordinatorTests: XCTestCase {
    func testKeepsPreviousSnapshotsAndMarksStaleWhenProviderFails() async {
        let provider = FlakyProvider()
        let registry = ProviderRegistry(providers: [provider])
        let account = ProviderAccount(provider: .vercel, displayName: "Vercel", tokenReference: "token")
        let settings = DeployBarSettings(refreshCadence: .manual, accounts: [account], showMockProvider: false)
        let coordinator = RefreshCoordinator(registry: registry, tokenStore: InMemoryTokenStore(tokens: ["token": "secret"]))

        let first = await coordinator.refresh(settings: settings, now: { Date(timeIntervalSince1970: 1) })
        XCTAssertEqual(first.snapshots.count, 1)
        XCTAssertFalse(first.snapshots[0].isStale)

        let second = await coordinator.refresh(settings: settings, now: { Date(timeIntervalSince1970: 2) })
        XCTAssertEqual(second.snapshots.count, 1)
        XCTAssertTrue(second.snapshots[0].isStale)
        XCTAssertEqual(second.snapshots[0].severity, .warning)
        XCTAssertEqual(second.issues.first?.kind, .network)
    }

    func testBackoffIncreasesAfterFailures() async {
        let provider = FlakyProvider(alwaysFail: true)
        let registry = ProviderRegistry(providers: [provider])
        let account = ProviderAccount(provider: .vercel, displayName: "Vercel", tokenReference: "token")
        let settings = DeployBarSettings(refreshCadence: .manual, accounts: [account], showMockProvider: false)
        let coordinator = RefreshCoordinator(registry: registry, tokenStore: InMemoryTokenStore(tokens: ["token": "secret"]))

        _ = await coordinator.refresh(settings: settings)
        let firstDelay = await coordinator.backoffDelay(for: account.id)
        XCTAssertEqual(firstDelay, 60)
        _ = await coordinator.refresh(settings: settings)
        let secondDelay = await coordinator.backoffDelay(for: account.id)
        XCTAssertEqual(secondDelay, 120)
    }

    func testSuccessfulRefreshReplacesOldProviderSnapshots() async {
        let provider = SequencedProvider()
        let registry = ProviderRegistry(providers: [provider])
        let account = ProviderAccount(provider: .railway, displayName: "Railway", tokenReference: "token")
        let settings = DeployBarSettings(refreshCadence: .manual, accounts: [account], showMockProvider: false)
        let coordinator = RefreshCoordinator(registry: registry, tokenStore: InMemoryTokenStore(tokens: ["token": "secret"]))

        let first = await coordinator.refresh(settings: settings, now: { Date(timeIntervalSince1970: 1) })
        XCTAssertEqual(first.snapshots.map(\.id), ["railway:\(account.id):dep_building"])

        let second = await coordinator.refresh(settings: settings, now: { Date(timeIntervalSince1970: 2) })
        XCTAssertEqual(second.snapshots.map(\.id), ["railway:\(account.id):dep_success"])
        XCTAssertEqual(second.snapshots[0].status, .success)
    }

    func testDisablingMockProviderRemovesStoredMockSnapshots() async {
        let registry = ProviderRegistry(providers: [MockProvider()])
        let coordinator = RefreshCoordinator(registry: registry, tokenStore: InMemoryTokenStore())
        let enabled = DeployBarSettings(refreshCadence: .manual, accounts: [], showMockProvider: true)
        let disabled = DeployBarSettings(refreshCadence: .manual, accounts: [], showMockProvider: false)

        let first = await coordinator.refresh(settings: enabled, now: { Date(timeIntervalSince1970: 1) })
        XCTAssertTrue(first.snapshots.contains { $0.provider == .mock })

        let second = await coordinator.refresh(settings: disabled, now: { Date(timeIntervalSince1970: 2) })
        XCTAssertFalse(second.snapshots.contains { $0.provider == .mock })
    }
}

private final class FlakyProvider: DeploymentProvider, @unchecked Sendable {
    let id: ProviderID = .vercel
    let displayName = "Vercel"
    private let counter = CallCounter()
    private let alwaysFail: Bool

    init(alwaysFail: Bool = false) {
        self.alwaysFail = alwaysFail
    }

    func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult {
        let currentCall = await counter.increment()

        if alwaysFail || currentCall > 1 {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: .vercel, accountID: context.account.id, kind: .network, message: "Network unavailable.")]
            )
        }

        return ProviderRefreshResult(
            snapshots: [
                DeploymentSnapshot(
                    id: "vercel:\(context.account.id):dpl_1",
                    provider: .vercel,
                    projectName: "web",
                    status: .ready,
                    lastUpdatedAt: context.now()
                )
            ]
        )
    }
}

private actor CallCounter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

private final class SequencedProvider: DeploymentProvider, @unchecked Sendable {
    let id: ProviderID = .railway
    let displayName = "Railway"
    private let counter = CallCounter()

    func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult {
        let currentCall = await counter.increment()
        let deploymentID = currentCall == 1 ? "dep_building" : "dep_success"
        let status: DeploymentStatus = currentCall == 1 ? .building : .success

        return ProviderRefreshResult(
            snapshots: [
                DeploymentSnapshot(
                    id: "railway:\(context.account.id):\(deploymentID)",
                    provider: .railway,
                    projectName: "api",
                    serviceName: "worker",
                    environmentName: "production",
                    status: status,
                    lastUpdatedAt: context.now()
                )
            ]
        )
    }
}
