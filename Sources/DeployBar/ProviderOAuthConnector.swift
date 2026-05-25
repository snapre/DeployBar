import AppKit
import AuthenticationServices
import DeployBarCore
import Foundation

struct ProviderOAuthToken: Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: TimeInterval?
}

enum ProviderOAuthConnectorError: Error, LocalizedError {
    case missingConfiguration(String)
    case unsupportedProvider
    case missingTokenEndpoint
    case tokenExchangeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let message):
            return message
        case .unsupportedProvider:
            return "OAuth is not supported for this provider yet."
        case .missingTokenEndpoint:
            return "OAuth token endpoint is not configured for this provider."
        case .tokenExchangeFailed(let message):
            return message
        case .cancelled:
            return "OAuth authorization was cancelled."
        }
    }
}

@MainActor
final class ProviderOAuthConnector: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private let configurationStore = OAuthConfigurationStore()

    func authorize(provider: ProviderID, gitLabAPIBaseURL: String?) async throws -> ProviderOAuthToken {
        guard let descriptor = provider.oauthDescriptor(gitLabAPIBaseURL: gitLabAPIBaseURL) else {
            throw ProviderOAuthConnectorError.unsupportedProvider
        }
        guard let configuration = configurationStore.configuration(for: provider) else {
            throw ProviderOAuthConnectorError.missingConfiguration(configurationStore.setupMessage(for: provider))
        }

        let request = try ProviderOAuthAuthorizationBuilder.makeRequest(
            descriptor: descriptor,
            client: configuration
        )
        let callbackURL = try await authenticate(with: request.url)

        switch descriptor.responseType {
        case .token:
            let token = try ProviderOAuthAuthorizationBuilder.accessToken(from: callbackURL, expectedState: request.state)
            return ProviderOAuthToken(accessToken: token, refreshToken: nil, expiresIn: nil)
        case .code:
            let code = try ProviderOAuthAuthorizationBuilder.code(from: callbackURL, expectedState: request.state)
            return try await exchangeCode(code, request: request)
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }

    private func authenticate(with url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: ProviderOAuthAuthorizationBuilder.callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: ProviderOAuthConnectorError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: ProviderOAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: ProviderOAuthConnectorError.cancelled)
            }
        }
    }

    private func exchangeCode(_ code: String, request: ProviderOAuthAuthorizationRequest) async throws -> ProviderOAuthToken {
        guard let tokenEndpoint = request.descriptor.tokenEndpoint else {
            throw ProviderOAuthConnectorError.missingTokenEndpoint
        }

        var bodyItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: request.redirectURI.absoluteString),
            URLQueryItem(name: "client_id", value: request.client.clientID)
        ]
        if let codeVerifier = request.codeVerifier {
            bodyItems.append(URLQueryItem(name: "code_verifier", value: codeVerifier))
        }
        if request.descriptor.tokenAuthMethod == .body, let clientSecret = request.client.clientSecret {
            bodyItems.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }

        var components = URLComponents()
        components.queryItems = bodyItems

        var tokenRequest = URLRequest(url: tokenEndpoint)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        tokenRequest.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: tokenRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw ProviderOAuthConnectorError.tokenExchangeFailed(errorMessage(from: data) ?? "OAuth token exchange failed with HTTP \(statusCode).")
        }

        let token = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        guard let accessToken = token.accessToken.nilIfBlank else {
            throw ProviderOAuthError.missingAccessToken
        }
        return ProviderOAuthToken(
            accessToken: accessToken,
            refreshToken: token.refreshToken?.nilIfBlank,
            expiresIn: token.expiresIn.map(TimeInterval.init)
        )
    }

    private func errorMessage(from data: Data) -> String? {
        if let response = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            return response.errorDescription ?? response.error
        }
        return String(data: data, encoding: .utf8)?.nilIfBlank
    }
}

private struct OAuthTokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct OAuthErrorResponse: Decodable {
    var error: String?
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
