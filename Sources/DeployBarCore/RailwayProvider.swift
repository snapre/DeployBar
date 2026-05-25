import Foundation

public struct RailwayProvider: DeploymentProvider {
    public let id: ProviderID = .railway
    public let displayName = "Railway"

    private let client: any HTTPClient
    private let endpointURL: URL
    private let limit: Int

    public init(
        client: any HTTPClient = APIClient(),
        endpointURL: URL = URL(string: "https://backboard.railway.com/graphql/v2")!,
        limit: Int = 10
    ) {
        self.client = client
        self.endpointURL = endpointURL
        self.limit = limit
    }

    public func fetchDeployments(context: ProviderContext) async -> ProviderRefreshResult {
        guard let token = context.token, !token.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Railway API token is not configured.")]
            )
        }

        guard !context.account.monitoredTargets.isEmpty else {
            return ProviderRefreshResult(
                snapshots: [],
                issues: [ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Railway requires at least one monitored service/environment target.")]
            )
        }

        var snapshots: [DeploymentSnapshot] = []
        var issues: [ProviderIssue] = []

        for target in context.account.monitoredTargets {
            guard target.serviceID?.isEmpty == false, target.environmentID?.isEmpty == false else {
                issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .notConfigured, message: "Railway target needs service and environment IDs."))
                continue
            }

            do {
                let request = try makeRequest(account: context.account, token: token, target: target)
                let response = try await client.send(request)

                if let message = RailwayParser.graphQLErrorMessage(from: response.data) {
                    issues.append(graphQLIssue(message: message, accountID: context.account.id))
                    continue
                }

                if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: context.account.id, statusCode: response.statusCode) {
                    issues.append(issue)
                    continue
                }

                do {
                    let parsed = try RailwayParser.snapshots(from: response.data, account: context.account, target: target, now: context.now())
                    snapshots.append(contentsOf: parsed)
                } catch RailwayParsingError.graphQLErrors(let message) {
                    issues.append(graphQLIssue(message: message, accountID: context.account.id))
                } catch {
                    issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .apiChanged, message: "Railway API response could not be parsed."))
                }
            } catch let error as APIClientError {
                issues.append(issue(for: error, accountID: context.account.id))
            } catch {
                issues.append(ProviderIssue(provider: id, accountID: context.account.id, kind: .unknown, message: "Could not build Railway API request."))
            }
        }

        return ProviderRefreshResult(snapshots: Self.deduplicated(snapshots), issues: issues)
    }

    public func discoverResources(token: String, tokenKind: RailwayTokenKind) async -> RailwayDiscoveryResult {
        guard !token.isEmpty else {
            return RailwayDiscoveryResult(
                issues: [ProviderIssue(provider: id, kind: .notConfigured, message: "Railway API token is not configured.")]
            )
        }

        switch tokenKind {
        case .accountOrWorkspace:
            return await fetchDiscoverProjects(token: token, tokenKind: tokenKind)
        case .project:
            let scoped = await fetchProjectTokenScope(token: token)
            guard let project = scoped.projects.first else {
                return scoped
            }

            let detailed = await fetchProjectDetails(token: token, tokenKind: tokenKind, projectID: project.id)
            if let detailedProject = detailed.projects.first, !detailedProject.services.isEmpty {
                return detailed
            }

            if !scoped.issues.isEmpty {
                return scoped
            }

            var mergedProject = project
            if let detailedProject = detailed.projects.first {
                mergedProject.name = detailedProject.name
                if !detailedProject.environments.isEmpty {
                    mergedProject.environments = detailedProject.environments
                }
            }
            return RailwayDiscoveryResult(projects: [mergedProject])
        }
    }

    private func makeRequest(account: ProviderAccount, token: String, target: MonitoredTarget) throws -> URLRequest {
        let body = RailwayGraphQLRequest(
            query: Self.deploymentsQuery,
            variables: RailwayDeploymentsVariables(
                first: limit,
                input: RailwayDeploymentListInput(
                    projectId: target.projectID,
                    serviceId: target.serviceID,
                    environmentId: target.environmentID
                )
            )
        )
        return try makeGraphQLRequest(token: token, tokenKind: account.railwayTokenKind ?? .accountOrWorkspace, body: body)
    }

    private func fetchDiscoverProjects(token: String, tokenKind: RailwayTokenKind) async -> RailwayDiscoveryResult {
        do {
            let request = try makeGraphQLRequest(
                token: token,
                tokenKind: tokenKind,
                body: RailwayGraphQLRequest(query: Self.projectsQuery, variables: EmptyVariables())
            )
            let response = try await client.send(request)
            if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: nil, statusCode: response.statusCode) {
                return RailwayDiscoveryResult(issues: [issue])
            }
            return RailwayDiscoveryResult(projects: try RailwayDiscoveryParser.projects(from: response.data))
        } catch RailwayParsingError.graphQLErrors(let message) {
            return RailwayDiscoveryResult(issues: [graphQLIssue(message: message, accountID: "")])
        } catch let error as APIClientError {
            return RailwayDiscoveryResult(issues: [issue(for: error, accountID: "")])
        } catch {
            return RailwayDiscoveryResult(issues: [ProviderIssue(provider: id, kind: .apiChanged, message: "Railway discovery response could not be parsed.")])
        }
    }

    private func fetchProjectDetails(token: String, tokenKind: RailwayTokenKind, projectID: String) async -> RailwayDiscoveryResult {
        do {
            let request = try makeGraphQLRequest(
                token: token,
                tokenKind: tokenKind,
                body: RailwayGraphQLRequest(query: Self.projectDetailsQuery, variables: ProjectDetailsVariables(id: projectID))
            )
            let response = try await client.send(request)
            if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: nil, statusCode: response.statusCode) {
                return RailwayDiscoveryResult(issues: [issue])
            }
            return RailwayDiscoveryResult(projects: try RailwayDiscoveryParser.projects(from: response.data))
        } catch RailwayParsingError.graphQLErrors(let message) {
            return RailwayDiscoveryResult(issues: [graphQLIssue(message: message, accountID: "")])
        } catch let error as APIClientError {
            return RailwayDiscoveryResult(issues: [issue(for: error, accountID: "")])
        } catch {
            return RailwayDiscoveryResult(issues: [ProviderIssue(provider: id, kind: .apiChanged, message: "Railway project discovery response could not be parsed.")])
        }
    }

    private func fetchProjectTokenScope(token: String) async -> RailwayDiscoveryResult {
        do {
            let request = try makeGraphQLRequest(
                token: token,
                tokenKind: .project,
                body: RailwayGraphQLRequest(query: Self.projectTokenQuery, variables: EmptyVariables())
            )
            let response = try await client.send(request)
            if let issue = ProviderIssue.fromHTTPStatus(provider: id, accountID: nil, statusCode: response.statusCode) {
                return RailwayDiscoveryResult(issues: [issue])
            }
            return RailwayDiscoveryResult(projects: try RailwayDiscoveryParser.projects(from: response.data))
        } catch RailwayParsingError.graphQLErrors(let message) {
            return RailwayDiscoveryResult(issues: [graphQLIssue(message: message, accountID: "")])
        } catch let error as APIClientError {
            return RailwayDiscoveryResult(issues: [issue(for: error, accountID: "")])
        } catch {
            return RailwayDiscoveryResult(issues: [ProviderIssue(provider: id, kind: .apiChanged, message: "Railway project token response could not be parsed.")])
        }
    }

    private func makeGraphQLRequest<Variables: Encodable>(
        token: String,
        tokenKind: RailwayTokenKind,
        body: RailwayGraphQLRequest<Variables>
    ) throws -> URLRequest {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DeployBar/0.1", forHTTPHeaderField: "User-Agent")

        if tokenKind == .project {
            request.setValue(token, forHTTPHeaderField: "Project-Access-Token")
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder.deployBar.encode(body)
        return request
    }

    private func issue(for error: APIClientError, accountID: String) -> ProviderIssue {
        ProviderUtilities.issue(for: error, provider: id, accountID: accountID)
    }

    private func graphQLIssue(message: String, accountID: String) -> ProviderIssue {
        let lowercased = message.lowercased()
        if lowercased.contains("not authorized") || lowercased.contains("unauthorized") {
            return ProviderIssue(provider: id, accountID: accountID, kind: .authentication, message: "Railway authentication failed.")
        }
        if lowercased.contains("cannot query field") || lowercased.contains("unknown argument") {
            return ProviderIssue(provider: id, accountID: accountID, kind: .apiChanged, message: "Railway GraphQL schema changed: \(shortMessage(message))")
        }
        return ProviderIssue(provider: id, accountID: accountID, kind: .apiChanged, message: "Railway GraphQL error: \(shortMessage(message))")
    }

    private func shortMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return trimmed }
        return "\(trimmed.prefix(177))..."
    }

    private static func deduplicated(_ snapshots: [DeploymentSnapshot]) -> [DeploymentSnapshot] {
        var seen = Set<String>()
        return snapshots.filter { snapshot in
            seen.insert(snapshot.id).inserted
        }
    }

    private static let deploymentsQuery = """
    query Deployments($first: Int!, $input: DeploymentListInput!) {
      deployments(first: $first, input: $input) {
        edges {
          node {
            id
            status
            createdAt
            updatedAt
            statusUpdatedAt
            url
            staticUrl
            meta
          }
        }
      }
    }
    """

    private static let projectsQuery = """
    query DiscoverRailwayProjects {
      projects(first: 50) {
        edges {
          node {
            id
            name
            services {
              edges {
                node {
                  id
                  name
                }
              }
            }
            environments {
              edges {
                node {
                  id
                  name
                }
              }
            }
          }
        }
      }
    }
    """

    private static let projectDetailsQuery = """
    query DiscoverRailwayProject($id: String!) {
      project(id: $id) {
        id
        name
        services {
          edges {
            node {
              id
              name
            }
          }
        }
        environments {
          edges {
            node {
              id
              name
            }
          }
        }
      }
    }
    """

    private static let projectTokenQuery = """
    query DiscoverRailwayProjectToken {
      projectToken {
        projectId
        environmentId
      }
    }
    """
}

private struct RailwayGraphQLRequest<Variables: Encodable>: Encodable {
    var query: String
    var variables: Variables
}

private struct RailwayDeploymentsVariables: Encodable {
    var first: Int
    var input: RailwayDeploymentListInput
}

private struct RailwayDeploymentListInput: Encodable {
    var projectId: String?
    var serviceId: String?
    var environmentId: String?
}

private struct ProjectDetailsVariables: Encodable {
    var id: String
}

private struct EmptyVariables: Encodable {}
