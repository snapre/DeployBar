import DeployBarCore
import XCTest

final class ProviderTokenLinksTests: XCTestCase {
    func testRailwayTokenLinkFollowsTokenKind() {
        let accountLink = ProviderID.railway.tokenLink(railwayTokenKind: .accountOrWorkspace)
        let projectLink = ProviderID.railway.tokenLink(railwayTokenKind: .project)

        XCTAssertEqual(accountLink?.url.absoluteString, "https://railway.com/account/tokens")
        XCTAssertEqual(projectLink?.url.absoluteString, "https://railway.com/dashboard")
    }

    func testGitLabTokenLinkUsesCustomAPIBaseURL() {
        let link = ProviderID.gitlab.tokenLink(gitLabAPIBaseURL: "https://gitlab.example.com/api/v4")
        let components = URLComponents(url: link!.url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components?.scheme, "https")
        XCTAssertEqual(components?.host, "gitlab.example.com")
        XCTAssertEqual(components?.path, "/-/user_settings/personal_access_tokens")
        XCTAssertEqual(query["name"], "DeployBar")
        XCTAssertEqual(query["description"], "Read deployment status for DeployBar")
        XCTAssertEqual(query["scopes"], "read_api")
    }

    func testGitHubTokenLinkPrefillsDeploymentsReadPermission() throws {
        let link = try XCTUnwrap(ProviderID.github.tokenLink())
        let components = try XCTUnwrap(URLComponents(url: link.url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(link.title, "Create Read Token")
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/settings/personal-access-tokens/new")
        XCTAssertEqual(query["name"], "DeployBar")
        XCTAssertEqual(query["description"], "Read deployment status for DeployBar")
        XCTAssertEqual(query["expires_in"], "90")
        XCTAssertEqual(query["deployments"], "read")
    }

    func testCloudflarePagesTokenLinkPrefillsPagesAndMembershipsReadPermissions() throws {
        let link = try XCTUnwrap(ProviderID.cloudflarePages.tokenLink())
        let components = try XCTUnwrap(URLComponents(url: link.url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(link.title, "Create Pages Token")
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "dash.cloudflare.com")
        XCTAssertEqual(components.path, "/profile/api-tokens")
        XCTAssertEqual(query["permissionGroupKeys"], #"[{"key":"page","type":"read"},{"key":"memberships","type":"read"}]"#)
        XCTAssertEqual(query["accountId"], "*")
        XCTAssertEqual(query["zoneId"], "all")
        XCTAssertEqual(query["name"], "DeployBar Pages Read")
    }

    func testProviderTokenLinksCoverTokenProviders() {
        let providers: [ProviderID] = [
            .vercel,
            .railway,
            .netlify,
            .render,
            .cloudflarePages,
            .digitalOcean,
            .heroku,
            .github,
            .gitlab
        ]

        XCTAssertTrue(providers.allSatisfy { $0.tokenLink() != nil })
        XCTAssertNil(ProviderID.mock.tokenLink())
    }
}
