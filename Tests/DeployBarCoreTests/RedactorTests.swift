import DeployBarCore
import XCTest

final class RedactorTests: XCTestCase {
    func testRedactsConfiguredSecrets() {
        let redactor = Redactor(secrets: ["vercel_token_123", "railway_token_456"])
        let output = redactor.redact("Authorization: Bearer vercel_token_123 and railway_token_456")

        XCTAssertFalse(output.contains("vercel_token_123"))
        XCTAssertFalse(output.contains("railway_token_456"))
        XCTAssertEqual(output, "Authorization: Bearer <redacted> and <redacted>")
    }
}
