import Foundation

public enum VercelParser {
    public static func snapshots(from data: Data, account: ProviderAccount, now: Date = Date()) throws -> [DeploymentSnapshot] {
        let response = try JSONDecoder.deployBarMilliseconds.decode(VercelDeploymentsResponse.self, from: data)
        return response.deployments.map { deployment in
            let status = DeploymentStatusMapper.vercelStatus(deployment.readyState ?? deployment.state)
            let url = deployment.url.flatMap(Self.deploymentURL(from:))
            let actor = deployment.creator?.username ?? deployment.creator?.githubLogin ?? deployment.creator?.gitlabLogin ?? deployment.creator?.email
            let branch = deployment.meta?["githubCommitRef"] ?? deployment.meta?["gitlabCommitRef"] ?? deployment.meta?["bitbucketCommitRef"]
            let sha = deployment.meta?["githubCommitSha"] ?? deployment.meta?["gitlabCommitSha"] ?? deployment.meta?["bitbucketCommitSha"]
            let message = deployment.meta?["githubCommitMessage"] ?? deployment.meta?["gitlabCommitMessage"] ?? deployment.meta?["bitbucketCommitMessage"]
            let finishedAt = deployment.ready
            let startedAt = deployment.buildingAt

            return DeploymentSnapshot(
                id: "vercel:\(account.id):\(deployment.uid)",
                provider: .vercel,
                projectName: deployment.name,
                environmentName: deployment.target,
                branch: branch,
                commitSha: sha,
                commitMessage: message,
                actor: actor,
                status: status,
                createdAt: deployment.createdAt ?? deployment.created,
                startedAt: startedAt,
                finishedAt: finishedAt,
                duration: duration(startedAt: startedAt, finishedAt: finishedAt),
                dashboardURL: deployment.inspectorUrl,
                deploymentURL: url,
                errorMessage: deployment.errorMessage,
                lastUpdatedAt: now
            )
        }
    }

    private static func duration(startedAt: Date?, finishedAt: Date?) -> TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    private static func deploymentURL(from rawValue: String) -> URL? {
        if rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") {
            return URL(string: rawValue)
        }
        return URL(string: "https://\(rawValue)")
    }
}

private struct VercelDeploymentsResponse: Decodable {
    var deployments: [VercelDeployment]
}

private struct VercelDeployment: Decodable {
    var uid: String
    var name: String
    var url: String?
    var state: String
    var readyState: String?
    var target: String?
    var created: Date?
    var createdAt: Date?
    var buildingAt: Date?
    var ready: Date?
    var creator: VercelCreator?
    var inspectorUrl: URL?
    var errorMessage: String?
    var meta: [String: String]?

    enum CodingKeys: String, CodingKey {
        case uid
        case name
        case url
        case state
        case readyState
        case target
        case created
        case createdAt
        case buildingAt
        case ready
        case creator
        case inspectorUrl
        case errorMessage
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try container.decode(String.self, forKey: .uid)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        state = try container.decode(String.self, forKey: .state)
        readyState = try container.decodeIfPresent(String.self, forKey: .readyState)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        created = try container.decodeIfPresent(Date.self, forKey: .created)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        buildingAt = try container.decodeIfPresent(Date.self, forKey: .buildingAt)
        ready = try container.decodeIfPresent(Date.self, forKey: .ready)
        creator = try container.decodeIfPresent(VercelCreator.self, forKey: .creator)
        inspectorUrl = try container.decodeIfPresent(URL.self, forKey: .inspectorUrl)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        meta = try container.decodeIfPresent(LossyStringDictionary.self, forKey: .meta)?.values
    }
}

private struct VercelCreator: Decodable {
    var email: String?
    var username: String?
    var githubLogin: String?
    var gitlabLogin: String?
}

private struct LossyStringDictionary: Decodable {
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

private extension JSONDecoder {
    static var deployBarMilliseconds: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
