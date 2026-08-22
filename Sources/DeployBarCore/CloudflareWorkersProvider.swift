import Foundation

public struct CloudflareWorkersProvider: DeploymentProvider {
    public let id: ProviderID = .cloudflareWorkers
    public let displayName = "Cloudflare Workers"

    private let client: any HTTPClient
    private let baseURL: URL
    private let limit: Int
    private let workerLimit: Int

    public init(
        client: any HTTPClient = APIClient(),
        baseURL: URL = URL(string: "https://api.cloudflare.com/client/v4")!,
        limit: Int = 10,
        workerLimit: Int = 20
    ) {
        self.client = client
        self.baseURL = baseURL
        self.limit = limit
        self.workerLimit = workerLimit
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
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Cloudflare Workers requires an account ID.")]
            )
        }

        do {
            let targets = try await targets(for: context.account, cloudflareAccountID: cloudflareAccountID, token: token)
            var snapshots: [DeploymentSnapshot] = []
            var issues: [ProviderIssue] = []

            for target in targets {
                guard let workerName = target.projectName?.trimmingCharacters(in: .whitespacesAndNewlines), !workerName.isEmpty else {
                    issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Cloudflare Workers target needs a Worker name."))
                    continue
                }

                var buildSnapshots: [DeploymentSnapshot] = []
                if let workerTag = target.projectID, !workerTag.isEmpty {
                    let response = try await client.send(makeBuildsRequest(accountID: cloudflareAccountID, workerTag: workerTag, token: token))
                    if response.statusCode == 404 {
                        buildSnapshots = []
                    } else if let issue = issue(from: response, accountID: context.account.id) {
                        issues.append(issue)
                    } else {
                        do {
                            buildSnapshots = try CloudflareWorkersParser.buildSnapshots(
                                from: response.data,
                                account: context.account,
                                target: target,
                                limit: limit,
                                now: context.now()
                            )
                        } catch {
                            issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "Cloudflare Workers Builds API response could not be parsed."))
                        }
                    }
                }

                if !buildSnapshots.isEmpty {
                    snapshots.append(contentsOf: buildSnapshots)
                    continue
                }

                let response = try await client.send(makeDeploymentsRequest(accountID: cloudflareAccountID, workerName: workerName, token: token))
                if let issue = issue(from: response, accountID: context.account.id) {
                    issues.append(issue)
                    continue
                }

                snapshots.append(contentsOf: try CloudflareWorkersParser.deploymentSnapshots(
                    from: response.data,
                    account: context.account,
                    target: target,
                    limit: limit,
                    now: context.now()
                ))
            }

            return ProviderRefreshResult(snapshots: ProviderUtilities.deduplicated(snapshots), issues: issues)
        } catch let error as CloudflareWorkersIssue {
            return ProviderRefreshResult(snapshots: [], issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderRefreshResult(snapshots: [], issues: [ProviderUtilities.issue(for: error, provider: id, accountID: context.account.id)])
        } catch {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "Cloudflare Workers API response could not be parsed.")]
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

            let scopes = try CloudflareWorkersParser.membershipAccounts(from: response.data).map { account in
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
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .notConfigured, message: "Cloudflare Workers requires an account ID.")]
            )
        }

        do {
            return ProviderTargetDiscoveryResult(targets: try await targets(for: account, cloudflareAccountID: cloudflareAccountID, token: token))
        } catch let error as CloudflareWorkersIssue {
            return ProviderTargetDiscoveryResult(issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderTargetDiscoveryResult(issues: [ProviderUtilities.issue(for: error, provider: id, accountID: account.id)])
        } catch {
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .apiChanged, message: "Cloudflare Workers discovery response could not be parsed.")]
            )
        }
    }

    private func targets(for account: ProviderAccount, cloudflareAccountID: String, token: String) async throws -> [MonitoredTarget] {
        if !account.monitoredTargets.isEmpty {
            return account.monitoredTargets
        }

        let response = try await client.send(makeWorkersRequest(accountID: cloudflareAccountID, token: token))
        if let issue = issue(from: response, accountID: account.id) {
            throw CloudflareWorkersIssue(issue)
        }

        return try CloudflareWorkersParser.workers(from: response.data).prefix(workerLimit).compactMap { worker in
            guard let workerName = worker.id?.trimmingCharacters(in: .whitespacesAndNewlines), !workerName.isEmpty else {
                return nil
            }
            return MonitoredTarget(projectID: worker.tag, projectName: workerName)
        }
    }

    private func makeMembershipsRequest(token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("memberships"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "per_page", value: "\(workerLimit)")]
        guard let url = components?.url else { throw APIClientError.invalidResponse }
        return authenticatedRequest(url: url, token: token)
    }

    private func makeWorkersRequest(accountID: String, token: String) throws -> URLRequest {
        let url = baseURL
            .appendingPathComponent("accounts")
            .appendingPathComponent(accountID)
            .appendingPathComponent("workers")
            .appendingPathComponent("scripts")
        return authenticatedRequest(url: url, token: token)
    }

    private func makeBuildsRequest(accountID: String, workerTag: String, token: String) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("accounts")
                .appendingPathComponent(accountID)
                .appendingPathComponent("builds")
                .appendingPathComponent("workers")
                .appendingPathComponent(workerTag)
                .appendingPathComponent("builds"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: "\(limit)")
        ]
        guard let url = components?.url else { throw APIClientError.invalidResponse }
        return authenticatedRequest(url: url, token: token)
    }

    private func makeDeploymentsRequest(accountID: String, workerName: String, token: String) throws -> URLRequest {
        let url = baseURL
            .appendingPathComponent("accounts")
            .appendingPathComponent(accountID)
            .appendingPathComponent("workers")
            .appendingPathComponent("scripts")
            .appendingPathComponent(workerName)
            .appendingPathComponent("deployments")
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
        guard let message = CloudflareWorkersParser.errorMessage(from: response.data) else {
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

public enum CloudflareWorkersParser {
    public static func buildSnapshots(
        from data: Data,
        account: ProviderAccount,
        target: MonitoredTarget,
        limit: Int = 10,
        now: Date = Date()
    ) throws -> [DeploymentSnapshot] {
        let response = try JSONDecoder.deployBar.decode(CloudflareWorkersResponse<[CloudflareWorkersBuild]>.self, from: data)
        let workerName = target.projectName ?? target.projectID ?? "Worker"

        return response.result.prefix(limit).compactMap { build in
            guard let buildUUID = build.buildUUID?.trimmingCharacters(in: .whitespacesAndNewlines), !buildUUID.isEmpty else {
                return nil
            }
            let metadata = build.buildTriggerMetadata
            if let targetBranch = target.branch?.trimmingCharacters(in: .whitespacesAndNewlines),
               !targetBranch.isEmpty,
               metadata?.branch?.caseInsensitiveCompare(targetBranch) != .orderedSame
            {
                return nil
            }

            let status = DeploymentStatusMapper.cloudflareWorkersBuildStatus(build.status, outcome: build.buildOutcome)
            let startedAt = build.runningOn ?? build.initializingOn ?? build.createdOn
            let finishedAt = status.isCloudflareWorkersTerminal ? build.stoppedOn ?? build.modifiedOn : nil

            return DeploymentSnapshot(
                id: "cloudflareWorkers:\(account.id):build:\(buildUUID)",
                provider: .cloudflareWorkers,
                projectName: workerName,
                environmentName: target.environmentName,
                branch: metadata?.branch ?? target.branch,
                commitSha: metadata?.commitHash,
                commitMessage: metadata?.commitMessage,
                actor: metadata?.author,
                status: status,
                createdAt: build.createdOn,
                startedAt: startedAt,
                finishedAt: finishedAt,
                duration: ProviderUtilities.duration(startedAt: startedAt, finishedAt: finishedAt),
                dashboardURL: URL(string: "https://dash.cloudflare.com"),
                errorMessage: status == .failed ? "Cloudflare Workers build failed." : nil,
                lastUpdatedAt: now
            )
        }
    }

    public static func deploymentSnapshots(
        from data: Data,
        account: ProviderAccount,
        target: MonitoredTarget,
        limit: Int = 10,
        now: Date = Date()
    ) throws -> [DeploymentSnapshot] {
        let response = try JSONDecoder.deployBar.decode(CloudflareWorkersResponse<CloudflareWorkersDeploymentsResult>.self, from: data)
        let workerName = target.projectName ?? target.projectID ?? "Worker"

        if let targetBranch = target.branch?.trimmingCharacters(in: .whitespacesAndNewlines), !targetBranch.isEmpty {
            return []
        }

        return response.result.deployments.prefix(limit).map { deployment in
            DeploymentSnapshot(
                id: "cloudflareWorkers:\(account.id):deployment:\(deployment.id)",
                provider: .cloudflareWorkers,
                projectName: workerName,
                environmentName: target.environmentName ?? "Production",
                commitMessage: deployment.annotations?.workersMessage,
                actor: deployment.authorEmail,
                status: .success,
                createdAt: deployment.createdOn,
                startedAt: deployment.createdOn,
                finishedAt: deployment.createdOn,
                dashboardURL: URL(string: "https://dash.cloudflare.com"),
                lastUpdatedAt: now
            )
        }
    }

    static func workers(from data: Data) throws -> [CloudflareWorkerResource] {
        try JSONDecoder.deployBar.decode(CloudflareWorkersResponse<[CloudflareWorkerResource]>.self, from: data).result
    }

    static func membershipAccounts(from data: Data) throws -> [CloudflareWorkersAccountResource] {
        let response = try JSONDecoder.deployBar.decode(CloudflareWorkersResponse<[CloudflareWorkersMembershipResource]>.self, from: data)
        return response.result.compactMap(\.account)
    }

    static func errorMessage(from data: Data) -> String? {
        guard let response = try? JSONDecoder.deployBar.decode(CloudflareWorkersErrorResponse.self, from: data) else {
            return nil
        }

        let messages = response.errors.compactMap { error -> String? in
            guard let rawMessage = error.message else { return nil }
            let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return nil }
            if let code = error.code {
                return "\(message) (\(code))"
            }
            return message
        }
        guard !messages.isEmpty else { return nil }
        return messages.joined(separator: "; ")
    }
}

private struct CloudflareWorkersResponse<Result: Decodable>: Decodable {
    var success: Bool?
    var result: Result
}

private struct CloudflareWorkersErrorResponse: Decodable {
    var errors: [CloudflareWorkersAPIError]
}

private struct CloudflareWorkersAPIError: Decodable {
    var code: Int?
    var message: String?
}

struct CloudflareWorkerResource: Decodable {
    var id: String?
    var tag: String?
}

struct CloudflareWorkersAccountResource: Decodable {
    var id: String
    var name: String
}

private struct CloudflareWorkersMembershipResource: Decodable {
    var account: CloudflareWorkersAccountResource?
}

private struct CloudflareWorkersBuild: Decodable {
    var buildUUID: String?
    var buildOutcome: String?
    var buildTriggerMetadata: CloudflareWorkersBuildMetadata?
    var createdOn: Date?
    var initializingOn: Date?
    var modifiedOn: Date?
    var runningOn: Date?
    var status: String?
    var stoppedOn: Date?

    enum CodingKeys: String, CodingKey {
        case buildUUID = "build_uuid"
        case buildOutcome = "build_outcome"
        case buildTriggerMetadata = "build_trigger_metadata"
        case createdOn = "created_on"
        case initializingOn = "initializing_on"
        case modifiedOn = "modified_on"
        case runningOn = "running_on"
        case status
        case stoppedOn = "stopped_on"
    }
}

private struct CloudflareWorkersBuildMetadata: Decodable {
    var author: String?
    var branch: String?
    var commitHash: String?
    var commitMessage: String?

    enum CodingKeys: String, CodingKey {
        case author
        case branch
        case commitHash = "commit_hash"
        case commitMessage = "commit_message"
    }
}

private struct CloudflareWorkersDeploymentsResult: Decodable {
    var deployments: [CloudflareWorkersDeployment]
}

private struct CloudflareWorkersDeployment: Decodable {
    var id: String
    var createdOn: Date?
    var source: String?
    var annotations: CloudflareWorkersDeploymentAnnotations?
    var authorEmail: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdOn = "created_on"
        case source
        case annotations
        case authorEmail = "author_email"
    }
}

private struct CloudflareWorkersDeploymentAnnotations: Decodable {
    var workersMessage: String?
    var workersTriggeredBy: String?

    enum CodingKeys: String, CodingKey {
        case workersMessage = "workers/message"
        case workersTriggeredBy = "workers/triggered_by"
    }
}

private struct CloudflareWorkersIssue: Error {
    var issue: ProviderIssue

    init(_ issue: ProviderIssue) {
        self.issue = issue
    }
}

private extension DeploymentStatus {
    var isCloudflareWorkersTerminal: Bool {
        switch self {
        case .success, .ready, .failed, .error, .canceled, .skipped:
            return true
        case .queued, .waiting, .initializing, .building, .deploying, .crashed, .removed, .sleeping, .unknown:
            return false
        }
    }
}
