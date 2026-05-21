import Foundation

public struct GitHubDeploymentsProvider: DeploymentProvider {
    public let id: ProviderID = .github
    public let displayName = "GitHub"

    private let client: any HTTPClient
    private let baseURL: URL
    private let limit: Int

    public init(
        client: any HTTPClient = APIClient(),
        baseURL: URL = URL(string: "https://api.github.com")!,
        limit: Int = 10
    ) {
        self.client = client
        self.baseURL = baseURL
        self.limit = limit
    }

    public func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult {
        guard let token = context.token, !token.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "GitHub token is not configured.")]
            )
        }
        guard !context.account.monitoredTargets.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "GitHub deployments require at least one repository target.")]
            )
        }

        var snapshots: [DeploymentSnapshot] = []
        var issues: [ProviderIssue] = []

        for target in context.account.monitoredTargets {
            guard let repository = target.projectID ?? target.projectName else {
                issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "GitHub target needs a repository such as owner/repo."))
                continue
            }

            do {
                let response = try await client.send(makeDeploymentsRequest(repository: repository, environment: target.environmentName, token: token))
                if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: context.account.id, statusCode: response.statusCode) {
                    issues.append(issue)
                    continue
                }

                let deployments = try GitHubDeploymentsParser.deployments(from: response.data)
                for deployment in deployments {
                    let (status, statusIssue) = try await latestStatus(for: deployment, token: token, accountID: context.account.id)
                    if let statusIssue {
                        issues.append(statusIssue)
                    }
                    snapshots.append(GitHubDeploymentsParser.snapshot(deployment: deployment, latestStatus: status, repository: repository, account: context.account, target: target, now: context.now()))
                }
            } catch let error as APIClientError {
                issues.append(ProviderUtilities.issue(for: error, provider: id, accountID: context.account.id))
            } catch {
                issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "GitHub deployments response could not be parsed."))
            }
        }

        return ProviderRefreshResult(snapshots: ProviderUtilities.deduplicated(snapshots), issues: issues)
    }

    private func latestStatus(
        for deployment: GitHubDeployment,
        token: String,
        accountID: String
    ) async throws -> (GitHubDeploymentStatus?, ProviderIssue?) {
        guard let statusesURL = deployment.statusesURL else { return (nil, nil) }
        let response = try await client.send(makeStatusesRequest(statusesURL: statusesURL, token: token))
        if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: accountID, statusCode: response.statusCode) {
            return (nil, issue)
        }
        return (try GitHubDeploymentsParser.statuses(from: response.data).first, nil)
    }

    private func makeDeploymentsRequest(repository: String, environment: String?, token: String) throws -> URLRequest {
        let parts = repository.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw APIClientError.invalidResponse }
        var components = URLComponents(url: baseURL.appendingPathComponent("repos").appendingPathComponent(parts[0]).appendingPathComponent(parts[1]).appendingPathComponent("deployments"), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "per_page", value: "\(limit)")]
        if let environment {
            queryItems.append(URLQueryItem(name: "environment", value: environment))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw APIClientError.invalidResponse }
        return authenticatedRequest(url: url, token: token)
    }

    private func makeStatusesRequest(statusesURL: URL, token: String) -> URLRequest {
        var components = URLComponents(url: statusesURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "per_page", value: "1")]
        return authenticatedRequest(url: components?.url ?? statusesURL, token: token)
    }

    private func authenticatedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("DeployBar/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }
}

public enum GitHubDeploymentsParser {
    static func deployments(from data: Data) throws -> [GitHubDeployment] {
        try JSONDecoder.deployBar.decode([GitHubDeployment].self, from: data)
    }

    static func statuses(from data: Data) throws -> [GitHubDeploymentStatus] {
        try JSONDecoder.deployBar.decode([GitHubDeploymentStatus].self, from: data)
    }

    static func snapshot(
        deployment: GitHubDeployment,
        latestStatus: GitHubDeploymentStatus?,
        repository: String,
        account: ProviderAccount,
        target: MonitoredTarget,
        now: Date = Date()
    ) -> DeploymentSnapshot {
        let status = DeploymentStatusMapper.githubDeploymentStatus(latestStatus?.state)
        let finishedAt = terminal(status) ? latestStatus?.updatedAt ?? deployment.updatedAt : nil
        return DeploymentSnapshot(
            id: "github:\(account.id):\(deployment.id)",
            provider: .github,
            projectName: target.projectName ?? repository,
            serviceName: deployment.task,
            environmentName: deployment.environment ?? target.environmentName,
            branch: deployment.ref,
            commitSha: deployment.sha,
            commitMessage: latestStatus?.description ?? deployment.description,
            actor: latestStatus?.creator?.login ?? deployment.creator?.login,
            status: status,
            createdAt: deployment.createdAt,
            startedAt: deployment.createdAt,
            finishedAt: finishedAt,
            duration: ProviderUtilities.duration(startedAt: deployment.createdAt, finishedAt: finishedAt),
            dashboardURL: URL(string: "https://github.com/\(repository)/deployments"),
            deploymentURL: latestStatus?.environmentURL ?? latestStatus?.targetURL,
            errorMessage: errorMessage(status: status, statusDescription: latestStatus?.description),
            lastUpdatedAt: now
        )
    }

    private static func terminal(_ status: DeploymentStatus) -> Bool {
        switch status {
        case .success, .ready, .failed, .error, .removed, .canceled:
            return true
        default:
            return false
        }
    }

    private static func errorMessage(status: DeploymentStatus, statusDescription: String?) -> String? {
        switch status {
        case .failed, .error:
            return statusDescription
        default:
            return nil
        }
    }
}

struct GitHubDeployment: Decodable {
    var id: Int
    var sha: String?
    var ref: String?
    var task: String?
    var environment: String?
    var description: String?
    var statusesURL: URL?
    var createdAt: Date?
    var updatedAt: Date?
    var creator: GitHubUser?

    enum CodingKeys: String, CodingKey {
        case id
        case sha
        case ref
        case task
        case environment
        case description
        case statusesURL = "statuses_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case creator
    }
}

struct GitHubDeploymentStatus: Decodable {
    var id: Int?
    var state: String?
    var description: String?
    var environmentURL: URL?
    var targetURL: URL?
    var logURL: URL?
    var createdAt: Date?
    var updatedAt: Date?
    var creator: GitHubUser?

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case description
        case environmentURL = "environment_url"
        case targetURL = "target_url"
        case logURL = "log_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case creator
    }
}

struct GitHubUser: Decodable {
    var login: String?
}
