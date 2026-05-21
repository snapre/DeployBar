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
}
