import Foundation

public struct CloudflarePagesProvider: DeploymentProvider {
    public let id: ProviderID = .cloudflarePages
    public let displayName = "Cloudflare Pages"

    private let client: any HTTPClient
    private let baseURL: URL
    private let limit: Int
    private let projectLimit: Int

    public init(
        client: any HTTPClient = APIClient(),
        baseURL: URL = URL(string: "https://api.cloudflare.com/client/v4")!,
        limit: Int = 10,
        projectLimit: Int = 20
    ) {
        self.client = client
        self.baseURL = baseURL
        self.limit = limit
        self.projectLimit = projectLimit
    }

    public func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult {
        guard let token = context.token, !token.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Cloudflare API token is not configured.")]
            )
        }
        guard let cloudflareAccountID = context.account.teamID, !cloudflareAccountID.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Cloudflare Pages requires an account ID.")]
            )
        }

        do {
            let targets = try await targets(for: context.account, cloudflareAccountID: cloudflareAccountID, token: token)
            var snapshots: [DeploymentSnapshot] = []
            var issues: [ProviderIssue] = []

            for target in targets {
                guard let projectName = target.projectName ?? target.projectID else {
                    issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Cloudflare Pages target needs a project name."))
                    continue
                }

                let response = try await client.send(makeDeploymentsRequest(accountID: cloudflareAccountID, projectName: projectName, token: token))
                if let issue = issue(from: response, accountID: context.account.id) {
                    issues.append(issue)
                    continue
                }

                snapshots.append(contentsOf: try CloudflarePagesParser.snapshots(from: response.data, account: context.account, target: target, now: context.now()))
            }

            return ProviderRefreshResult(snapshots: ProviderUtilities.deduplicated(snapshots), issues: issues)
        } catch let error as CloudflarePagesIssue {
            return ProviderRefreshResult(snapshots: [], issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderRefreshResult(snapshots: [], issues: [ProviderUtilities.issue(for: error, provider: id, accountID: context.account.id)])
        } catch {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "Cloudflare Pages API response could not be parsed.")]
            )
        }
    }

    public func discoverAccounts(token: String) async -> ProviderScopeDiscoveryResult {
        guard !token.isEmpty else {
            return ProviderScopeDiscoveryResult(
                issues: [ProviderIssue(provider: id, kind: .notConfigured, message: "Cloudflare API token is not configured.")]
            )
        }

        do {
            let response = try await client.send(makeMembershipsRequest(token: token))
            if let issue = issue(from: response, accountID: nil) {
                return ProviderScopeDiscoveryResult(issues: [issue])
            }

            let scopes = try CloudflarePagesParser.membershipAccounts(from: response.data).map { account in
                ProviderScopeResource(id: account.id, name: account.name)
            }
            return ProviderScopeDiscoveryResult(scopes: scopes)
        } catch let error as APIClientError {
            return ProviderScopeDiscoveryResult(
                issues: [ProviderUtilities.issue(for: error, provider: id, accountID: nil)]
            )
        } catch {
            return ProviderScopeDiscoveryResult(
                issues: [ProviderIssue(provider: id, kind: .apiChanged, message: "Cloudflare account discovery response could not be parsed.")]
            )
        }
    }

    public func discoverTargets(token: String, account: ProviderAccount) async -> ProviderTargetDiscoveryResult {
        guard !token.isEmpty else {
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .notConfigured, message: "Cloudflare API token is not configured.")]
            )
        }
        guard let cloudflareAccountID = account.teamID, !cloudflareAccountID.isEmpty else {
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .notConfigured, message: "Cloudflare Pages requires an account ID.")]
            )
        }

        do {
            return ProviderTargetDiscoveryResult(targets: try await targets(for: account, cloudflareAccountID: cloudflareAccountID, token: token))
        } catch let error as CloudflarePagesIssue {
            return ProviderTargetDiscoveryResult(issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderTargetDiscoveryResult(issues: [ProviderUtilities.issue(for: error, provider: id, accountID: account.id)])
        } catch {
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .apiChanged, message: "Cloudflare Pages discovery response could not be parsed.")]
            )
        }
    }

    private func targets(for account: ProviderAccount, cloudflareAccountID: String, token: String) async throws -> [MonitoredTarget] {
        if !account.monitoredTargets.isEmpty {
            return account.monitoredTargets
        }

        let response = try await client.send(makeProjectsRequest(accountID: cloudflareAccountID, token: token))
        if let issue = issue(from: response, accountID: account.id) {
            throw CloudflarePagesIssue(issue)
        }

        return try CloudflarePagesParser.projects(from: response.data).prefix(projectLimit).map { project in
            MonitoredTarget(projectID: project.id, projectName: project.name, branch: project.productionBranch)
        }
    }

    private func makeMembershipsRequest(token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("memberships"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "per_page", value: "\(projectLimit)")]
        guard let url = components?.url else { throw APIClientError.invalidResponse }
        return authenticatedRequest(url: url, token: token)
    }

    private func makeProjectsRequest(accountID: String, token: String) throws -> URLRequest {
        let components = URLComponents(url: baseURL.appendingPathComponent("accounts").appendingPathComponent(accountID).appendingPathComponent("pages").appendingPathComponent("projects"), resolvingAgainstBaseURL: false)
        guard let url = components?.url else { throw APIClientError.invalidResponse }
        return authenticatedRequest(url: url, token: token)
    }

    private func makeDeploymentsRequest(accountID: String, projectName: String, token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("accounts").appendingPathComponent(accountID).appendingPathComponent("pages").appendingPathComponent("projects").appendingPathComponent(projectName).appendingPathComponent("deployments"), resolvingAgainstBaseURL: false)
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

    private func issue(from response: HTTPResponse, accountID: String?) -> ProviderIssue? {
        guard let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: accountID, statusCode: response.statusCode) else {
            return nil
        }
        guard let message = CloudflarePagesParser.errorMessage(from: response.data) else {
            return issue
        }
        return ProviderIssue(
            provider: id,
            accountID: accountID,
            kind: issue.kind,
            message: "\(displayName) API returned HTTP \(response.statusCode): \(message)"
        )
    }
}

