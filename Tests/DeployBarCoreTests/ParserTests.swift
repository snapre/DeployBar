import DeployBarCore
import XCTest

final class ParserTests: XCTestCase {
    func testVercelDeploymentParsing() throws {
        let json = """
        {
          "deployments": [
            {
              "uid": "dpl_123",
              "name": "web",
              "url": "web-example.vercel.app",
              "created": 1710000000000,
              "state": "READY",
              "readyState": "READY",
              "target": "production",
              "buildingAt": 1710000001000,
              "ready": 1710000061000,
              "creator": {
                "email": "dev@example.com",
                "username": "dev"
              },
              "inspectorUrl": "https://vercel.com/acme/web/dpl_123",
              "meta": {
                "githubCommitRef": "main",
                "githubCommitSha": "abcdef123456",
                "githubCommitMessage": "Ship menu bar"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let account = ProviderAccount(provider: .vercel, displayName: "Vercel", tokenReference: "token")
        let snapshots = try VercelParser.snapshots(from: json, account: account, now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].id, "vercel:\(account.id):dpl_123")
        XCTAssertEqual(snapshots[0].projectName, "web")
        XCTAssertEqual(snapshots[0].status, .ready)
        XCTAssertEqual(snapshots[0].severity, .healthy)
        XCTAssertEqual(snapshots[0].branch, "main")
        XCTAssertEqual(snapshots[0].commitSha, "abcdef123456")
        XCTAssertEqual(snapshots[0].commitMessage, "Ship menu bar")
        XCTAssertEqual(snapshots[0].actor, "dev")
        XCTAssertEqual(snapshots[0].deploymentURL?.absoluteString, "https://web-example.vercel.app")
        XCTAssertEqual(snapshots[0].duration, 60)
    }

    func testRailwayDeploymentParsing() throws {
        let json = """
        {
          "data": {
            "deployments": {
              "edges": [
                {
                  "node": {
                    "id": "dep_123",
                    "status": "FAILED",
                    "createdAt": "2026-05-21T10:00:00Z",
                    "updatedAt": "2026-05-21T10:03:00Z",
                    "statusUpdatedAt": "2026-05-21T10:03:00Z",
                    "projectId": "project_123",
                    "serviceId": "service_123",
                    "environmentId": "env_123",
                    "url": "https://api.up.railway.app",
                    "staticUrl": null,
                    "diagnosis": "Healthcheck failed",
                    "meta": {
                      "branch": "main",
                      "commitSha": "123456abcdef",
                      "commitMessage": "Fix healthcheck path",
                      "commitAuthor": "dev"
                    },
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

        let account = ProviderAccount(provider: .railway, displayName: "Railway", tokenReference: "token")
        let snapshots = try RailwayParser.snapshots(from: json, account: account, now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].projectName, "backend")
        XCTAssertEqual(snapshots[0].serviceName, "api")
        XCTAssertEqual(snapshots[0].environmentName, "production")
        XCTAssertEqual(snapshots[0].status, .failed)
        XCTAssertEqual(snapshots[0].severity, .critical)
        XCTAssertEqual(snapshots[0].branch, "main")
        XCTAssertEqual(snapshots[0].commitSha, "123456abcdef")
        XCTAssertEqual(snapshots[0].commitMessage, "Fix healthcheck path")
        XCTAssertEqual(snapshots[0].actor, "dev")
        XCTAssertEqual(snapshots[0].deploymentURL?.absoluteString, "https://api.up.railway.app")
        XCTAssertEqual(snapshots[0].errorMessage, "Healthcheck failed")
        XCTAssertEqual(snapshots[0].duration, 180)
    }

    func testRailwayParsingUsesFallbackTargetWhenResponseOmitsResourceIDs() throws {
        let json = """
        {
          "data": {
            "deployments": {
              "edges": [
                {
                  "node": {
                    "id": "dep_srome",
                    "status": "SUCCESS",
                    "createdAt": "2026-05-21T10:00:00Z",
                    "updatedAt": "2026-05-21T10:01:00Z",
                    "statusUpdatedAt": "2026-05-21T10:01:00Z",
                    "url": null,
                    "staticUrl": null,
                    "diagnosis": null,
                    "meta": {}
                  }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let firstTarget = MonitoredTarget(
            projectID: "project_pmf",
            projectName: "pmf-agent",
            serviceID: "service_pmf",
            serviceName: "@pmf-agent/api",
            environmentID: "env_pmf",
            environmentName: "production"
        )
        let secondTarget = MonitoredTarget(
            projectID: "project_srome",
            projectName: "srome",
            serviceID: "service_srome",
            serviceName: "@srome/api",
            environmentID: "env_srome",
            environmentName: "production"
        )
        let account = ProviderAccount(
            provider: .railway,
            displayName: "Railway",
            tokenReference: "token",
            monitoredTargets: [firstTarget, secondTarget]
        )

        let snapshots = try RailwayParser.snapshots(
            from: json,
            account: account,
            target: secondTarget,
            now: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].projectName, "srome")
        XCTAssertEqual(snapshots[0].serviceName, "@srome/api")
        XCTAssertEqual(snapshots[0].environmentName, "production")
    }

    func testNetlifyDeploymentParsing() throws {
        let json = """
        [
          {
            "id": "deploy_123",
            "site_id": "site_123",
            "name": "docs",
            "state": "ready",
            "context": "production",
            "branch": "main",
            "commit_ref": "abc123",
            "title": "Publish docs",
            "committer": "dev@example.com",
            "deploy_ssl_url": "https://docs.netlify.app",
            "admin_url": "https://app.netlify.com/sites/docs/deploys/deploy_123",
            "created_at": "2026-05-21T10:00:00Z",
            "updated_at": "2026-05-21T10:01:00Z",
            "published_at": "2026-05-21T10:01:00Z"
          }
        ]
        """.data(using: .utf8)!

        let account = ProviderAccount(provider: .netlify, displayName: "Netlify", tokenReference: "token")
        let target = MonitoredTarget(projectID: "site_123", projectName: "docs")
        let snapshots = try NetlifyParser.snapshots(from: json, account: account, target: target, now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].id, "netlify:\(account.id):deploy_123")
        XCTAssertEqual(snapshots[0].projectName, "docs")
        XCTAssertEqual(snapshots[0].environmentName, "production")
        XCTAssertEqual(snapshots[0].status, .ready)
        XCTAssertEqual(snapshots[0].deploymentURL?.absoluteString, "https://docs.netlify.app")
        XCTAssertEqual(snapshots[0].duration, 60)
    }

    func testNetlifyNoContentChangeDeployIsSkipped() throws {
        let json = """
        [
          {
            "id": "deploy_123",
            "site_id": "site_123",
            "name": "docs",
            "state": "error",
            "context": "production",
            "branch": "main",
            "commit_ref": "abc123",
            "title": "Publish docs",
            "error_message": "Failed during stage 'checking build content for changes': Canceled build due to no content change",
            "created_at": "2026-05-21T10:00:00Z",
            "updated_at": "2026-05-21T10:01:00Z"
          }
        ]
        """.data(using: .utf8)!

        let account = ProviderAccount(provider: .netlify, displayName: "Netlify", tokenReference: "token")
        let target = MonitoredTarget(projectID: "site_123", projectName: "docs")
        let snapshots = try NetlifyParser.snapshots(from: json, account: account, target: target, now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshots[0].status, .skipped)
        XCTAssertEqual(snapshots[0].severity, .healthy)
        XCTAssertNil(snapshots[0].errorMessage)
    }

    func testRenderDeploymentParsing() throws {
        let json = """
        [
          {
            "deploy": {
              "id": "dep_123",
              "status": "build_failed",
              "createdAt": "2026-05-21T10:00:00Z",
              "updatedAt": "2026-05-21T10:02:00Z",
              "startedAt": "2026-05-21T10:00:30Z",
              "finishedAt": "2026-05-21T10:02:00Z",
              "failureReason": "Build command failed",
              "commit": {
                "id": "abc123",
                "message": "Fix build",
                "createdBy": "dev"
              }
            }
          }
        ]
        """.data(using: .utf8)!

        let account = ProviderAccount(provider: .render, displayName: "Render", tokenReference: "token")
        let target = MonitoredTarget(serviceID: "srv_123", serviceName: "api", environmentName: "web_service")
        let snapshots = try RenderParser.snapshots(from: json, account: account, target: target, now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].projectName, "api")
        XCTAssertEqual(snapshots[0].serviceName, "api")
        XCTAssertEqual(snapshots[0].status, .failed)
        XCTAssertEqual(snapshots[0].errorMessage, "Build command failed")
        XCTAssertEqual(snapshots[0].duration, 90)
    }

    func testCloudflarePagesDeploymentParsing() throws {
        let json = """
        {
          "success": true,
          "result": [
            {
              "id": "pages_dep_123",
              "project_name": "web",
              "environment": "production",
              "url": "https://web.pages.dev",
              "created_on": "2026-05-21T10:00:00Z",
              "modified_on": "2026-05-21T10:02:00Z",
              "latest_stage": {
                "name": "deploy",
                "status": "success",
                "ended_on": "2026-05-21T10:02:00Z"
              },
              "deployment_trigger": {
                "metadata": {
                  "branch": "main",
                  "commit_hash": "abc123",
                  "commit_message": "Ship pages",
                  "commit_author": "dev"
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let account = ProviderAccount(provider: .cloudflarePages, displayName: "Cloudflare", tokenReference: "token")
        let target = MonitoredTarget(projectName: "web")
        let snapshots = try CloudflarePagesParser.snapshots(from: json, account: account, target: target, now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].id, "cloudflarePages:\(account.id):pages_dep_123")
        XCTAssertEqual(snapshots[0].status, .success)
        XCTAssertEqual(snapshots[0].branch, "main")
        XCTAssertEqual(snapshots[0].commitSha, "abc123")
        XCTAssertEqual(snapshots[0].deploymentURL?.absoluteString, "https://web.pages.dev")
        XCTAssertEqual(snapshots[0].duration, 120)
    }

    func testDigitalOceanDeploymentParsing() throws {
        let json = """
        {
          "deployments": [
            {
              "id": "do_dep_123",
              "cause": "Manual deployment",
              "phase": "ACTIVE",
              "triggered_by": "dev@example.com",
              "created_at": "2026-05-21T10:00:00Z",
              "updated_at": "2026-05-21T10:03:00Z",
              "spec": {
                "name": "api",
                "branch": "main",
                "commit_sha": "abc123"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let account = ProviderAccount(provider: .digitalOcean, displayName: "DigitalOcean", tokenReference: "token")
        let target = MonitoredTarget(projectID: "app_123", projectName: "api")
        let snapshots = try DigitalOceanParser.snapshots(from: json, account: account, target: target, now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].id, "digitalOcean:\(account.id):do_dep_123")
        XCTAssertEqual(snapshots[0].status, .success)
        XCTAssertEqual(snapshots[0].commitSha, "abc123")
        XCTAssertEqual(snapshots[0].duration, 180)
    }

    func testHerokuReleaseParsing() throws {
        let json = """
        [
          {
            "id": "rel_123",
            "version": 42,
            "status": "succeeded",
            "current": true,
            "description": "Deploy abc123",
            "created_at": "2026-05-21T10:00:00Z",
            "updated_at": "2026-05-21T10:01:00Z",
            "app": { "id": "app_123", "name": "api" },
            "user": { "email": "dev@example.com" }
          }
        ]
        """.data(using: .utf8)!

        let account = ProviderAccount(provider: .heroku, displayName: "Heroku", tokenReference: "token")
        let target = MonitoredTarget(projectName: "api")
        let snapshots = try HerokuParser.snapshots(from: json, account: account, target: target, now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].id, "heroku:\(account.id):rel_123")
        XCTAssertEqual(snapshots[0].projectName, "api")
        XCTAssertEqual(snapshots[0].serviceName, "release v42")
        XCTAssertEqual(snapshots[0].status, .success)
        XCTAssertEqual(snapshots[0].actor, "dev@example.com")
        XCTAssertEqual(snapshots[0].duration, 60)
    }

    func testGitLabDeploymentParsing() throws {
        let json = """
        [
          {
            "id": 123,
            "ref": "main",
            "sha": "abc123",
            "status": "success",
            "created_at": "2026-05-21T10:00:00Z",
            "updated_at": "2026-05-21T10:04:00Z",
            "user": { "username": "dev" },
            "environment": {
              "name": "production",
              "external_url": "https://api.example.com"
            },
            "deployable": {
              "name": "deploy-production",
              "status": "success",
              "commit": { "title": "Ship API" }
            }
          }
        ]
        """.data(using: .utf8)!

        let account = ProviderAccount(provider: .gitlab, displayName: "GitLab", tokenReference: "token")
        let target = MonitoredTarget(projectName: "acme/api")
        let snapshots = try GitLabDeploymentsParser.snapshots(from: json, account: account, target: target, project: "acme/api", now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].id, "gitlab:\(account.id):123")
        XCTAssertEqual(snapshots[0].status, .success)
        XCTAssertEqual(snapshots[0].environmentName, "production")
        XCTAssertEqual(snapshots[0].deploymentURL?.absoluteString, "https://api.example.com")
        XCTAssertEqual(snapshots[0].duration, 240)
    }
}
