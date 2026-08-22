import XCTest
@testable import DeployBarCore

final class DeployBarSettingsTests: XCTestCase {
    func testAddingRealProviderAccountDisablesMockProvider() {
        let account = ProviderAccount(
            provider: .github,
            displayName: "GitHub",
            tokenReference: "token"
        )
        var settings = DeployBarSettings(showMockProvider: true)

        settings.addAccount(account)

        XCTAssertEqual(settings.accounts, [account])
        XCTAssertFalse(settings.showMockProvider)
    }

    func testAddingMockAccountDoesNotDisableMockProvider() {
        let account = ProviderAccount(
            provider: .mock,
            displayName: "Mock",
            tokenReference: "mock"
        )
        var settings = DeployBarSettings(showMockProvider: true)

        settings.addAccount(account)

        XCTAssertTrue(settings.showMockProvider)
    }

    func testMockProviderCanBeEnabledAgainAfterConnectingAccount() {
        let account = ProviderAccount(
            provider: .github,
            displayName: "GitHub",
            tokenReference: "token"
        )
        var settings = DeployBarSettings(showMockProvider: true)

        settings.addAccount(account)
        settings.showMockProvider = true

        XCTAssertTrue(settings.showMockProvider)
    }
}
