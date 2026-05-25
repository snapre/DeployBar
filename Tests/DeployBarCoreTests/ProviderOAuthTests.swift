import DeployBarCore
import XCTest

final class ProviderOAuthTests: XCTestCase {
    func testVercelOAuthRequestUsesCodeFlowWithPKCE() throws {
        let descriptor = try XCTUnwrap(ProviderID.vercel.oauthDescriptor())
        let request = try ProviderOAuthAuthorizationBuilder.makeRequest(
            descriptor: descriptor,
            client: ProviderOAuthClientConfiguration(
                clientID: "vercel_client",
                redirectURI: ProviderOAuthAuthorizationBuilder.defaultRedirectURI(for: .vercel)
            ),
            state: "state123",
            codeVerifier: "verifier123"
        )
        let components = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.host, "vercel.com")
        XCTAssertEqual(components.path, "/oauth/authorize")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["client_id"], "vercel_client")
        XCTAssertEqual(query["redirect_uri"], "deploybar://oauth/vercel")
        XCTAssertEqual(query["scope"], "openid email profile offline_access")
        XCTAssertEqual(query["state"], "state123")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["code_challenge"], ProviderOAuthAuthorizationBuilder.codeChallenge(for: "verifier123"))
        XCTAssertEqual(request.codeVerifier, "verifier123")
    }

    func testDigitalOceanOAuthRequestUsesImplicitTokenFlow() throws {
        let descriptor = try XCTUnwrap(ProviderID.digitalOcean.oauthDescriptor())
        let request = try ProviderOAuthAuthorizationBuilder.makeRequest(
            descriptor: descriptor,
            client: ProviderOAuthClientConfiguration(
                clientID: "do_client",
                redirectURI: ProviderOAuthAuthorizationBuilder.defaultRedirectURI(for: .digitalOcean)
            ),
            state: "state123"
        )
        let components = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.host, "cloud.digitalocean.com")
        XCTAssertEqual(components.path, "/v1/oauth/authorize")
        XCTAssertEqual(query["response_type"], "token")
        XCTAssertEqual(query["client_id"], "do_client")
        XCTAssertEqual(query["scope"], "app:read")
        XCTAssertEqual(query["prompt"], "select_account")
        XCTAssertNil(query["code_challenge"])
    }

    func testOAuthCallbackParsesCodeAndTokenWithStateValidation() throws {
        let codeURL = URL(string: "deploybar://oauth/vercel?code=abc&state=state123")!
        let tokenURL = URL(string: "deploybar://oauth/netlify#access_token=secret&state=state123&token_type=bearer")!

        XCTAssertEqual(try ProviderOAuthAuthorizationBuilder.code(from: codeURL, expectedState: "state123"), "abc")
        XCTAssertEqual(try ProviderOAuthAuthorizationBuilder.accessToken(from: tokenURL, expectedState: "state123"), "secret")
        XCTAssertThrowsError(try ProviderOAuthAuthorizationBuilder.code(from: codeURL, expectedState: "wrong"))
    }

    func testGitLabOAuthDescriptorUsesCustomWebBaseURL() throws {
        let descriptor = try XCTUnwrap(ProviderID.gitlab.oauthDescriptor(gitLabAPIBaseURL: "https://gitlab.example.com/api/v4"))

        XCTAssertEqual(descriptor.authorizationEndpoint.absoluteString, "https://gitlab.example.com/oauth/authorize")
        XCTAssertEqual(descriptor.tokenEndpoint?.absoluteString, "https://gitlab.example.com/oauth/token")
        XCTAssertEqual(descriptor.scopes, ["read_api"])
        XCTAssertTrue(descriptor.usesPKCE)
    }

    func testGitHubOAuthDescriptorUsesDeploymentScope() throws {
        let descriptor = try XCTUnwrap(ProviderID.github.oauthDescriptor())

        XCTAssertEqual(descriptor.authorizationEndpoint.absoluteString, "https://github.com/login/oauth/authorize")
        XCTAssertEqual(descriptor.tokenEndpoint?.absoluteString, "https://github.com/login/oauth/access_token")
        XCTAssertEqual(descriptor.scopes, ["repo_deployment"])
        XCTAssertEqual(descriptor.responseType, .code)
    }
}