public enum CloudflarePagesParser {
    public static func snapshots(from data: Data, account: ProviderAccount, target: MonitoredTarget, now: Date = Date()) throws -> [DeploymentSnapshot] {
        let response = try JSONDecoder.deployBar.decode(CloudflarePagesResponse<[CloudflarePagesDeployment]>.self, from: data)
        return response.result.map { deployment in
            let status = deployment.isSkipped == true
                ? DeploymentStatus.skipped
                : DeploymentStatusMapper.cloudflarePagesStatus(deployment.latestStage?.status ?? deployment.stageStatus ?? deployment.status ?? "")
            let metadata = deployment.deploymentTrigger?.metadata
            let finishedAt = finishedAt(status: status, deployment: deployment)
            let projectName = deployment.projectName ?? target.projectName ?? target.projectID ?? "Pages Project"

            return DeploymentSnapshot(
                id: "cloudflarePages:\(account.id):\(deployment.id)",
                provider: .cloudflarePages,
                projectName: projectName,
                environmentName: deployment.environment ?? target.environmentName,
                branch: metadata?.branch ?? target.branch,
                commitSha: metadata?.commitHash,
                commitMessage: metadata?.commitMessage,
                actor: metadata?.commitAuthor,
                status: status,
                createdAt: deployment.createdOn,
                startedAt: deployment.createdOn,
                finishedAt: finishedAt,
                duration: ProviderUtilities.duration(startedAt: deployment.createdOn, finishedAt: finishedAt),
                dashboardURL: deployment.dashboardURL,
                deploymentURL: ProviderUtilities.normalizedURL(from: deployment.url ?? deployment.aliases?.first),
                errorMessage: deployment.latestStage?.endedOn == nil && status == .failed ? deployment.latestStage?.name : nil,
                lastUpdatedAt: now
            )
        }
    }

    static func projects(from data: Data) throws -> [CloudflarePagesProject] {
        let response = try JSONDecoder.deployBar.decode(CloudflarePagesResponse<[CloudflarePagesProject]>.self, from: data)
        return response.result
    }

    static func membershipAccounts(from data: Data) throws -> [CloudflareAccountResource] {
        let response = try JSONDecoder.deployBar.decode(CloudflarePagesResponse<[CloudflareMembershipResource]>.self, from: data)
        return response.result.compactMap(\.account)
    }

    static func errorMessage(from data: Data) -> String? {
        guard
            let response = try? JSONDecoder.deployBar.decode(CloudflarePagesErrorResponse.self, from: data)
        else {
            return nil
        }

        let messages = response.errors.compactMap { error -> String? in
            let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return nil }
            if let code = error.code {
                return "\(message) (\(code))"
            }
            return message
        }
        guard !messages.isEmpty else { return nil }
        return messages.joined(separator: "; ")
    }

    private static func finishedAt(status: DeploymentStatus, deployment: CloudflarePagesDeployment) -> Date? {
        switch status {
        case .success, .ready, .failed, .error, .canceled, .skipped:
            return deployment.latestStage?.endedOn ?? deployment.modifiedOn
        default:
            return nil
        }
    }
}

private struct CloudflarePagesResponse<Result: Decodable>: Decodable {
    var success: Bool?
    var result: Result
}

private struct CloudflarePagesErrorResponse: Decodable {
    var errors: [CloudflarePagesAPIError]
}

private struct CloudflarePagesAPIError: Decodable {
    var code: Int?
    var message: String
}

struct CloudflarePagesProject: Decodable {
    var id: String?
    var name: String
    var productionBranch: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case productionBranch = "production_branch"
    }
}

struct CloudflareAccountResource: Decodable {
    var id: String
    var name: String
}

private struct CloudflareMembershipResource: Decodable {
    var account: CloudflareAccountResource?
}

private struct CloudflarePagesDeployment: Decodable {
    var id: String
    var projectName: String?
    var environment: String?
    var url: String?
    var aliases: [String]?
    var createdOn: Date?
    var modifiedOn: Date?
    var dashboardURL: URL?
    var latestStage: CloudflarePagesStage?
    var deploymentTrigger: CloudflarePagesDeploymentTrigger?
    var stageStatus: String?
    var status: String?
    var isSkipped: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case projectName = "project_name"
        case environment
        case url
        case aliases
        case createdOn = "created_on"
        case modifiedOn = "modified_on"
        case dashboardURL = "dashboard_url"
        case latestStage = "latest_stage"
        case deploymentTrigger = "deployment_trigger"
        case stageStatus = "stage_status"
        case status
        case isSkipped = "is_skipped"
    }
}

private struct CloudflarePagesStage: Decodable {
    var name: String?
    var status: String?
    var endedOn: Date?

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case endedOn = "ended_on"
    }
}

private struct CloudflarePagesDeploymentTrigger: Decodable {
    var metadata: CloudflarePagesMetadata?
}

private struct CloudflarePagesMetadata: Decodable {
    var branch: String?
    var commitHash: String?
    var commitMessage: String?
    var commitAuthor: String?

    enum CodingKeys: String, CodingKey {
        case branch
        case commitHash = "commit_hash"
        case commitMessage = "commit_message"
        case commitAuthor = "commit_author"
    }
}

private struct CloudflarePagesIssue: Error {
    var issue: ProviderIssue

    init(_ issue: ProviderIssue) {
        self.issue = issue
    }
}
