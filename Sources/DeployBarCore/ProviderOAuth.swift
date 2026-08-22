import CryptoKit
import Foundation
import Security

public enum ProviderOAuthResponseType: String, Equatable, Sendable {
    case code
    case token
}

public enum ProviderOAuthTokenAuthMethod: Equatable, Sendable {
    case none
    case body
}

public struct ProviderOAuthDescriptor: Equatable, Sendable {
    public var provider: ProviderID
    public var authorizationEndpoint: URL
    public var tokenEndpoint: URL?
    public var scopes: [String]
    public var responseType: ProviderOAuthResponseType
    public var usesPKCE: Bool
    public var prompt: String?
    public var tokenAuthMethod: ProviderOAuthTokenAuthMethod
    public var storesAsBearerToken: Bool

    public init(
        provider: ProviderID,
        authorizationEndpoint: URL,
        tokenEndpoint: URL? = nil,
        scopes: [String],
        responseType: ProviderOAuthResponseType,
        usesPKCE: Bool = false,
        prompt: String? = nil,
        tokenAuthMethod: ProviderOAuthTokenAuthMethod = .body,
        storesAsBearerToken: Bool = true
    ) {
        self.provider = provider
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.scopes = scopes
        self.responseType = responseType
        self.usesPKCE = usesPKCE
        self.prompt = prompt
        self.tokenAuthMethod = tokenAuthMethod
        self.storesAsBearerToken = storesAsBearerToken
    }
}

public struct ProviderOAuthClientConfiguration: Equatable, Sendable {
    public var clientID: String
    public var clientSecret: String?
    public var redirectURI: URL

    public init(clientID: String, clientSecret: String? = nil, redirectURI: URL) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
    }
}

public struct ProviderOAuthAuthorizationRequest: Equatable, Sendable {
    public var url: URL
    public var state: String
    public var codeVerifier: String?
    public var redirectURI: URL
    public var descriptor: ProviderOAuthDescriptor
    public var client: ProviderOAuthClientConfiguration
}

public enum ProviderOAuthError: Error, Equatable, Sendable {
    case unsupportedProvider
    case invalidAuthorizationURL
    case invalidCallback
    case stateMismatch
    case missingAuthorizationCode
    case missingAccessToken
}

public extension ProviderID {
    func oauthDescriptor(gitLabAPIBaseURL: String? = nil) -> ProviderOAuthDescriptor? {
        switch self {
        case .vercel:
            return ProviderOAuthDescriptor(
                provider: self,
                authorizationEndpoint: URL(string: "https://vercel.com/oauth/authorize")!,
                tokenEndpoint: URL(string: "https://api.vercel.com/login/oauth/token"),
                scopes: ["openid", "email", "profile", "offline_access"],
                responseType: .code,
                usesPKCE: true
            )
        case .railway:
            return ProviderOAuthDescriptor(
                provider: self,
                authorizationEndpoint: URL(string: "https://backboard.railway.com/oauth/auth")!,
                tokenEndpoint: URL(string: "https://backboard.railway.com/oauth/token"),
                scopes: ["openid", "email", "profile", "offline_access", "project:viewer"],
                responseType: .code,
                usesPKCE: true,
                prompt: "consent"
            )
        case .netlify:
            return ProviderOAuthDescriptor(
                provider: self,
                authorizationEndpoint: URL(string: "https://app.netlify.com/authorize")!,
                scopes: [],
                responseType: .token,
                tokenAuthMethod: .none
            )
        case .digitalOcean:
            return ProviderOAuthDescriptor(
                provider: self,
                authorizationEndpoint: URL(string: "https://cloud.digitalocean.com/v1/oauth/authorize")!,
                scopes: ["app:read"],
                responseType: .token,
                prompt: "select_account",
                tokenAuthMethod: .none
            )
        case .heroku:
            return ProviderOAuthDescriptor(
                provider: self,
                authorizationEndpoint: URL(string: "https://id.heroku.com/oauth/authorize")!,
                tokenEndpoint: URL(string: "https://id.heroku.com/oauth/token"),
                scopes: ["read"],
                responseType: .code
            )
        case .gitlab:
            let webBaseURL = Self.gitLabWebBaseURL(from: gitLabAPIBaseURL)
            return ProviderOAuthDescriptor(
                provider: self,
                authorizationEndpoint: webBaseURL.appendingPathComponent("oauth").appendingPathComponent("authorize"),
                tokenEndpoint: webBaseURL.appendingPathComponent("oauth").appendingPathComponent("token"),
                scopes: ["read_api"],
                responseType: .code,
                usesPKCE: true
            )
        case .github:
            return ProviderOAuthDescriptor(
                provider: self,
                authorizationEndpoint: URL(string: "https://github.com/login/oauth/authorize")!,
                tokenEndpoint: URL(string: "https://github.com/login/oauth/access_token"),
                scopes: ["repo_deployment"],
                responseType: .code
            )
        case .mock, .render, .cloudflarePages, .cloudflareWorkers, .flyio:
            return nil
        }
    }

