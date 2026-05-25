import Foundation

public struct NetlifyProvider: DeploymentProvider {
    public let id: ProviderID = .netlify
    public let displayName = "Netlify"

    private let client: any HTTPClient
    private let baseURL: URL
    private let limit: Int
    private let siteLimit: Int

    public init(
        client: any HTTPClient = APIClient(),
        baseURL: URL = URL(string: "https://api.netlify.com")!,
        limit: Int = 10,
        siteLimit: Int = 20
    ) {
        self.client = client
        self.baseURL = baseURL
        self.limit = limit
        self.siteLimit = siteLimit
    }

    public func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult {
        guard let token = context.token, !token.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Netlify API token is not configured.")]
            )
        }

        do {
            let targets = try await targets(for: context.account, token: token)
            var snapshots: [DeploymentSnapshot] = []
            var issues: [ProviderIssue] = []

            for target in targets {
                guard let siteID = target.projectID ?? target.projectName else {
                    issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Netlify target needs a site ID or site name."))
                    continue
                }

                let response = try await client.send(makeDeploysRequest(siteID: siteID, token: token))
                if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: context.account.id, statusCode: response.statusCode) {
                    issues.append(issue)
                    continue
                }

                snapshots.append(contentsOf: try NetlifyParser.snapshots(from: response.data, account: context.account, target: target, now: context.now()))
            }

            return ProviderRefreshResult(snapshots: ProviderUtilities.deduplicated(snapshots), issues: issues)
        } catch let error as ProviderDiscoveryIssue {
            return ProviderRefreshResult(snapshots: [], issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderRefreshResult(snapshots: [], issues: [ProviderUtilities.issue(for: error, provider: id, accountID: context.account.id)])
        } catch {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "Netlify API response could not be parsed.")]
            )
        }
    }

    public func discoverTargets(token: String, account: ProviderAccount) async -> ProviderTargetDiscoveryResult {
        guard !token.isEmpty else {
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .notConfigured, message: "Netlify API token is not configured.")]
            )
        }

        do {
            return ProviderTargetDiscoveryResult(targets: try await targets(for: account, token: token))
        } catch let error as ProviderDiscoveryIssue {
            return ProviderTargetDiscoveryResult(issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderTargetDiscoveryResult(issues: [ProviderUtilities.issue(for: error, provider: id, accountID: account.id)])
        } catch {
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .apiChanged, message: "Netlify discovery response could not be parsed.")]
            )
        }
    }

    private func targets(for account: ProviderAccount, token: String) async throws -> [MonitoredTarget] {
        if !account.monitoredTargets.isEmpty {
            return account.monitoredTargets
        }

        let response = try await client.send(makeSitesRequest(token: token))
        if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: account.id, statusCode: response.statusCode) {
            throw ProviderDiscoveryIssue(issue)
        }

        return try NetlifyParser.sites(from: response.data).prefix(siteLimit).map { site in
            MonitoredTarget(projectID: site.id, projectName: site.name)
        }
    }

    private func makeSitesRequest(token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("api").appendingPathComponent("v1").appendingPathComponent("sites"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "per_page", value: "\(siteLimit)")]
        guard let url = components?.url else { throw APIClientError.invalidResponse }
        return authenticatedRequest(url: url, token: token)
    }

    private func makeDeploysRequest(siteID: String, token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("api").appendingPathComponent("v1").appendingPathComponent("sites").appendingPathComponent(siteID).appendingPathComponent("deploys"), resolvingAgainstBaseURL: false)
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

public enum NetlifyParser {
    public static func snapshots(from data: Data, account: ProviderAccount, target: MonitoredTarget, now: Date = Date()) throws -> [DeploymentSnapshot] {
        let deployments = try JSONDecoder.deployBar.decode([NetlifyDeployment].self, from: data)
        return deployments.map { deployment in
            let status = status(for: deployment)
            let finishedAt = finishedAt(status: status, deployment: deployment)
            let siteName = target.projectName ?? deployment.name ?? deployment.siteName ?? target.projectID ?? "Netlify Site"

            return DeploymentSnapshot(
                id: "netlify:\(account.id):\(deployment.id)",
                provider: .netlify,
                projectName: siteName,
                environmentName: deployment.context ?? target.environmentName,
                branch: deployment.branch ?? target.branch,
                commitSha: deployment.commitRef,
                commitMessage: deployment.title,
                actor: deployment.committer,
                status: status,
                createdAt: deployment.createdAt,
                startedAt: deployment.createdAt,
                finishedAt: finishedAt,
                duration: ProviderUtilities.duration(startedAt: deployment.createdAt, finishedAt: finishedAt),
                dashboardURL: deployment.adminUrl,
                deploymentURL: ProviderUtilities.normalizedURL(from: deployment.deploySslUrl ?? deployment.deployUrl ?? deployment.sslUrl ?? deployment.url),
                errorMessage: status == .failed ? deployment.errorMessage : nil,
                lastUpdatedAt: now
            )
        }
    }

    static func sites(from data: Data) throws -> [NetlifySite] {
        try JSONDecoder.deployBar.decode([NetlifySite].self, from: data)
    }

    private static func finishedAt(status: DeploymentStatus, deployment: NetlifyDeployment) -> Date? {
        switch status {
        case .ready, .success, .failed, .error, .canceled, .skipped:
            return deployment.publishedAt ?? deployment.updatedAt
        default:
            return nil
        }
    }

    private static func status(for deployment: NetlifyDeployment) -> DeploymentStatus {
        let status = DeploymentStatusMapper.netlifyStatus(deployment.state)
        guard status == .failed,
              let errorMessage = deployment.errorMessage?.lowercased(),
              errorMessage.contains("no content change")
        else {
            return status
        }

        return .skipped
    }
}

struct NetlifySite: Decodable {
    var id: String
    var name: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

private struct NetlifyDeployment: Decodable {
    var id: String
    var siteID: String?
    var siteName: String?
    var name: String?
    var state: String
    var context: String?
    var branch: String?
    var commitRef: String?
    var title: String?
    var committer: String?
    var url: String?
    var sslUrl: String?
    var deployUrl: String?
    var deploySslUrl: String?
    var adminUrl: URL?
    var createdAt: Date?
    var updatedAt: Date?
    var publishedAt: Date?
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case siteID = "site_id"
        case siteName = "site_name"
        case name
        case state
        case context
        case branch
        case commitRef = "commit_ref"
        case title
        case committer
        case url
        case sslUrl = "ssl_url"
        case deployUrl = "deploy_url"
        case deploySslUrl = "deploy_ssl_url"
        case adminUrl = "admin_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case publishedAt = "published_at"
        case errorMessage = "error_message"
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        siteID = try container.decodeIfPresent(String.self, forKey: .siteID)
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        state = try container.decode(String.self, forKey: .state)
        context = try container.decodeIfPresent(String.self, forKey: .context)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        commitRef = try container.decodeIfPresent(String.self, forKey: .commitRef)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        committer = try container.decodeIfPresent(String.self, forKey: .committer)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        sslUrl = try container.decodeIfPresent(String.self, forKey: .sslUrl)
        deployUrl = try container.decodeIfPresent(String.self, forKey: .deployUrl)
        deploySslUrl = try container.decodeIfPresent(String.self, forKey: .deploySslUrl)
        adminUrl = try container.decodeIfPresent(URL.self, forKey: .adminUrl)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
            ?? container.decodeIfPresent(String.self, forKey: .error)
    }
}

private struct ProviderDiscoveryIssue: Error {
    var issue: ProviderIssue

    init(_ issue: ProviderIssue) {
        self.issue = issue
    }
}
