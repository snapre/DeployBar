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
}
