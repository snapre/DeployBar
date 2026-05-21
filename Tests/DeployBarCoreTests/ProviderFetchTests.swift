import DeployBarCore
import XCTest

final class ProviderFetchTests: XCTestCase {
    func testVercelProviderBuildsFilteredAuthenticatedRequest() async throws {
        let body = """
        {
          "deployments": [
            {
              "uid": "dpl_123",
              "name": "web",
              "url": "web-example.vercel.app",
              "state": "BUILDING",
              "readyState": "BUILDING",
              "target": "production",
              "created": 1710000000000
            }
          ]
        }
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [HTTPResponse(statusCode: 200, data: body)])
        let provider = VercelProvider(client: client, limit: 5)
        let account = ProviderAccount(
            provider: .vercel,
            displayName: "Acme",
            tokenReference: "token",
            teamSlug: "acme",
            monitoredTargets: [
                MonitoredTarget(projectName: "web", environmentName: "production", branch: "main")
            ]
        )

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "vercel_secret"))
        let requests = await client.requests

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.snapshots.count, 1)
        XCTAssertEqual(result.snapshots[0].status, .building)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer vercel_secret")

        let components = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)
        let queryItems = Dictionary(uniqueKeysWithValues: components!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(queryItems["slug"], "acme")
        XCTAssertEqual(queryItems["projectId"], "web")
        XCTAssertEqual(queryItems["target"], "production")
        XCTAssertEqual(queryItems["branch"], "main")
        XCTAssertEqual(queryItems["limit"], "5")
    }

    func testVercelDiscoveryListsProjectsAndRecentHints() async throws {
        let projectsBody = """
        {
          "projects": [
            { "id": "prj_123", "name": "web" }
          ]
        }
        """.data(using: .utf8)!
        let deploymentsBody = """
        {
          "deployments": [
            {
              "uid": "dpl_123",
              "name": "web",
              "projectId": "prj_123",
              "state": "READY",
              "target": "production",
              "created": 1710000000000,
              "meta": {
                "githubCommitRef": "main"
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: projectsBody),
            HTTPResponse(statusCode: 200, data: deploymentsBody)
        ])
        let provider = VercelProvider(client: client)
        let account = ProviderAccount(provider: .vercel, displayName: "Vercel", tokenReference: "token", teamSlug: "acme")

        let result = await provider.discoverResources(token: "vercel_secret", account: account)
        let requests = await client.requests

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.projects.first?.id, "prj_123")
        XCTAssertEqual(result.projects.first?.name, "web")
        XCTAssertEqual(result.projects.first?.environments, ["production"])
        XCTAssertEqual(result.projects.first?.branches, ["main"])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer vercel_secret")
        XCTAssertEqual(URLComponents(url: requests.first!.url!, resolvingAgainstBaseURL: false)?.path, "/v10/projects")
    }

