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

    func testTransportFailuresExplainLocalNetworkTroubleshooting() async {
        let client = ThrowingHTTPClient(error: APIClientError.transport)
        let provider = VercelProvider(client: client)
        let account = ProviderAccount(provider: .vercel, displayName: "Vercel", tokenReference: "token")

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "vercel_secret"))

        XCTAssertEqual(result.snapshots, [])
        XCTAssertEqual(result.issues.first?.kind, .network)
        XCTAssertEqual(
            result.issues.first?.message,
            "Network connection issue: could not reach Vercel API. Check your internet, VPN, or proxy connection."
        )
    }

    func testSharedTransportFailuresExplainLocalNetworkTroubleshooting() async {
        let client = ThrowingHTTPClient(error: APIClientError.transport)
        let provider = NetlifyProvider(client: client)
        let account = ProviderAccount(provider: .netlify, displayName: "Netlify", tokenReference: "token")

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "netlify_secret"))

        XCTAssertEqual(result.snapshots, [])
        XCTAssertEqual(result.issues.first?.kind, .network)
        XCTAssertEqual(
            result.issues.first?.message,
            "Network connection issue: could not reach Netlify API. Check your internet, VPN, or proxy connection."
        )
    }

    func testNetlifyProviderListsSitesWhenNoTargetsConfigured() async throws {
        let sitesBody = """
        [
          { "id": "site_123", "name": "docs" }
        ]
        """.data(using: .utf8)!
        let deploysBody = """
        [
          {
            "id": "deploy_123",
            "name": "docs",
            "state": "ready",
            "created_at": "2026-05-21T10:00:00Z",
            "updated_at": "2026-05-21T10:01:00Z"
          }
        ]
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: sitesBody),
            HTTPResponse(statusCode: 200, data: deploysBody)
        ])
        let provider = NetlifyProvider(client: client, limit: 3, siteLimit: 5)
        let account = ProviderAccount(provider: .netlify, displayName: "Netlify", tokenReference: "token")

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "netlify_secret"))
        let requests = await client.requests

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.snapshots.count, 1)
        XCTAssertEqual(result.snapshots[0].projectName, "docs")
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer netlify_secret")
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.path, "/api/v1/sites")
        XCTAssertEqual(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.path, "/api/v1/sites/site_123/deploys")
    }

    func testNetlifyDiscoveryListsSitesWithoutFetchingDeploys() async throws {
        let sitesBody = """
        [
          { "id": "site_123", "name": "docs" }
        ]
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [HTTPResponse(statusCode: 200, data: sitesBody)])
        let provider = NetlifyProvider(client: client, siteLimit: 5)
        let account = ProviderAccount(provider: .netlify, displayName: "Netlify", tokenReference: "token")

        let result = await provider.discoverTargets(token: "netlify_secret", account: account)
        let requests = await client.requests

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.targets.count, 1)
        XCTAssertEqual(result.targets[0].projectID, "site_123")
        XCTAssertEqual(result.targets[0].projectName, "docs")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.path, "/api/v1/sites")
    }

    func testCloudflarePagesProviderRequiresAccountID() async {
        let provider = CloudflarePagesProvider(client: RecordingHTTPClient(responses: []))
        let account = ProviderAccount(provider: .cloudflarePages, displayName: "Cloudflare", tokenReference: "token")

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "cloudflare_secret"))

        XCTAssertEqual(result.snapshots, [])
        XCTAssertEqual(result.issues.first?.kind, .notConfigured)
    }

    func testCloudflarePagesProviderListsProjectsWhenNoTargetsConfigured() async throws {
        let projectsBody = """
        {
          "success": true,
          "result": [
            { "id": "prj_123", "name": "web", "production_branch": "main" }
          ]
        }
        """.data(using: .utf8)!
        let deploymentsBody = """
        {
          "success": true,
          "result": [
            {
              "id": "pages_dep_123",
              "project_name": "web",
              "environment": "production",
              "created_on": "2026-05-21T10:00:00Z",
              "latest_stage": { "status": "success", "ended_on": "2026-05-21T10:01:00Z" }
            }
          ]
        }
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: projectsBody),
            HTTPResponse(statusCode: 200, data: deploymentsBody)
        ])
        let provider = CloudflarePagesProvider(client: client, limit: 2, projectLimit: 5)
        let account = ProviderAccount(provider: .cloudflarePages, displayName: "Cloudflare", tokenReference: "token", teamID: "acct_123")

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "cloudflare_secret"))
        let requests = await client.requests

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.snapshots.count, 1)
        XCTAssertEqual(result.snapshots[0].status, .success)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer cloudflare_secret")
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.path, "/client/v4/accounts/acct_123/pages/projects")
        XCTAssertNil(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.query)
        XCTAssertEqual(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.path, "/client/v4/accounts/acct_123/pages/projects/web/deployments")
    }

    func testCloudflarePagesProviderSurfacesAPIErrorMessage() async throws {
        let errorBody = """
        {
          "success": false,
          "errors": [
            { "code": 8000002, "message": "invalid account identifier" }
          ]
        }
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [HTTPResponse(statusCode: 400, data: errorBody)])
        let provider = CloudflarePagesProvider(client: client, projectLimit: 5)
        let account = ProviderAccount(provider: .cloudflarePages, displayName: "Cloudflare", tokenReference: "token", teamID: "bad_account")

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "cloudflare_secret"))

        XCTAssertEqual(result.snapshots, [])
        XCTAssertEqual(result.issues.first?.message, "Cloudflare Pages API returned HTTP 400: invalid account identifier (8000002)")
    }

    func testCloudflarePagesDiscoveryListsAccountsAndTargets() async throws {
        let accountsBody = """
        {
          "success": true,
          "result": [
            { "account": { "id": "acct_123", "name": "Acme" } }
          ]
        }
        """.data(using: .utf8)!
        let projectsBody = """
        {
          "success": true,
          "result": [
            { "id": "prj_123", "name": "web", "production_branch": "main" }
          ]
        }
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: accountsBody),
            HTTPResponse(statusCode: 200, data: projectsBody)
        ])
        let provider = CloudflarePagesProvider(client: client, projectLimit: 5)

        let accountResult = await provider.discoverAccounts(token: "cloudflare_secret")
        let targetAccount = ProviderAccount(provider: .cloudflarePages, displayName: "Cloudflare", tokenReference: "token", teamID: "acct_123")
        let targetResult = await provider.discoverTargets(token: "cloudflare_secret", account: targetAccount)
        let requests = await client.requests

        XCTAssertEqual(accountResult.issues, [])
        XCTAssertEqual(accountResult.scopes.first?.id, "acct_123")
        XCTAssertEqual(accountResult.scopes.first?.name, "Acme")
        XCTAssertEqual(targetResult.issues, [])
        XCTAssertEqual(targetResult.targets.first?.projectID, "prj_123")
        XCTAssertEqual(targetResult.targets.first?.projectName, "web")
        XCTAssertEqual(targetResult.targets.first?.branch, "main")
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.path, "/client/v4/memberships")
        XCTAssertEqual(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.path, "/client/v4/accounts/acct_123/pages/projects")
    }

    func testGitHubProviderFetchesLatestDeploymentStatus() async throws {
        let deploymentsBody = """
        [
          {
            "id": 123,
            "sha": "abc123",
            "ref": "main",
            "task": "deploy",
            "environment": "production",
            "description": "Deploy production",
            "statuses_url": "https://api.github.com/repos/acme/api/deployments/123/statuses",
            "created_at": "2026-05-21T10:00:00Z",
            "updated_at": "2026-05-21T10:00:00Z",
            "creator": { "login": "dev" }
          }
        ]
        """.data(using: .utf8)!
        let statusesBody = """
        [
          {
            "id": 456,
            "state": "success",
            "description": "Deployment passed",
            "environment_url": "",
            "target_url": "https://api.example.com",
            "log_url": "",
            "created_at": "2026-05-21T10:01:00Z",
            "updated_at": "2026-05-21T10:01:00Z",
            "creator": { "login": "deploy-bot" }
          }
        ]
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: deploymentsBody),
            HTTPResponse(statusCode: 200, data: statusesBody)
        ])
        let provider = GitHubDeploymentsProvider(client: client, limit: 4)
        let account = ProviderAccount(
            provider: .github,
            displayName: "GitHub",
            tokenReference: "token",
            monitoredTargets: [MonitoredTarget(projectID: "acme/api", environmentName: "production")]
        )

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "github_secret"))
        let requests = await client.requests

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.snapshots.count, 1)
        XCTAssertEqual(result.snapshots[0].status, .success)
        XCTAssertEqual(result.snapshots[0].actor, "deploy-bot")
        XCTAssertEqual(result.snapshots[0].deploymentURL?.absoluteString, "https://api.example.com")
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer github_secret")
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.path, "/repos/acme/api/deployments")
    }

    func testGitHubDiscoveryListsAccessibleRepositories() async throws {
        let body = """
        [
          { "full_name": "acme/api" },
          { "full_name": "acme/web" }
        ]
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [HTTPResponse(statusCode: 200, data: body)])
        let provider = GitHubDeploymentsProvider(client: client)
        let account = ProviderAccount(provider: .github, displayName: "GitHub", tokenReference: "token")

        let result = await provider.discoverTargets(token: "github_secret", account: account)
        let requests = await client.requests
        let components = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.targets.map(\.projectID), ["acme/api", "acme/web"])
        XCTAssertEqual(result.targets.map(\.projectName), ["acme/api", "acme/web"])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer github_secret")
        XCTAssertEqual(components?.path, "/user/repos")
        XCTAssertEqual(query["affiliation"], "owner,collaborator,organization_member")
        XCTAssertEqual(query["sort"], "updated")
        XCTAssertEqual(query["per_page"], "100")
    }

    func testGitLabProviderBuildsAuthenticatedDeploymentRequest() async throws {
        let body = """
        [
          {
            "id": 123,
            "ref": "main",
            "sha": "abc123",
            "status": "running",
            "created_at": "2026-05-21T10:00:00Z",
            "updated_at": "2026-05-21T10:01:00Z",
            "environment": { "name": "production" }
          }
        ]
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [HTTPResponse(statusCode: 200, data: body)])
        let provider = GitLabDeploymentsProvider(client: client, limit: 6)
        let account = ProviderAccount(
            provider: .gitlab,
            displayName: "GitLab",
            tokenReference: "token",
            monitoredTargets: [MonitoredTarget(projectID: "acme/api", projectName: "acme/api", environmentName: "production")]
        )

        let result = await provider.fetchDeployments(context: ProviderContext(account: account, token: "gitlab_secret"))
        let requests = await client.requests

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.snapshots.count, 1)
        XCTAssertEqual(result.snapshots[0].status, .deploying)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab_secret")
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.percentEncodedPath, "/api/v4/projects/acme%2Fapi/deployments")
    }

    func testGitLabDiscoveryListsMembershipProjectsWithBearerToken() async throws {
        let body = """
        [
          { "path_with_namespace": "acme/api" },
          { "path_with_namespace": "acme/web" }
        ]
        """.data(using: .utf8)!
        let client = RecordingHTTPClient(responses: [HTTPResponse(statusCode: 200, data: body)])
        let provider = GitLabDeploymentsProvider(client: client, baseURL: URL(string: "https://gitlab.example.com/api/v4")!)
        let account = ProviderAccount(
            provider: .gitlab,
            displayName: "GitLab",
            tokenReference: "token",
            authHeader: .bearer
        )

        let result = await provider.discoverTargets(token: "gitlab_oauth_secret", account: account)
        let requests = await client.requests
        let components = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.targets.map(\.projectID), ["acme/api", "acme/web"])
        XCTAssertEqual(result.targets.map(\.projectName), ["acme/api", "acme/web"])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer gitlab_oauth_secret")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "PRIVATE-TOKEN"))
        XCTAssertEqual(components?.path, "/api/v4/projects")
        XCTAssertEqual(query["membership"], "true")
        XCTAssertEqual(query["order_by"], "last_activity_at")
        XCTAssertEqual(query["sort"], "desc")
        XCTAssertEqual(query["per_page"], "100")
    }
}

private final class ThrowingHTTPClient: HTTPClient, @unchecked Sendable {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func send(_: URLRequest) async throws -> HTTPResponse {
        throw error
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