    private static func gitLabWebBaseURL(from rawBaseURL: String?) -> URL {
        let baseURL = URL(string: "https://gitlab.com")!
        guard let rawBaseURL = rawBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawBaseURL.isEmpty else {
            return baseURL
        }
        let normalized = rawBaseURL.hasPrefix("http://") || rawBaseURL.hasPrefix("https://")
            ? rawBaseURL
            : "https://\(rawBaseURL)"
        guard var components = URLComponents(string: normalized) else {
            return baseURL
        }
        components.path = components.path
            .replacingOccurrences(of: "/api/v4", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.isEmpty {
            components.path = "/\(components.path)"
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? baseURL
    }
}

public enum ProviderOAuthAuthorizationBuilder {
    public static let callbackScheme = "deploybar"

    public static func defaultRedirectURI(for provider: ProviderID) -> URL {
        URL(string: "\(callbackScheme)://oauth/\(provider.rawValue)")!
    }

    public static func makeRequest(
        descriptor: ProviderOAuthDescriptor,
        client: ProviderOAuthClientConfiguration,
        state: String = randomURLSafeString(byteCount: 24),
        codeVerifier: String? = nil
    ) throws -> ProviderOAuthAuthorizationRequest {
        guard var components = URLComponents(url: descriptor.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw ProviderOAuthError.invalidAuthorizationURL
        }

        let verifier = descriptor.usesPKCE ? (codeVerifier ?? randomURLSafeString(byteCount: 32)) : nil
        var queryItems = [
            URLQueryItem(name: "response_type", value: descriptor.responseType.rawValue),
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "redirect_uri", value: client.redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state)
        ]
        if !descriptor.scopes.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: descriptor.scopes.joined(separator: " ")))
        }
        if let prompt = descriptor.prompt {
            queryItems.append(URLQueryItem(name: "prompt", value: prompt))
        }
        if let verifier {
            queryItems.append(URLQueryItem(name: "code_challenge", value: codeChallenge(for: verifier)))
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ProviderOAuthError.invalidAuthorizationURL
        }

        return ProviderOAuthAuthorizationRequest(
            url: url,
            state: state,
            codeVerifier: verifier,
            redirectURI: client.redirectURI,
            descriptor: descriptor,
            client: client
        )
    }

    public static func code(from callbackURL: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard values["error"] == nil else {
            throw ProviderOAuthError.invalidCallback
        }
        guard values["state"] == expectedState else {
            throw ProviderOAuthError.stateMismatch
        }
        guard let code = values["code"], !code.isEmpty else {
            throw ProviderOAuthError.missingAuthorizationCode
        }
        return code
    }

    public static func accessToken(from callbackURL: URL, expectedState: String) throws -> String {
        var items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let fragment = callbackURL.fragment,
           let fragmentItems = URLComponents(string: "?\(fragment)")?.queryItems {
            items.append(contentsOf: fragmentItems)
        }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard values["error"] == nil else {
            throw ProviderOAuthError.invalidCallback
        }
        guard values["state"] == expectedState else {
            throw ProviderOAuthError.stateMismatch
        }
        guard let accessToken = values["access_token"], !accessToken.isEmpty else {
            throw ProviderOAuthError.missingAccessToken
        }
        return accessToken
    }

    public static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    public static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
