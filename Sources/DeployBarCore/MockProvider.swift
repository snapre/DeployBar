import Foundation

public struct MockProvider: DeploymentProvider {
    public let id: ProviderID = .mock
    public let displayName = "Mock"

    public init() {}

    public func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult {
        let now = context.now()
        let snapshots = [
            DeploymentSnapshot(
                id: "mock-queued",
                provider: .mock,
                projectName: "checkout-web",
                environmentName: "Preview",
                branch: "feature/menu-bar",
                commitSha: "a1b2c3d",
                actor: "alex",
                status: .queued,
                createdAt: now.addingTimeInterval(-90),
                lastUpdatedAt: now
            ),
            DeploymentSnapshot(
                id: "mock-building",
                provider: .mock,
                projectName: "api",
                serviceName: "worker",
                environmentName: "Production",
                branch: "main",
                commitSha: "d4e5f6a",
                actor: "mira",
                status: .building,
                createdAt: now.addingTimeInterval(-320),
                startedAt: now.addingTimeInterval(-260),
                dashboardURL: URL(string: "https://example.com/dashboard"),
                deploymentURL: URL(string: "https://api.example.com"),
                lastUpdatedAt: now
            ),
            DeploymentSnapshot(
                id: "mock-ready",
                provider: .mock,
                projectName: "docs",
                environmentName: "Production",
                branch: "main",
                commitSha: "987abcd",
                actor: "sam",
                status: .ready,
                createdAt: now.addingTimeInterval(-7200),
                startedAt: now.addingTimeInterval(-7150),
                finishedAt: now.addingTimeInterval(-7000),
                duration: 150,
                deploymentURL: URL(string: "https://docs.example.com"),
                lastUpdatedAt: now
            ),
            DeploymentSnapshot(
                id: "mock-failed",
                provider: .mock,
                projectName: "marketing",
                environmentName: "Preview",
                branch: "campaign-refresh",
                commitSha: "000bad1",
                actor: "nora",
                status: .failed,
                createdAt: now.addingTimeInterval(-1800),
                startedAt: now.addingTimeInterval(-1700),
                finishedAt: now.addingTimeInterval(-1650),
                duration: 50,
                errorMessage: "Build command exited with status 1",
                lastUpdatedAt: now
            )
        ]

        return ProviderRefreshResult(snapshots: snapshots)
    }
}
