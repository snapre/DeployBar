import Foundation

public struct VercelProvider: DeploymentProvider {
    public let id: ProviderID = .vercel
    public let displayName = "Vercel"

    private let client: any HTTPClient
    private let baseURL: URL
    private let limit: Int

    public init(
        client: any HTTPClient = APIClient(),
        baseURL: URL = URL(string: "https://api.vercel.com")!,
        limit: Int = 20
    ) {
        self.client = client
        self.baseURL = baseURL
        self.limit = limit
    }

    public func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult {
        guard let token = context.token, !token.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Vercel API token is not configured.")]
            )
        }

        var snapshots: [DeploymentSnapshot] = []
        var issues: [ProviderIssue] = []
        let targets = context.account.monitoredTargets.isEmpty ? [nil] : context.account.monitoredTargets.map(Optional.some)

        for target in targets {
            do {
                let request = try makeRequest(account: context.account, token: token, target: target)
                let response = try await client.send(request)

                if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: context.account.id, statusCode: response.statusCode) {
                    issues.append(issue)
                    continue
                }

                let parsed = try VercelParser.snapshots(from: response.data, account: context.account, now: context.now())
                snapshots.append(contentsOf: parsed)
            } catch let error as APIClientError {
                issues.append(issue(for: error, accountID: context.account.id))
            } catch {
                issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "Vercel API response could not be parsed."))
            }
        }

        return ProviderRefreshResult(snapshots: Self.deduplicated(snapshots), issues: issues)
    }

    public func discoverResources(token: String, account: ProviderAccount) async -> VercelDiscoveryResult {
        guard !token.isEmpty else {
            return VercelDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .notConfigured, message: "Vercel API token is not configured.")]
            )
        }

        do {
            let projectsResponse = try await client.send(makeProjectsRequest(account: account, token: token))
            if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: account.id, statusCode: projectsResponse.statusCode) {
                return VercelDiscoveryResult(issues: [issue])
            }

            var projects = try VercelDiscoveryParser.projects(from: projectsResponse.data)
            let hintsResponse = try await client.send(makeDeploymentsRequest(account: account, token: token, target: nil, limit: 100))
            if hintsResponse.statusCode == 200, let hints = try? VercelDiscoveryParser.deploymentHints(from: hintsResponse.data) {
                projects = projects.map { project in
                    var copy = project
                    let projectHints = hints[project.id] ?? hints[project.name]
                    copy.environments = sorted(projectHints?.environments ?? [])
                    copy.branches = sorted(projectHints?.branches ?? [])
                    return copy
                }
            }

            return VercelDiscoveryResult(projects: projects)
        } catch let error as APIClientError {
            return VercelDiscoveryResult(issues: [issue(for: error, accountID: account.id)])
        } catch {
            return VercelDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .apiChanged, message: "Vercel discovery response could not be parsed.")]
            )
        }
    }

    private func makeRequest(account: ProviderAccount, token: String, target: MonitoredTarget?) throws -> URLRequest {
        try makeDeploymentsRequest(account: account, token: token, target: target, limit: limit)
    }

    private func makeDeploymentsRequest(account: ProviderAccount, token: String, target: MonitoredTarget?, limit: Int) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("v6").appendingPathComponent("deployments"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let teamID = account.teamID {
            queryItems.append(URLQueryItem(name: "teamId", value: teamID))
        }
        if let teamSlug = account.teamSlug {
            queryItems.append(URLQueryItem(name: "slug", value: teamSlug))
        }
        if let project = target?.projectID ?? target?.projectName {
            queryItems.append(URLQueryItem(name: "projectId", value: project))
        }
        if let environment = target?.environmentName {
            queryItems.append(URLQueryItem(name: "target", value: environment))
        }
        if let branch = target?.branch {
            queryItems.append(URLQueryItem(name: "branch", value: branch))
        }

        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DeployBar/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func makeProjectsRequest(account: ProviderAccount, token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("v10").appendingPathComponent("projects"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if let teamID = account.teamID {
            queryItems.append(URLQueryItem(name: "teamId", value: teamID))
        }
        if let teamSlug = account.teamSlug {
            queryItems.append(URLQueryItem(name: "slug", value: teamSlug))
        }
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw APIClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DeployBar/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func issue(for error: APIClientError, accountID: String) -> ProviderIssue {
        switch error {
        case .invalidResponse:
            ProviderIssue(provider: id, accountID: accountID, kind: .apiChanged, message: "Vercel API returned an invalid response.")
        case .transport:
            ProviderIssue(provider: id, accountID: accountID, kind: .network, message: "Could not reach Vercel API.")
        }
    }

    private static func deduplicated(_ snapshots: [DeploymentSnapshot]) -> [DeploymentSnapshot] {
        var seen = Set<String>()
        return snapshots.filter { snapshot in
            seen.insert(snapshot.id).inserted
        }
    }

    private func sorted(_ values: Set<String>) -> [String] {
        values.sorted { lhs, rhs in
            if lhs == "production" { return true }
            if rhs == "production" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }
}
