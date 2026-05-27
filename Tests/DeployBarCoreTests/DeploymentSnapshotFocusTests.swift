import DeployBarCore
import XCTest

final class DeploymentSnapshotFocusTests: XCTestCase {
    func testRailwayFocusUsesNewestDeploymentForSameTarget() {
        let olderFailure = DeploymentSnapshot(
            id: "railway:account:dep_failed",
            provider: .railway,
            projectName: "pmf-agent",
            serviceName: "@pmf-agent/api",
            environmentName: "production",
            status: .failed,
            createdAt: Date(timeIntervalSince1970: 100),
            lastUpdatedAt: Date(timeIntervalSince1970: 200)
        )
        let newerSuccess = DeploymentSnapshot(
            id: "railway:account:dep_success",
            provider: .railway,
            projectName: "pmf-agent",
            serviceName: "@pmf-agent/api",
            environmentName: "production",
            status: .success,
            createdAt: Date(timeIntervalSince1970: 300),
            lastUpdatedAt: Date(timeIntervalSince1970: 400)
        )

        let focused = DeploymentSnapshotFocus.focused([olderFailure, newerSuccess])

        XCTAssertEqual(focused.count, 1)
        XCTAssertEqual(focused[0].id, "railway:account:dep_success")
        XCTAssertEqual(focused[0].severity, .healthy)
    }

    func testRailwayFocusKeepsDifferentTargetsSeparate() {
        let pmfAgent = DeploymentSnapshot(
            id: "railway:account:dep_pmf",
            provider: .railway,
            projectName: "pmf-agent",
            serviceName: "@pmf-agent/api",
            environmentName: "production",
            status: .success,
            createdAt: Date(timeIntervalSince1970: 100),
            lastUpdatedAt: Date(timeIntervalSince1970: 100)
        )
        let srome = DeploymentSnapshot(
            id: "railway:account:dep_srome",
            provider: .railway,
            projectName: "srome",
            serviceName: "@srome/api",
            environmentName: "production",
            status: .success,
            createdAt: Date(timeIntervalSince1970: 200),
            lastUpdatedAt: Date(timeIntervalSince1970: 200)
        )

        let focused = DeploymentSnapshotFocus.focused([pmfAgent, srome])

        XCTAssertEqual(focused.map(\.projectName).sorted(), ["pmf-agent", "srome"])
    }
}
