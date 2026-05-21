import Foundation

public struct VercelDiscoveryResult: Equatable, Sendable {
    public var projects: [VercelProjectResource]
    public var issues: [ProviderIssue]

    public init(projects: [VercelProjectResource] = [], issues: [ProviderIssue] = []) {
        self.projects = projects
        self.issues = issues
    }
}

public struct VercelProjectResource: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var environments: [String]
    public var branches: [String]

    public init(id: String, name: String, environments: [String] = [], branches: [String] = []) {
        self.id = id
        self.name = name
        self.environments = environments
        self.branches = branches
    }
}

enum VercelDiscoveryParser {
    static func projects(from data: Data) throws -> [VercelProjectResource] {
        let decoder = JSONDecoder()
        if let object = try? decoder.decode(VercelProjectsObjectResponse.self, from: data) {
            return object.projects.map { VercelProjectResource(id: $0.id, name: $0.name) }
        }
        let array = try decoder.decode([VercelProjectNode].self, from: data)
        return array.map { VercelProjectResource(id: $0.id, name: $0.name) }
    }

    static func deploymentHints(from data: Data) throws -> [String: VercelDeploymentHints] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let response = try decoder.decode(VercelDiscoveryDeploymentsResponse.self, from: data)
        var hintsByProject: [String: VercelDeploymentHints] = [:]

        for deployment in response.deployments {
            let keys = [deployment.projectId, deployment.name].compactMap { $0 }
            let branch = deployment.meta?["githubCommitRef"]
                ?? deployment.meta?["gitlabCommitRef"]
                ?? deployment.meta?["bitbucketCommitRef"]
            let environment = deployment.target ?? "preview"

            for key in keys {
                var hints = hintsByProject[key, default: VercelDeploymentHints()]
                if let branch, !branch.isEmpty {
                    hints.branches.insert(branch)
                }
                if !environment.isEmpty {
                    hints.environments.insert(environment)
                }
                hintsByProject[key] = hints
            }
        }

        return hintsByProject
    }
}

struct VercelDeploymentHints: Equatable {
    var environments: Set<String> = []
    var branches: Set<String> = []
}

private struct VercelProjectsObjectResponse: Decodable {
    var projects: [VercelProjectNode]
}

private struct VercelProjectNode: Decodable {
    var id: String
    var name: String
}

private struct VercelDiscoveryDeploymentsResponse: Decodable {
    var deployments: [VercelDiscoveryDeployment]
}

private struct VercelDiscoveryDeployment: Decodable {
    var projectId: String?
    var name: String
    var target: String?
    var meta: [String: String]?

    enum CodingKeys: String, CodingKey {
        case projectId
        case name
        case target
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        name = try container.decode(String.self, forKey: .name)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        meta = try container.decodeIfPresent(VercelDiscoveryLossyStringDictionary.self, forKey: .meta)?.values
    }
}

private struct VercelDiscoveryLossyStringDictionary: Decodable {
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
