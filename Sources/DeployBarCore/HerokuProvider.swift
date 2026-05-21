import Foundation

public struct HerokuProvider: DeploymentProvider {
    public let id: ProviderID = .heroku
    public let displayName = "Heroku"

    private let client: any HTTPClient
    private let baseURL: URL
    private let limit: Int
    private let appLimit: Int

    public init(
        client: any HTTPClient = APIClient(),
        baseURL: URL = URL(string: "https://api.heroku.com")!,
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
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Heroku API token is not configured.")]
            )
        }

        do {
            let targets = try await targets(for: context.account, token: token)
            var snapshots: [DeploymentSnapshot] = []
            var issues: [ProviderIssue] = []

            for target in targets {
                guard let app = target.projectID ?? target.projectName else {
                    issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Heroku target needs an app name or app ID."))
                    continue
                }

                let response = try await client.send(makeReleasesRequest(app: app, token: token))
                if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: context.account.id, statusCode: response.statusCode) {
                    issues.append(issue)
                    continue
                }

                snapshots.append(contentsOf: try HerokuParser.snapshots(from: response.data, account: context.account, target: target, now: context.now()))
            }

            return ProviderRefreshResult(snapshots: ProviderUtilities.deduplicated(snapshots), issues: issues)
        } catch let error as HerokuIssue {
            return ProviderRefreshResult(snapshots: [], issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderRefreshResult(snapshots: [], issues: [ProviderUtilities.issue(for: error, provider: id, accountID: context.account.id)])
        } catch {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "Heroku API response could not be parsed.")]
            )
        }
    }

    private func targets(for account: ProviderAccount, token: String) async throws -> [MonitoredTarget] {
        if !account.monitoredTargets.isEmpty {
            return account.monitoredTargets
        }

        let response = try await client.send(makeAppsRequest(token: token))
        if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: account.id, statusCode: response.statusCode) {
            throw HerokuIssue(issue)
        }

        return try HerokuParser.apps(from: response.data).prefix(appLimit).map { app in
            MonitoredTarget(projectID: app.id, projectName: app.name)
        }
    }

    private func makeAppsRequest(token: String) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("apps")
        var request = authenticatedRequest(url: url, token: token)
        request.setValue("name ..; order=asc,max=\(appLimit)", forHTTPHeaderField: "Range")
        return request
    }

    private func makeReleasesRequest(app: String, token: String) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("apps").appendingPathComponent(app).appendingPathComponent("releases")
        var request = authenticatedRequest(url: url, token: token)
        request.setValue("version ..; order=desc,max=\(limit)", forHTTPHeaderField: "Range")
        return request
    }

    private func authenticatedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.heroku+json; version=3", forHTTPHeaderField: "Accept")
        request.setValue("DeployBar/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }
}

public enum HerokuParser {
    public static func snapshots(from data: Data, account: ProviderAccount, target: MonitoredTarget, now: Date = Date()) throws -> [DeploymentSnapshot] {
        let releases = try JSONDecoder.deployBar.decode([HerokuRelease].self, from: data)
        return releases.map { release in
            let status = DeploymentStatusMapper.herokuStatus(release.status)
            return DeploymentSnapshot(
                id: "heroku:\(account.id):\(release.id)",
                provider: .heroku,
                projectName: release.app?.name ?? target.projectName ?? target.projectID ?? "Heroku App",
                serviceName: "release v\(release.version)",
                environmentName: release.current == true ? "current" : nil,
                branch: target.branch,
                commitSha: nil,
                commitMessage: release.description,
                actor: release.user?.email,
                status: status,
                createdAt: release.createdAt,
                startedAt: release.createdAt,
                finishedAt: terminal(status) ? release.updatedAt : nil,
                duration: ProviderUtilities.duration(startedAt: release.createdAt, finishedAt: terminal(status) ? release.updatedAt : nil),
                dashboardURL: dashboardURL(appName: release.app?.name ?? target.projectName, version: release.version),
                deploymentURL: nil,
                errorMessage: status == .failed ? release.description : nil,
                lastUpdatedAt: now
            )
        }
    }

    static func apps(from data: Data) throws -> [HerokuApp] {
        try JSONDecoder.deployBar.decode([HerokuApp].self, from: data)
    }

    private static func terminal(_ status: DeploymentStatus) -> Bool {
        switch status {
        case .success, .failed, .error, .removed, .canceled:
            return true
        default:
            return false
        }
    }

    private static func dashboardURL(appName: String?, version: Int) -> URL? {
        guard let appName else { return nil }
        return URL(string: "https://dashboard.heroku.com/apps/\(appName)/activity/releases/\(version)")
    }
}

struct HerokuApp: Decodable {
    var id: String
    var name: String
}

private struct HerokuRelease: Decodable {
    var id: String
    var version: Int
    var status: String
    var current: Bool?
    var description: String?
    var createdAt: Date?
    var updatedAt: Date?
    var app: HerokuApp?
    var user: HerokuUser?

    enum CodingKeys: String, CodingKey {
        case id
        case version
        case status
        case current
        case description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case app
        case user
    }
}

private struct HerokuUser: Decodable {
    var email: String?
}

private struct HerokuIssue: Error {
    var issue: ProviderIssue

    init(_ issue: ProviderIssue) {
        self.issue = issue
    }
}

