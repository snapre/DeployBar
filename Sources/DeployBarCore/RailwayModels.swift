import Foundation

public enum RailwayParser {
    public static func snapshots(
        from data: Data,
        account: ProviderAccount,
        target fallbackTarget: MonitoredTarget? = nil,
        now: Date = Date()
    ) throws -> [DeploymentSnapshot] {
        let response = try JSONDecoder.deployBar.decode(RailwayDeploymentsResponse.self, from: data)
        if let errors = response.errors, !errors.isEmpty {
            throw RailwayParsingError.graphQLErrors(errors.map(\.message).joined(separator: "; "))
        }

        return response.data?.deployments.edges.map { edge in
            let deployment = edge.node
            let status = DeploymentStatusMapper.railwayStatus(deployment.status)
            let target = fallbackTarget ?? matchingTarget(for: deployment, account: account)
            let projectID = deployment.projectId ?? target?.projectID
            let serviceID = deployment.serviceId ?? target?.serviceID
            let environmentID = deployment.environmentId ?? target?.environmentID
            let projectName = target?.projectName ?? deployment.project?.name ?? projectID ?? "Railway Project"
            let serviceName = target?.serviceName ?? deployment.service?.name ?? serviceID
            let environmentName = target?.environmentName ?? deployment.environment?.name ?? environmentID
            let dashboardURL = dashboardURL(projectID: projectID, serviceID: serviceID, environmentID: environmentID)
            let deploymentURL = deployment.url.flatMap(Self.normalizedURL(from:))
                ?? deployment.staticUrl.flatMap(Self.normalizedURL(from:))
            let finishedAt = finishedAt(status: status, deployment: deployment)
            let branch = metaValue(deployment.meta, keys: ["branch", "gitBranch", "githubCommitRef", "gitlabCommitRef", "bitbucketCommitRef"])
            let commitSha = metaValue(deployment.meta, keys: ["commitSha", "gitCommitSha", "githubCommitSha", "gitlabCommitSha", "bitbucketCommitSha"])
            let commitMessage = metaValue(deployment.meta, keys: ["commitMessage", "gitCommitMessage", "githubCommitMessage", "gitlabCommitMessage", "bitbucketCommitMessage"])
            let actor = metaValue(deployment.meta, keys: ["commitAuthor", "gitCommitAuthor", "githubCommitAuthor", "gitlabCommitAuthor", "bitbucketCommitAuthor"])

            return DeploymentSnapshot(
                id: "railway:\(account.id):\(deployment.id)",
                provider: .railway,
                projectName: projectName,
                serviceName: serviceName,
                environmentName: environmentName,
                branch: branch,
                commitSha: commitSha,
                commitMessage: commitMessage,
                actor: actor,
                status: status,
                createdAt: deployment.createdAt,
                startedAt: deployment.createdAt,
                finishedAt: finishedAt,
                duration: duration(startedAt: deployment.createdAt, finishedAt: finishedAt),
                dashboardURL: dashboardURL,
                deploymentURL: deploymentURL,
                errorMessage: deployment.diagnosis,
                lastUpdatedAt: now
            )
        } ?? []
    }

    static func graphQLErrorMessage(from data: Data) -> String? {
        guard let response = try? JSONDecoder.deployBar.decode(RailwayDeploymentsResponse.self, from: data) else {
            return nil
        }
        guard let errors = response.errors, !errors.isEmpty else {
            return nil
        }
        return errors.map(\.message).joined(separator: "; ")
    }

    private static func matchingTarget(for deployment: RailwayDeployment, account: ProviderAccount) -> MonitoredTarget? {
        account.monitoredTargets.first { target in
            matches(targetID: target.projectID, deploymentID: deployment.projectId)
                && matches(targetID: target.serviceID, deploymentID: deployment.serviceId)
                && matches(targetID: target.environmentID, deploymentID: deployment.environmentId)
        }
    }

