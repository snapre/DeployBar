import Foundation

public struct GitLabDeploymentsProvider: DeploymentProvider {
    public let id: ProviderID = .gitlab
    public let displayName = "GitLab"

    private let client: any HTTPClient
    private let baseURL: URL
    private let limit: Int

    public init(
        client: any HTTPClient = APIClient(),
        baseURL: URL = URL(string: "https://gitlab.com/api/v4")!,
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
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "GitLab token is not configured.")]
            )
        }
        guard !context.account.monitoredTargets.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "GitLab deployments require at least one project target.")]
            )
        }

        var snapshots: [DeploymentSnapshot] = []
        var issues: [ProviderIssue] = []

        for target in context.account.monitoredTargets {
            guard let project = target.projectID ?? target.projectName else {
                issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "GitLab target needs a project ID or URL-encoded path."))
                continue
            }

            do {
                let response = try await client.send(makeDeploymentsRequest(project: project, environment: target.environmentName, account: context.account, token: token))
                if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: context.account.id, statusCode: response.statusCode) {
                    issues.append(issue)
                    continue
                }

                snapshots.append(contentsOf: try GitLabDeploymentsParser.snapshots(from: response.data, account: context.account, target: target, project: project, now: context.now()))
            } catch let error as APIClientError {
                issues.append(ProviderUtilities.issue(for: error, provider: id, accountID: context.account.id))
            } catch {
                issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "GitLab deployments response could not be parsed."))
            }
        }

        return ProviderRefreshResult(snapshots: ProviderUtilities.deduplicated(snapshots), issues: issues)
    }

    private func makeDeploymentsRequest(project: String, environment: String?, account: ProviderAccount, token: String) throws -> URLRequest {
        let apiBaseURL = account.teamSlug.flatMap(URL.init(string:)) ?? baseURL
        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidResponse
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = basePath.isEmpty ? "" : "/\(basePath)"
        components.percentEncodedPath = "\(prefix)/projects/\(percentEncodedPathComponent(project))/deployments"
        var queryItems = [
            URLQueryItem(name: "per_page", value: "\(limit)"),
            URLQueryItem(name: "order_by", value: "updated_at"),
            URLQueryItem(name: "sort", value: "desc")
        ]
        if let environment {
            queryItems.append(URLQueryItem(name: "environment", value: environment))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw APIClientError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DeployBar/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func percentEncodedPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public enum GitLabDeploymentsParser {
    public static func snapshots(from data: Data, account: ProviderAccount, target: MonitoredTarget, project: String, now: Date = Date()) throws -> [DeploymentSnapshot] {
        let deployments = try JSONDecoder.deployBar.decode([GitLabDeployment].self, from: data)
        return deployments.map { deployment in
            let status = DeploymentStatusMapper.gitlabDeploymentStatus(deployment.status)
            let finishedAt = terminal(status) ? deployment.updatedAt : nil
            let environmentName = deployment.environment?.name ?? target.environmentName

            return DeploymentSnapshot(
                id: "gitlab:\(account.id):\(deployment.id)",
                provider: .gitlab,
                projectName: target.projectName ?? project,
                serviceName: deployment.deployable?.name,
                environmentName: environmentName,
                branch: deployment.ref ?? target.branch,
                commitSha: deployment.sha,
                commitMessage: deployment.deployable?.commit?.title,
                actor: deployment.user?.username ?? deployment.deployable?.user?.username,
                status: status,
                createdAt: deployment.createdAt,
                startedAt: deployment.createdAt,
                finishedAt: finishedAt,
                duration: ProviderUtilities.duration(startedAt: deployment.createdAt, finishedAt: finishedAt),
                dashboardURL: dashboardURL(project: target.projectName ?? project, deploymentID: deployment.id),
                deploymentURL: deployment.environment?.externalURL,
                errorMessage: status == .failed ? deployment.deployable?.status : nil,
                lastUpdatedAt: now
            )
        }
    }

    private static func terminal(_ status: DeploymentStatus) -> Bool {
        switch status {
        case .success, .ready, .failed, .error, .canceled, .removed:
            return true
        default:
            return false
        }
    }

    private static func dashboardURL(project: String, deploymentID: Int) -> URL? {
        guard project.contains("/") else { return nil }
        return URL(string: "https://gitlab.com/\(project)/-/deployments/\(deploymentID)")
    }
}

private struct GitLabDeployment: Decodable {
    var id: Int
    var iid: Int?
    var ref: String?
    var sha: String?
    var status: String
    var createdAt: Date?
    var updatedAt: Date?
    var user: GitLabUser?
    var environment: GitLabEnvironment?
    var deployable: GitLabDeployable?

    enum CodingKeys: String, CodingKey {
        case id
        case iid
        case ref
        case sha
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case user
        case environment
        case deployable
    }
}

private struct GitLabEnvironment: Decodable {
    var name: String?
    var externalURL: URL?

    enum CodingKeys: String, CodingKey {
        case name
        case externalURL = "external_url"
    }
}

private struct GitLabDeployable: Decodable {
    var name: String?
    var status: String?
    var user: GitLabUser?
    var commit: GitLabCommit?
}

private struct GitLabCommit: Decodable {
    var title: String?
}

private struct GitLabUser: Decodable {
    var username: String?
}
