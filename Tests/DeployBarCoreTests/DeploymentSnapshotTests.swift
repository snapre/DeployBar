import XCTest
@testable import DeployBarCore

final class DeploymentSnapshotTests: XCTestCase {
    func testProjectAndServiceDisplayNameIncludesDistinctService() {
        let snapshot = makeSnapshot(projectName: "Srome", serviceName: "api")

        XCTAssertEqual(snapshot.projectAndServiceDisplayName, "Srome · api")
    }

    func testProjectAndServiceDisplayNameOmitsMissingEmptyOrDuplicateService() {
        XCTAssertEqual(
            makeSnapshot(projectName: "Srome", serviceName: nil).projectAndServiceDisplayName,
            "Srome"
        )
        XCTAssertEqual(
            makeSnapshot(projectName: "Srome", serviceName: "  ").projectAndServiceDisplayName,
            "Srome"
        )
        XCTAssertEqual(
            makeSnapshot(projectName: "Srome", serviceName: "sRoMe").projectAndServiceDisplayName,
            "Srome"
        )
    }

    private func makeSnapshot(projectName: String, serviceName: String?) -> DeploymentSnapshot {
        DeploymentSnapshot(
            id: "deployment",
            provider: .railway,
            projectName: projectName,
            serviceName: serviceName,
            status: .success
        )
    }
}
