import DeployBarCore
import XCTest

final class DeploymentStatusMapperTests: XCTestCase {
    func testVercelStatusMapping() {
        XCTAssertEqual(DeploymentStatusMapper.vercelStatus("QUEUED"), .queued)
        XCTAssertEqual(DeploymentStatusMapper.vercelStatus("INITIALIZING"), .initializing)
        XCTAssertEqual(DeploymentStatusMapper.vercelStatus("BUILDING"), .building)
        XCTAssertEqual(DeploymentStatusMapper.vercelStatus("READY"), .ready)
        XCTAssertEqual(DeploymentStatusMapper.vercelStatus("ERROR"), .error)
        XCTAssertEqual(DeploymentStatusMapper.vercelStatus("CANCELED"), .canceled)
        XCTAssertEqual(DeploymentStatusMapper.vercelStatus("DELETED"), .unknown)
    }

    func testRailwayStatusMapping() {
        XCTAssertEqual(DeploymentStatusMapper.railwayStatus("QUEUED"), .queued)
        XCTAssertEqual(DeploymentStatusMapper.railwayStatus("WAITING"), .waiting)
        XCTAssertEqual(DeploymentStatusMapper.railwayStatus("BUILDING"), .building)
        XCTAssertEqual(DeploymentStatusMapper.railwayStatus("DEPLOYING"), .deploying)
        XCTAssertEqual(DeploymentStatusMapper.railwayStatus("SUCCESS"), .success)
        XCTAssertEqual(DeploymentStatusMapper.railwayStatus("FAILED"), .failed)
        XCTAssertEqual(DeploymentStatusMapper.railwayStatus("CRASHED"), .crashed)
        XCTAssertEqual(DeploymentStatusMapper.railwayStatus("REMOVED"), .removed)
        XCTAssertEqual(DeploymentStatusMapper.railwayStatus("SLEEPING"), .sleeping)
        XCTAssertEqual(DeploymentStatusMapper.railwayStatus("SKIPPED"), .skipped)
    }

    func testSeverityRules() {
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .failed), .critical)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .crashed), .critical)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .error), .critical)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .canceled), .healthy)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .removed), .warning)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .queued), .pending)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .waiting), .pending)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .initializing), .pending)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .building), .active)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .deploying), .active)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .success), .healthy)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .ready), .healthy)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .success, isStale: true, failureKind: .network), .warning)
        XCTAssertEqual(DeploymentStatusMapper.severity(for: .success, isStale: true, failureKind: .authentication), .critical)
    }

    func testAdditionalProviderStatusMappings() {
        XCTAssertEqual(DeploymentStatusMapper.netlifyStatus("ready"), .ready)
        XCTAssertEqual(DeploymentStatusMapper.netlifyStatus("building"), .building)
        XCTAssertEqual(DeploymentStatusMapper.netlifyStatus("error"), .failed)

        XCTAssertEqual(DeploymentStatusMapper.renderStatus("build_in_progress"), .building)
        XCTAssertEqual(DeploymentStatusMapper.renderStatus("update_in_progress"), .deploying)
        XCTAssertEqual(DeploymentStatusMapper.renderStatus("live"), .success)
        XCTAssertEqual(DeploymentStatusMapper.renderStatus("build_failed"), .failed)

        XCTAssertEqual(DeploymentStatusMapper.cloudflarePagesStatus("success"), .success)
        XCTAssertEqual(DeploymentStatusMapper.cloudflarePagesStatus("active"), .building)
        XCTAssertEqual(DeploymentStatusMapper.cloudflarePagesStatus("failure"), .failed)

        XCTAssertEqual(DeploymentStatusMapper.digitalOceanStatus("ACTIVE"), .success)
        XCTAssertEqual(DeploymentStatusMapper.digitalOceanStatus("BUILDING"), .building)
        XCTAssertEqual(DeploymentStatusMapper.digitalOceanStatus("ERROR"), .failed)

        XCTAssertEqual(DeploymentStatusMapper.herokuStatus("succeeded"), .success)
        XCTAssertEqual(DeploymentStatusMapper.herokuStatus("pending"), .deploying)
        XCTAssertEqual(DeploymentStatusMapper.herokuStatus("failed"), .failed)

        XCTAssertEqual(DeploymentStatusMapper.flyStatus("running"), .deploying)
        XCTAssertEqual(DeploymentStatusMapper.flyStatus("succeeded"), .success)
        XCTAssertEqual(DeploymentStatusMapper.flyStatus("failed"), .failed)
        XCTAssertEqual(DeploymentStatusMapper.flyStatus("replaced"), .removed)

        XCTAssertEqual(DeploymentStatusMapper.githubDeploymentStatus("in_progress"), .deploying)
        XCTAssertEqual(DeploymentStatusMapper.githubDeploymentStatus("success"), .success)
        XCTAssertEqual(DeploymentStatusMapper.githubDeploymentStatus("failure"), .failed)

        XCTAssertEqual(DeploymentStatusMapper.gitlabDeploymentStatus("running"), .deploying)
        XCTAssertEqual(DeploymentStatusMapper.gitlabDeploymentStatus("success"), .success)
        XCTAssertEqual(DeploymentStatusMapper.gitlabDeploymentStatus("failed"), .failed)
    }
}