    func testRailwayProviderUsesProjectTokenHeaderAndGraphQLVariables() async throws {
        let body = """
        {
          "data": {
            "deployments": {
              "edges": [
                {
                  "node": {
                    "id": "dep_123",
                    "status": "SUCCESS",
                    "createdAt": "2026-05-21T10:00:00.000Z",
                    "updatedAt": "2026-05-21T10:01:00.000Z",
                    "statusUpdatedAt": "2026-05-21T10:01:00.000Z",
                    "projectId": "project_123",
                    "serviceId": "service_123",
                    "environmentId": "env_123",
                    "url": "https://api.up.railway.app",
                    "staticUrl": null,
                    "diagnosis": null,
                    "project": { "name": "backend" },
                    "service": { "name": "api" },
                    "environment": { "name": "production" }
                  }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [HTTPResponse(statusCode: 200, data: body)])
        let provider = RailwayProvider(client: client, limit: 3)
        let account = ProviderAccount(
            provider: .railway,
            displayName: "Railway",
            tokenReference: "token",
            railwayTokenKind: .project,
            monitoredTargets: [
                MonitoredTarget(projectID: "project_123", serviceID: "service_123", environmentID: "env_123")
            ]
        )

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "railway_secret"))
        let requests = await client.requests

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.snapshots.count, 1)
        XCTAssertEqual(result.snapshots[0].status, .success)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Project-Access-Token"), "railway_secret")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))

        let bodyObject = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: Any]
        let variables = bodyObject["variables"] as! [String: Any]
        let input = variables["input"] as! [String: Any]
        XCTAssertEqual(variables["first"] as? Int, 3)
        XCTAssertEqual(input["projectId"] as? String, "project_123")
        XCTAssertEqual(input["serviceId"] as? String, "service_123")
        XCTAssertEqual(input["environmentId"] as? String, "env_123")
    }

    func testRailwayProviderRequiresTargets() async {
        let provider = RailwayProvider(client: RecordingHTTPClient(responses: []))
        let account = ProviderAccount(provider: .railway, displayName: "Railway", tokenReference: "token")

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "secret"))

        XCTAssertEqual(result.snapshots, [])
        XCTAssertEqual(result.issues.first?.kind, .notConfigured)
    }

    func testRailwayProviderSurfacesGraphQLErrorFromHTTP400Body() async {
        let body = """
        {
          "errors": [
            { "message": "Cannot query field \\"url\\" on type \\"Deployment\\"." }
          ]
        }
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [HTTPResponse(statusCode: 400, data: body)])
        let provider = RailwayProvider(client: client)
        let account = ProviderAccount(
            provider: .railway,
            displayName: "Railway",
            tokenReference: "token",
            railwayTokenKind: .accountOrWorkspace,
            monitoredTargets: [
                MonitoredTarget(projectID: "project_123", serviceID: "service_123", environmentID: "env_123")
            ]
        )

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "railway_secret"))

        XCTAssertEqual(result.snapshots, [])
        XCTAssertEqual(result.issues.first?.kind, .apiChanged)
        XCTAssertTrue(result.issues.first?.message.contains("Cannot query field") ?? false)
        XCTAssertFalse(result.issues.first?.message.contains("railway_secret") ?? true)
    }

    func testRailwayDiscoveryListsProjectsServicesAndEnvironments() async throws {
        let body = """
        {
          "data": {
            "projects": {
              "edges": [
                {
                  "node": {
                    "id": "project_123",
                    "name": "backend",
                    "services": {
                      "edges": [
                        { "node": { "id": "service_123", "name": "api" } }
                      ]
                    },
                    "environments": {
                      "edges": [
                        { "node": { "id": "env_123", "name": "production" } }
                      ]
                    }
                  }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [HTTPResponse(statusCode: 200, data: body)])
        let provider = RailwayProvider(client: client)

        let result = await provider.discoverResources(token: "railway_secret", tokenKind: .accountOrWorkspace)
        let requests = await client.requests

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.projects.first?.name, "backend")
        XCTAssertEqual(result.projects.first?.services.first?.name, "api")
        XCTAssertEqual(result.projects.first?.environments.first?.name, "production")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer railway_secret")
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Project-Access-Token"))
    }

    func testRailwayProjectTokenDiscoveryFallsBackToTokenScope() async {
        let tokenScopeBody = """
        {
          "data": {
            "projectToken": {
              "projectId": "project_123456789",
              "environmentId": "env_123456789"
            }
          }
        }
        """.data(using: .utf8)!
        let projectDetailsErrorBody = """
        {
          "errors": [
            { "message": "Not Authorized" }
          ]
        }
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: tokenScopeBody),
            HTTPResponse(statusCode: 200, data: projectDetailsErrorBody)
        ])
        let provider = RailwayProvider(client: client)

        let result = await provider.discoverResources(token: "railway_project_secret", tokenKind: .project)
        let requests = await client.requests

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.projects.first?.id, "project_123456789")
        XCTAssertEqual(result.projects.first?.environments.first?.id, "env_123456789")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Project-Access-Token"), "railway_project_secret")
    }

    func testProviderMapsAuthenticationStatusWithoutTokenInMessage() async {
        let client = RecordingHTTPClient(responses: [HTTPResponse(statusCode: 401, data: Data())])
        let provider = VercelProvider(client: client)
        let account = ProviderAccount(provider: .vercel, displayName: "Vercel", tokenReference: "token")

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "super_secret_token"))

        XCTAssertEqual(result.issues.first?.kind, .authentication)
        XCTAssertFalse(result.issues.first?.message.contains("super_secret_token") ?? true)
    }
}

private final class RecordingHTTPClient: HTTPClient, @unchecked Sendable {
    private let state: RecordingHTTPClientState

    init(responses: [HTTPResponse]) {
        self.state = RecordingHTTPClientState(responses: responses)
    }

    var requests: [URLRequest] {
        get async {
            await state.requests
        }
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        await state.send(request)
    }
}

private actor RecordingHTTPClientState {
    private(set) var requests: [URLRequest] = []
    private var responses: [HTTPResponse]

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) -> HTTPResponse {
        requests.append(request)
        if responses.isEmpty {
            return HTTPResponse(statusCode: 500, data: Data())
        }
        return responses.removeFirst()
    }
}
