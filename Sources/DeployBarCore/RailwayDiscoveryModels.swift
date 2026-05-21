import Foundation

public struct RailwayDiscoveryResult: Equatable, Sendable {
    public var projects: [RailwayProjectResource]
    public var issues: [ProviderIssue]

    public init(projects: [RailwayProjectResource] = [], issues: [ProviderIssue] = []) {
        self.projects = projects
        self.issues = issues
    }
}

public struct RailwayProjectResource: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var services: [RailwayServiceResource]
    public var environments: [RailwayEnvironmentResource]

    public init(
        id: String,
        name: String,
        services: [RailwayServiceResource] = [],
        environments: [RailwayEnvironmentResource] = []
    ) {
        self.id = id
        self.name = name
        self.services = services
        self.environments = environments
    }
}

public struct RailwayServiceResource: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct RailwayEnvironmentResource: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

enum RailwayDiscoveryParser {
    static func projects(from data: Data) throws -> [RailwayProjectResource] {
        let response = try JSONDecoder.deployBar.decode(RailwayProjectsResponse.self, from: data)
        if let errors = response.errors, !errors.isEmpty {
            throw RailwayParsingError.graphQLErrors(errors.map(\.message).joined(separator: "; "))
        }

        if let projects = response.data?.projects?.edges.map({ Self.project(from: $0.node) }) {
            return projects
        }

        if let project = response.data?.project {
            return [Self.project(from: project)]
        }

        if let token = response.data?.projectToken {
            return [
                RailwayProjectResource(
                    id: token.projectId,
                    name: "Project \(token.projectId.shortID)",
                    environments: token.environmentId.map {
                        [RailwayEnvironmentResource(id: $0, name: "Environment \($0.shortID)")]
                    } ?? []
                )
            ]
        }

        return []
    }

    private static func project(from node: RailwayProjectNode) -> RailwayProjectResource {
        RailwayProjectResource(
            id: node.id,
            name: node.name,
            services: node.services?.edges.map { RailwayServiceResource(id: $0.node.id, name: $0.node.name) } ?? [],
            environments: node.environments?.edges.map { RailwayEnvironmentResource(id: $0.node.id, name: $0.node.name) } ?? []
        )
    }
}

private struct RailwayProjectsResponse: Decodable {
    var data: RailwayProjectsData?
    var errors: [RailwayDiscoveryGraphQLError]?
}

private struct RailwayProjectsData: Decodable {
    var projects: RailwayProjectsConnection?
    var project: RailwayProjectNode?
    var projectToken: RailwayProjectToken?
}

private struct RailwayProjectsConnection: Decodable {
    var edges: [RailwayProjectEdge]
}

private struct RailwayProjectEdge: Decodable {
    var node: RailwayProjectNode
}

private struct RailwayProjectNode: Decodable {
    var id: String
    var name: String
    var services: RailwayServicesConnection?
    var environments: RailwayEnvironmentsConnection?
}

private struct RailwayServicesConnection: Decodable {
    var edges: [RailwayServiceEdge]
}

private struct RailwayServiceEdge: Decodable {
    var node: RailwayNamedNode
}

private struct RailwayEnvironmentsConnection: Decodable {
    var edges: [RailwayEnvironmentEdge]
}

private struct RailwayEnvironmentEdge: Decodable {
    var node: RailwayNamedNode
}

private struct RailwayNamedNode: Decodable {
    var id: String
    var name: String
}

private struct RailwayProjectToken: Decodable {
    var projectId: String
    var environmentId: String?
}

private struct RailwayDiscoveryGraphQLError: Decodable {
    var message: String
}

private extension String {
    var shortID: String {
        String(prefix(8))
    }
}
