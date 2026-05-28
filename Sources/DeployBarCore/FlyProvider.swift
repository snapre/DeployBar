import Foundation

public struct FlyProvider: DeploymentProvider {
    public let id: ProviderID = .flyio
    public let displayName = "Fly.io"

    private let client: any HTTPClient
    private let endpointURL: URL
    private let limit: Int
    private let appLimit: Int

    public init(
        client: any HTTPClient = APIClient(),
        endpointURL: URL = URL(string: "https://api.fly.io/graphql")!,
        limit: Int = 10,
        appLimit: Int = 20
    ) {
        self.client = client
        self.endpointURL = endpointURL
        self.limit = limit
        self.appLimit = appLimit
    }

    public func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult {
        guard let token = context.token, !token.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Fly.io API token is not configured.")]
            )
        }

        do {
            let targets = try await targets(for: context.account, token: token)
            var snapshots: [DeploymentSnapshot] = []
            var issues: [ProviderIssue] = []

            for target in targets {
                guard let app = target.projectID ?? target.projectName else {
                    issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Fly.io target needs an app name."))
                    continue
                }

                let response = try await client.send(makeReleasesRequest(app: app, token: token))

                if let message = FlyParser.graphQLErrorMessage(from: response.data) {
                    issues.append(graphQLIssue(message: message, accountID: context.account.id))
                    continue
                }

                if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: context.account.id, statusCode: response.statusCode) {
                    issues.append(issue)
                    continue
                }

                snapshots.append(contentsOf: try FlyParser.snapshots(from: response.data, account: context.account, target: target, now: context.now()))
            }

            return ProviderRefreshResult(snapshots: ProviderUtilities.deduplicated(snapshots), issues: issues)
        } catch let error as FlyProviderIssue {
            return ProviderRefreshResult(snapshots: [], issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderRefreshResult(snapshots: [], issues: [ProviderUtilities.issue(for: error, provider: id, accountID: context.account.id)])
        } catch {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "Fly.io API response could not be parsed.")]
            )
        }
    }

    public func discoverTargets(token: String, account: ProviderAccount) async -> ProviderTargetDiscoveryResult {
        guard !token.isEmpty else {
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .notConfigured, message: "Fly.io API token is not configured.")]
            )
        }

        do {
            return ProviderTargetDiscoveryResult(targets: try await discoverApps(account: account, token: token))
        } catch let error as FlyProviderIssue {
            return ProviderTargetDiscoveryResult(issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderTargetDiscoveryResult(issues: [ProviderUtilities.issue(for: error, provider: id, accountID: account.id)])
        } catch {
            return ProviderTargetDiscoveryResult(
                issues: [ProviderIssue(provider: id, accountID: account.id, kind: .apiChanged, message: "Fly.io discovery response could not be parsed.")]
            )
        }
    }

    private func targets(for account: ProviderAccount, token: String) async throws -> [MonitoredTarget] {
        if !account.monitoredTargets.isEmpty {
            return account.monitoredTargets
        }

        return try await discoverApps(account: account, token: token)
    }

    private func discoverApps(account: ProviderAccount, token: String) async throws -> [MonitoredTarget] {
        let response = try await client.send(makeAppsRequest(token: token))

        if let message = FlyParser.graphQLErrorMessage(from: response.data) {
            throw FlyProviderIssue(graphQLIssue(message: message, accountID: account.id))
        }
        if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: account.id, statusCode: response.statusCode) {
            throw FlyProviderIssue(issue)
        }

        return try FlyParser.apps(from: response.data).prefix(appLimit).map { app in
            MonitoredTarget(projectID: app.name, projectName: app.name)
        }
    }

    private func makeReleasesRequest(app: String, token: String) throws -> URLRequest {
        let body = FlyGraphQLRequest(
            query: Self.releasesQuery,
            variables: FlyReleasesVariables(appName: app, first: limit)
        )
        return try makeGraphQLRequest(token: token, body: body)
    }

    private func makeAppsRequest(token: String) throws -> URLRequest {
        let body = FlyGraphQLRequest(
            query: Self.appsQuery,
            variables: FlyAppsVariables(first: appLimit)
        )
        return try makeGraphQLRequest(token: token, body: body)
    }

    private func makeGraphQLRequest<Variables: Encodable>(token: String, body: FlyGraphQLRequest<Variables>) throws -> URLRequest {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue(Self.authorizationHeader(for: token), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DeployBar/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder.deployBar.encode(body)
        return request
    }

    private static func authorizationHeader(for token: String) -> String {
        let stripped = strippedAuthorizationScheme(from: token)
        if containsFlyV1Token(stripped) {
            return "FlyV1 \(stripped)"
        }
        return "Bearer \(stripped)"
    }

    private static func strippedAuthorizationScheme(from token: String) -> String {
        var value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        while true {
            let lowercased = value.lowercased()
            if lowercased.hasPrefix("bearer ") {
                value = String(value.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lowercased.hasPrefix("flyv1 ") {
                value = String(value.dropFirst("flyv1 ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                return value
            }
        }
    }

    private static func containsFlyV1Token(_ token: String) -> Bool {
        token.split(separator: ",").contains { part in
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("fm1r_") || trimmed.hasPrefix("fm1a_") || trimmed.hasPrefix("fm2_")
        }
    }

    private func graphQLIssue(message: String, accountID: String) -> ProviderIssue {
        let lowercased = message.lowercased()
        if lowercased.contains("authenticat") || lowercased.contains("unauthorized") || lowercased.contains("access denied") || lowercased.contains("must be logged in") {
            return ProviderIssue(provider: id, accountID: accountID, kind: .authentication, message: "Fly.io authentication failed.")
        }
        if lowercased.contains("cannot query field") || lowercased.contains("unknown argument") || lowercased.contains("undefined field") {
            return ProviderIssue(provider: id, accountID: accountID, kind: .apiChanged, message: "Fly.io GraphQL schema changed: \(shortMessage(message))")
        }
        return ProviderIssue(provider: id, accountID: accountID, kind: .apiChanged, message: "Fly.io GraphQL error: \(shortMessage(message))")
    }

    private func shortMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return trimmed }
        return "\(trimmed.prefix(177))..."
    }

    private static let releasesQuery = """
    query Releases($appName: String!, $first: Int!) {
      app(name: $appName) {
        name
        releases: releasesUnprocessed(first: $first) {
          nodes {
            id
            version
            description
            reason
            status
            stable
            createdAt
            user {
              email
            }
          }
        }
      }
    }
    """

    private static let appsQuery = """
    query DiscoverFlyApps($first: Int!) {
      apps(first: $first) {
        nodes {
          id
          name
        }
      }
    }
    """
}

public enum FlyParser {
    public static func snapshots(from data: Data, account: ProviderAccount, target: MonitoredTarget, now: Date = Date()) throws -> [DeploymentSnapshot] {
        let response = try JSONDecoder.deployBar.decode(FlyReleasesResponse.self, from: data)
        if let errors = response.errors, !errors.isEmpty {
            throw FlyParsingError.graphQLErrors(errors.map(\.message).joined(separator: "; "))
        }

        let appName = response.data?.app?.name ?? target.projectName ?? target.projectID
        let nodes = response.data?.app?.releases?.nodes ?? []

        return nodes.map { release in
            let status = DeploymentStatusMapper.flyStatus(release.status ?? "")
            let finishedAt = terminal(status) ? release.createdAt : nil
            return DeploymentSnapshot(
                id: "flyio:\(account.id):\(release.id)",
                provider: .flyio,
                projectName: appName ?? "Fly.io App",
                serviceName: release.version.map { "release v\($0)" },
                environmentName: release.stable == true ? "stable" : nil,
                branch: target.branch,
                commitSha: nil,
                commitMessage: release.description ?? release.reason,
                actor: release.user?.email,
                status: status,
                createdAt: release.createdAt,
                startedAt: release.createdAt,
                finishedAt: finishedAt,
                duration: nil,
                dashboardURL: dashboardURL(appName: appName),
                deploymentURL: nil,
                errorMessage: status == .failed ? release.description : nil,
                lastUpdatedAt: now
            )
        }
    }

    public static func apps(from data: Data) throws -> [FlyApp] {
        let response = try JSONDecoder.deployBar.decode(FlyAppsResponse.self, from: data)
        if let errors = response.errors, !errors.isEmpty {
            throw FlyParsingError.graphQLErrors(errors.map(\.message).joined(separator: "; "))
        }
        return response.data?.apps?.nodes ?? []
    }

    static func graphQLErrorMessage(from data: Data) -> String? {
        guard let response = try? JSONDecoder.deployBar.decode(FlyErrorEnvelope.self, from: data),
              let errors = response.errors, !errors.isEmpty
        else {
            return nil
        }
        return errors.map(\.message).joined(separator: "; ")
    }

    private static func terminal(_ status: DeploymentStatus) -> Bool {
        switch status {
        case .success, .failed, .error, .removed, .canceled:
            return true
        default:
            return false
        }
    }

    private static func dashboardURL(appName: String?) -> URL? {
        guard let appName, !appName.isEmpty else { return nil }
        return URL(string: "https://fly.io/apps/\(appName)")
    }
}

public struct FlyApp: Decodable {
    public var id: String?
    public var name: String
}

private struct FlyGraphQLRequest<Variables: Encodable>: Encodable {
    var query: String
    var variables: Variables
}

private struct FlyReleasesVariables: Encodable {
    var appName: String
    var first: Int
}

private struct FlyAppsVariables: Encodable {
    var first: Int
}

private struct FlyErrorEnvelope: Decodable {
    var errors: [FlyGraphQLError]?
}

private struct FlyGraphQLError: Decodable {
    var message: String
}

private struct FlyReleasesResponse: Decodable {
    var data: FlyReleasesData?
    var errors: [FlyGraphQLError]?
}

private struct FlyReleasesData: Decodable {
    var app: FlyAppReleases?
}

private struct FlyAppReleases: Decodable {
    var name: String?
    var releases: FlyReleaseConnection?
}

private struct FlyReleaseConnection: Decodable {
    var nodes: [FlyRelease]
}

private struct FlyRelease: Decodable {
    var id: String
    var version: Int?
    var description: String?
    var reason: String?
    var status: String?
    var stable: Bool?
    var createdAt: Date?
    var user: FlyReleaseUser?
}

private struct FlyReleaseUser: Decodable {
    var email: String?
}

private struct FlyAppsResponse: Decodable {
    var data: FlyAppsData?
    var errors: [FlyGraphQLError]?
}

private struct FlyAppsData: Decodable {
    var apps: FlyAppConnection?
}

private struct FlyAppConnection: Decodable {
    var nodes: [FlyApp]
}

enum FlyParsingError: Error {
    case graphQLErrors(String)
}

private struct FlyProviderIssue: Error {
    var issue: ProviderIssue

    init(_ issue: ProviderIssue) {
        self.issue = issue
    }
}
