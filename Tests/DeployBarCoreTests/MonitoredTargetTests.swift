import DeployBarCore
import XCTest

final class MonitoredTargetTests: XCTestCase {
    func testRailwayScopeMatchesByIDsOrNames() {
        let existing = MonitoredTarget(
            projectID: "project_123",
            projectName: "pmf-agent",
            serviceID: "service_123",
            serviceName: "@pmf-agent/api",
            environmentID: "env_123",
            environmentName: "production"
        )

        let discoveredAgain = MonitoredTarget(
            projectID: "project_123",
            projectName: "pmf-agent",
            serviceID: "service_123",
            serviceName: "@pmf-agent/api",
            environmentID: "env_123",
            environmentName: "production"
        )

        let sameByName = MonitoredTarget(
            projectName: "PMF-Agent",
            serviceName: "@pmf-agent/api",
            environmentName: "Production"
        )

        XCTAssertTrue(existing.matchesScope(of: discoveredAgain, for: .railway))
        XCTAssertTrue(existing.matchesScope(of: sameByName, for: .railway))
    }

    func testRailwayScopeSeparatesDifferentEnvironment() {
        let production = MonitoredTarget(projectName: "pmf-agent", serviceName: "api", environmentName: "production")
        let staging = MonitoredTarget(projectName: "pmf-agent", serviceName: "api", environmentName: "staging")

        XCTAssertFalse(production.matchesScope(of: staging, for: .railway))
    }

    func testVercelScopeIncludesEnvironmentAndBranch() {
        let mainProduction = MonitoredTarget(projectName: "web", environmentName: "production", branch: "main")
        let allBranchesProduction = MonitoredTarget(projectName: "web", environmentName: "production")
        let sameByIDAndName = MonitoredTarget(projectID: "web", projectName: "web", environmentName: "Production", branch: "Main")

        XCTAssertFalse(mainProduction.matchesScope(of: allBranchesProduction, for: .vercel))
        XCTAssertTrue(mainProduction.matchesScope(of: sameByIDAndName, for: .vercel))
    }

    func testGenericProviderTargetBehavior() {
        let repository = MonitoredTarget(projectID: "acme/api", environmentName: "production")
        let sameRepository = MonitoredTarget(projectName: "ACME/API", environmentName: "Production")
        let emptyTarget = MonitoredTarget()

        XCTAssertTrue(repository.matchesScope(of: sameRepository, for: .github))
        XCTAssertTrue(repository.satisfiesRequiredFields(for: .github))
        XCTAssertFalse(emptyTarget.satisfiesRequiredFields(for: .github))
        XCTAssertEqual(MonitoredTarget(projectName: "docs").displayName(for: .netlify), "docs / All contexts / All branches")
    }

    func testDiscoveryTargetsCanBeDeduplicatedAndFiltered() {
        let existing = MonitoredTarget(projectID: "acme/api")
        let targets = [
            MonitoredTarget(projectName: "ACME/API"),
            MonitoredTarget(projectID: "acme/web"),
            MonitoredTarget(projectName: "acme/web")
        ]

        let availableTargets = targets.excludingTargets([existing], for: .github)

        XCTAssertEqual(availableTargets.count, 1)
        XCTAssertEqual(availableTargets.first?.projectID, "acme/web")
    }

    func testDisplayNamePrefersHumanNamesOverIDs() {
        let target = MonitoredTarget(
            projectID: "43db090d-4c41-4567-b424-9f0a9f026f0f",
            projectName: "deploybar",
            serviceID: "740e4f7b-0c94-4443-9d0c-9d5e6f287328",
            serviceName: "api",
            environmentID: "ba232523-f2d2-4216-823b-3f94d8e9f5ab",
            environmentName: "production"
        )

        XCTAssertEqual(target.displayName(for: .railway), "deploybar / api / production")
        XCTAssertTrue(target.satisfiesRequiredFields(for: .railway))
    }
}