    private static func matches(targetID: String?, deploymentID: String?) -> Bool {
        guard let targetID else { return true }
        guard let deploymentID else { return false }
        return targetID == deploymentID
    }

    private static func dashboardURL(projectID: String?, serviceID: String?, environmentID: String?) -> URL? {
        guard let projectID else { return nil }
        var components = URLComponents(string: "https://railway.com/project/\(projectID)")
        if let serviceID {
            components = URLComponents(string: "https://railway.com/project/\(projectID)/service/\(serviceID)")
        }
        if let environmentID {
            components?.queryItems = [URLQueryItem(name: "environmentId", value: environmentID)]
        }
        return components?.url
    }

    private static func normalizedURL(from rawValue: String) -> URL? {
        if rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") {
            return URL(string: rawValue)
        }
        return URL(string: "https://\(rawValue)")
    }

    private static func metaValue(_ meta: [String: String]?, keys: [String]) -> String? {
        guard let meta else { return nil }
        for key in keys {
            let value = meta[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func finishedAt(status: DeploymentStatus, deployment: RailwayDeployment) -> Date? {
        switch status {
        case .success, .failed, .crashed, .removed, .skipped, .sleeping:
            return deployment.statusUpdatedAt ?? deployment.updatedAt
        default:
            return nil
        }
    }

    private static func duration(startedAt: Date?, finishedAt: Date?) -> TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }
}

public enum RailwayParsingError: Error, Equatable {
    case graphQLErrors(String)
}

private struct RailwayDeploymentsResponse: Decodable {
    var data: RailwayData?
    var errors: [RailwayGraphQLError]?
}

private struct RailwayGraphQLError: Decodable {
    var message: String
}

private struct RailwayData: Decodable {
    var deployments: RailwayDeploymentsConnection
}

private struct RailwayDeploymentsConnection: Decodable {
    var edges: [RailwayDeploymentEdge]
}

private struct RailwayDeploymentEdge: Decodable {
    var node: RailwayDeployment
}

private struct RailwayDeployment: Decodable {
    var id: String
    var status: String
    var createdAt: Date?
    var updatedAt: Date?
    var statusUpdatedAt: Date?
    var projectId: String?
    var serviceId: String?
    var environmentId: String?
    var url: String?
    var staticUrl: String?
    var diagnosis: String?
    var meta: [String: String]?
    var project: RailwayNamedResource?
    var service: RailwayNamedResource?
    var environment: RailwayNamedResource?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case createdAt
        case updatedAt
        case statusUpdatedAt
        case projectId
        case serviceId
        case environmentId
        case url
        case staticUrl
        case diagnosis
        case meta
        case project
        case service
        case environment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        statusUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .statusUpdatedAt)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        serviceId = try container.decodeIfPresent(String.self, forKey: .serviceId)
        environmentId = try container.decodeIfPresent(String.self, forKey: .environmentId)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        staticUrl = try container.decodeIfPresent(String.self, forKey: .staticUrl)
        diagnosis = try container.decodeIfPresent(String.self, forKey: .diagnosis)
        meta = try container.decodeIfPresent(RailwayLossyStringDictionary.self, forKey: .meta)?.values
        project = try container.decodeIfPresent(RailwayNamedResource.self, forKey: .project)
        service = try container.decodeIfPresent(RailwayNamedResource.self, forKey: .service)
        environment = try container.decodeIfPresent(RailwayNamedResource.self, forKey: .environment)
    }
}

private struct RailwayNamedResource: Decodable {
    var name: String
}

private struct RailwayLossyStringDictionary: Decodable {
    var values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var values: [String: String] = [:]

        for key in container.allKeys {
            if let value = try? container.decode(String.self, forKey: key) {
                values[key.stringValue] = value
            } else if let value = try? container.decode(Int.self, forKey: key) {
                values[key.stringValue] = String(value)
            } else if let value = try? container.decode(Bool.self, forKey: key) {
                values[key.stringValue] = String(value)
            }
        }

        self.values = values
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
