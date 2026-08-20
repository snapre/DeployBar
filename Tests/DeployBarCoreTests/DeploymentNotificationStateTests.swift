import DeployBarCore
import XCTest

final class DeploymentNotificationStateTests: XCTestCase {
    func testInitialRefreshOnlyEstablishesBaseline() {
        let current = makeSnapshot(id: "dep_success", projectName: "Avatar Signal", status: .success, createdAt: 200)

        let candidates = DeploymentNotificationState().candidates(from: [current])

        XCTAssertTrue(candidates.isEmpty)
    }

    func testOnlyNewestDeploymentForKnownScopeBecomesCandidate() {
        let previous = makeSnapshot(id: "dep_building", projectName: "Avatar Signal", status: .building, createdAt: 100)
        let olderFailure = makeSnapshot(id: "dep_failed", projectName: "Avatar Signal", status: .failed, createdAt: 150)
        let newerSuccess = makeSnapshot(id: "dep_success", projectName: "Avatar Signal", status: .success, createdAt: 200)
        let state = DeploymentNotificationState(snapshots: [previous])

        let candidates = state.candidates(from: [olderFailure, newerSuccess])

        XCTAssertEqual(candidates.map(\.id), ["railway:account:dep_success"])
        XCTAssertEqual(state.statusesByID, ["railway:account:dep_building": .building])
    }

    func testNewScopeOnlyEstablishesBaselineWhileKnownScopeStillNotifies() {
        let knownPrevious = makeSnapshot(id: "dep_known_building", projectName: "Known", status: .building, createdAt: 100)
        let knownCurrent = makeSnapshot(id: "dep_known_success", projectName: "Known", status: .success, createdAt: 200)
        let newScopeHistory = makeSnapshot(id: "dep_new_failed", projectName: "New", status: .failed, createdAt: 50)
        let state = DeploymentNotificationState(snapshots: [knownPrevious])

        let candidates = state.candidates(from: [knownCurrent, newScopeHistory])

        XCTAssertEqual(candidates.map(\.id), ["railway:account:dep_known_success"])
    }

    func testStatusChangeForSameDeploymentRemainsCandidate() {
        let previous = makeSnapshot(id: "dep_1", projectName: "Avatar Signal", status: .building, createdAt: 100)
        let current = makeSnapshot(id: "dep_1", projectName: "Avatar Signal", status: .failed, createdAt: 100)
        let state = DeploymentNotificationState(snapshots: [previous])

        let candidates = state.candidates(from: [current])

        XCTAssertEqual(candidates.map(\.id), ["railway:account:dep_1"])
        XCTAssertEqual(state.statusesByID[current.id], .building)
    }

    private func makeSnapshot(
        id: String,
        projectName: String,
        status: DeploymentStatus,
        createdAt: TimeInterval
    ) -> DeploymentSnapshot {
        DeploymentSnapshot(
            id: "railway:account:\(id)",
            provider: .railway,
            projectName: projectName,
            serviceName: "avatarsignal",
            environmentName: "production",
            branch: "main",
            status: status,
            createdAt: Date(timeIntervalSince1970: createdAt),
            lastUpdatedAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}
