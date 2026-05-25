import Foundation

public struct DigitalOceanProvider: DeploymentProvider {
    public let id: ProviderID = .digitalOcean
    public let displayName = "DigitalOcean"

    private let client: any HTTPClient
    private let baseURL: URL
    private let limit: Int
    private let appLimit: Int

    public init(
        client: any HTTPClient = APIClient(),
        baseURL: URL = URL(string: "https://api.digitalocean.com")!,
        limit: Int = 10,
        appLimit: Int = 20
    ) {
        self.client = client
        self.baseURL = baseURL
        self.limit = limit
        self.appLimit = appLimit
    }

    public func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult {
        guard let token = context.token, !token.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "DigitalOcean API token is not configured.")]
            )
        }

        do {
            let targets = try await targets(for: context.account, token: token)
            var snapshots: [DeploymentSnapshot] = []
            var issues: [ProviderIssue] = []

            for target in targets {
                guard let appID = target.projectID ?? target.projectName else {
                    issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "DigitalOcean target needs an app ID."))
                    continue
                }

                let response = try await client.send(makeDeploymentsRequest(appID: appID, token: token))
                if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: context.account.id, statusCode: response.statusCode) {
                    issues.append(issue)
                    continue
                }

                snapshots.append(contentsOf: try DigitalOceanParser.snapshots(from: response.data, account: context.account, target: target, now: context.now()))
            }

            return ProviderRefreshResult(snapshots: ProviderUtilities.deduplicated(snapshots), issues: issues)
        } catch let error as DigitalOceanIssue {
            return ProviderRefreshResult(snapshots: [], issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderRefreshResult(snapshots: [], issues: [ProviderUtilities.issue(for: error, provider: id, accountID: context.account.id)])
        } catch {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "DigitalOcean API response could not be parsed.")]
            )
        }
    }

    public func discoverTargets(token: String, account: ProviderAccount) async -> ProviderTargetDiscoveryResult {
        guard !token.isEmpty else {
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .notConfigured, message: "DigitalOcean API token is not configured.")]
            )
        }

        do {
            return ProviderTargetDiscoveryResult(targets: try await targets(for: account, token: token))
        } catch let error as DigitalOceanIssue {
            return ProviderTargetDiscoveryResult(issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderTargetDiscoveryResult(issues: [ProviderUtilities.issue(for: error, provider: id, accountID: account.id)])
        } catch {
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .apiChanged, message: "DigitalOcean discovery response could not be parsed.")]
            )
        }
    }

    private func targets(for account: ProviderAccount, token: String) async throws -> [MonitoredTarget] {
        if !account.monitoredTargets.isEmpty {
            return account.monitoredTargets
        }

        let response = try await client.send(makeAppsRequest(token: token))
        if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: account.id, statusCode: response.statusCode) {
            throw DigitalOceanIssue(issue)
        }

        return try DigitalOceanParser.apps(from: response.data).prefix(appLimit).map { app in
            MonitoredTarget(projectID: app.id, projectName: app.name)
        }
    }

    private func makeAppsRequest(token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("v2").appendingPathComponent("apps"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "per_page", value: "\(appLimit)")]
        guard let url = components?.url else { throw APIClientError.invalidResponse }
        return authenticatedRequest(url: url, token: token)
    }

    private func makeDeploymentsRequest(appID: String, token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("v2").appendingPathComponent("apps").appendingPathComponent(appID).appendingPathComponent("deployments"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "per_page", value: "\(limit)")]
        guard let url = components?.url else { throw APIClientError.invalidResponse }
        return authenticatedRequest(url: url, token: token)
    }

    private func authenticatedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DeployBar/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }
}

public enum DigitalOceanParser {
    public static func snapshots(from data: Data, account: ProviderAccount, target: MonitoredTarget, now: Date = Date()) throws -> [DeploymentSnapshot] {
        let response = try JSONDecoder.deployBar.decode(DigitalOceanDeploymentsResponse.self, from: data)
        return response.deployments.map { deployment in
            let status = DeploymentStatusMapper.digitalOceanStatus(deployment.phase ?? deployment.progress?.currentStep ?? "")
            let finishedAt = finishedAt(status: status, deployment: deployment)
            return DeploymentSnapshot(
                id: "digitalOcean:\(account.id):\(deployment.id)",
                provider: .digitalOcean,
                projectName: target.projectName ?? target.projectID ?? "DigitalOcean App",
                serviceName: target.serviceName,
                environmentName: deployment.phase ?? target.environmentName,
                branch: deployment.spec?.branch ?? target.branch,
                commitSha: deployment.spec?.commitSHA,
                commitMessage: deployment.cause,
                actor: deployment.triggeredBy,
                status: status,
                createdAt: deployment.createdAt,
                startedAt: deployment.createdAt,
                finishedAt: finishedAt,
                duration: ProviderUtilities.duration(startedAt: deployment.createdAt, finishedAt: finishedAt),
                dashboardURL: dashboardURL(appID: target.projectID, deploymentID: deployment.id),
                deploymentURL: nil,
                errorMessage: deployment.progress?.error,
                lastUpdatedAt: now
            )
        }
    }

    static func apps(from data: Data) throws -> [DigitalOceanApp] {
        try JSONDecoder.deployBar.decode(DigitalOceanAppsResponse.self, from: data).apps
    }

    private static func finishedAt(status: DeploymentStatus, deployment: DigitalOceanDeployment) -> Date? {
        switch status {
        case .success, .ready, .failed, .error, .canceled, .skipped:
            return deployment.updatedAt
        default:
            return nil
        }
    }

    private static func dashboardURL(appID: String?, deploymentID: String) -> URL? {
        guard let appID else { return nil }
        return URL(string: "https://cloud.digitalocean.com/apps/\(appID)/deployments/\(deploymentID)")
    }
}

private struct DigitalOceanAppsResponse: Decodable {
    var apps: [DigitalOceanApp]
}

struct DigitalOceanApp: Decodable {
    var id: String
    var spec: DigitalOceanAppSpec?

    var name: String? {
        spec?.name
    }
}

private struct DigitalOceanDeploymentsResponse: Decodable {
    var deployments: [DigitalOceanDeployment]
}

private struct DigitalOceanDeployment: Decodable {
    var id: String
    var cause: String?
    var phase: String?
    var triggeredBy: String?
    var createdAt: Date?
    var updatedAt: Date?
    var progress: DigitalOceanDeploymentProgress?
    var spec: DigitalOceanAppSpec?

    enum CodingKeys: String, CodingKey {
        case id
        case cause
        case phase
        case triggeredBy = "triggered_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case progress
        case spec
    }
}

private struct DigitalOceanDeploymentProgress: Decodable {
    var currentStep: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case currentStep = "current_step"
        case error
    }
}

struct DigitalOceanAppSpec: Decodable {
    var name: String?
    var branch: String?
    var commitSHA: String?

    enum CodingKeys: String, CodingKey {
        case name
        case branch
        case commitSHA = "commit_sha"
    }
}

private struct DigitalOceanIssue: Error {
    var issue: ProviderIssue

    init(_ issue: ProviderIssue) {
        self.issue = issue
    }
}
