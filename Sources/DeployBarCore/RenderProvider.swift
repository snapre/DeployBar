import Foundation

public struct RenderProvider: DeploymentProvider {
    public let id: ProviderID = .render
    public let displayName = "Render"

    private let client: any HTTPClient
    private let baseURL: URL
    private let limit: Int
    private let serviceLimit: Int

    public init(
        client: any HTTPClient = APIClient(),
        baseURL: URL = URL(string: "https://api.render.com")!,
        limit: Int = 10,
        serviceLimit: Int = 20
    ) {
        self.client = client
        self.baseURL = baseURL
        self.limit = limit
        self.serviceLimit = serviceLimit
    }

    public func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult {
        guard let token = context.token, !token.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Render API token is not configured.")]
            )
        }

        do {
            let targets = try await targets(for: context.account, token: token)
            var snapshots: [DeploymentSnapshot] = []
            var issues: [ProviderIssue] = []

            for target in targets {
                guard let serviceID = target.serviceID ?? target.serviceName ?? target.projectID else {
                    issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Render target needs a service ID."))
                    continue
                }

                let response = try await client.send(makeDeploysRequest(serviceID: serviceID, token: token))
                if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: context.account.id, statusCode: response.statusCode) {
                    issues.append(issue)
                    continue
                }

                snapshots.append(contentsOf: try RenderParser.snapshots(from: response.data, account: context.account, target: target, now: context.now()))
            }

            return ProviderRefreshResult(snapshots: ProviderUtilities.deduplicated(snapshots), issues: issues)
        } catch let error as RenderProviderIssue {
            return ProviderRefreshResult(snapshots: [], issues: [error.issue])
        } catch let error as APIClientError {
            return ProviderRefreshResult(snapshots: [], issues: [ProviderUtilities.issue(for: error, provider: id, accountID: context.account.id)])
        } catch {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "Render API response could not be parsed.")]
            )
        }
    }

    private func targets(for account: ProviderAccount, token: String) async throws -> [MonitoredTarget] {
        if !account.monitoredTargets.isEmpty {
            return account.monitoredTargets
        }

        let response = try await client.send(makeServicesRequest(token: token))
        if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: account.id, statusCode: response.statusCode) {
            throw RenderProviderIssue(issue)
        }

        return try RenderParser.services(from: response.data).prefix(serviceLimit).map { service in
            MonitoredTarget(serviceID: service.id, serviceName: service.name, environmentName: service.type)
        }
    }

    private func makeServicesRequest(token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1").appendingPathComponent("services"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: "\(serviceLimit)")]
        guard let url = components?.url else { throw APIClientError.invalidResponse }
        return authenticatedRequest(url: url, token: token)
    }

    private func makeDeploysRequest(serviceID: String, token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1").appendingPathComponent("services").appendingPathComponent(serviceID).appendingPathComponent("deploys"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
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

public enum RenderParser {
    public static func snapshots(from data: Data, account: ProviderAccount, target: MonitoredTarget, now: Date = Date()) throws -> [DeploymentSnapshot] {
        let items = try JSONDecoder.deployBar.decode([RenderDeployEnvelope].self, from: data)
        return items.compactMap(\.deploy).map { deploy in
            let status = DeploymentStatusMapper.renderStatus(deploy.status)
            let serviceID = target.serviceID ?? target.projectID
            let finishedAt = finishedAt(status: status, deploy: deploy)
            return DeploymentSnapshot(
                id: "render:\(account.id):\(deploy.id)",
                provider: .render,
                projectName: target.projectName ?? target.serviceName ?? serviceID ?? "Render Service",
                serviceName: target.serviceName ?? serviceID,
                environmentName: target.environmentName,
                branch: target.branch,
                commitSha: deploy.commit?.id,
                commitMessage: deploy.commit?.message,
                actor: deploy.commit?.createdBy,
                status: status,
                createdAt: deploy.createdAt,
                startedAt: deploy.startedAt ?? deploy.createdAt,
                finishedAt: finishedAt,
                duration: ProviderUtilities.duration(startedAt: deploy.startedAt ?? deploy.createdAt, finishedAt: finishedAt),
                dashboardURL: dashboardURL(serviceID: serviceID, deployID: deploy.id),
                deploymentURL: nil,
                errorMessage: deploy.failureReason,
                lastUpdatedAt: now
            )
        }
    }

    static func services(from data: Data) throws -> [RenderService] {
        let items = try JSONDecoder.deployBar.decode([RenderServiceEnvelope].self, from: data)
        return items.compactMap(\.service)
    }

    private static func finishedAt(status: DeploymentStatus, deploy: RenderDeploy) -> Date? {
        switch status {
        case .success, .failed, .error, .canceled:
            return deploy.finishedAt ?? deploy.updatedAt
        default:
            return nil
        }
    }

    private static func dashboardURL(serviceID: String?, deployID: String) -> URL? {
        guard let serviceID else { return nil }
        return URL(string: "https://dashboard.render.com/services/\(serviceID)/deploys/\(deployID)")
    }
}

struct RenderService: Decodable {
    var id: String
    var name: String?
    var type: String?
}

private struct RenderServiceEnvelope: Decodable {
    var service: RenderService?

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self), let service = try container.decodeIfPresent(RenderService.self, forKey: .service) {
            self.service = service
        } else {
            self.service = try RenderService(from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case service
    }
}

private struct RenderDeployEnvelope: Decodable {
    var deploy: RenderDeploy?

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self), let deploy = try container.decodeIfPresent(RenderDeploy.self, forKey: .deploy) {
            self.deploy = deploy
        } else {
            self.deploy = try RenderDeploy(from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case deploy
    }
}

private struct RenderDeploy: Decodable {
    var id: String
    var status: String
    var createdAt: Date?
    var updatedAt: Date?
    var startedAt: Date?
    var finishedAt: Date?
    var failureReason: String?
    var commit: RenderCommit?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case createdAt
        case updatedAt
        case startedAt
        case finishedAt
        case failureReason
        case commit
    }
}

private struct RenderCommit: Decodable {
    var id: String?
    var message: String?
    var createdBy: String?
}

private struct RenderProviderIssue: Error {
    var issue: ProviderIssue

    init(_ issue: ProviderIssue) {
        self.issue = issue
    }
}

