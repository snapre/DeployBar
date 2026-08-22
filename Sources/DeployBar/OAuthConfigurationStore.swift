import DeployBarCore
import Foundation

struct OAuthConfigurationStore {
    struct StoredConfiguration: Decodable {
        var clientID: String
        var clientSecret: String?
        var redirectURI: String?
    }

    static var configurationURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("DeployBar", isDirectory: true)
            .appendingPathComponent("oauth.json")
    }

    func configuration(for provider: ProviderID) -> ProviderOAuthClientConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        let key = environmentKey(for: provider)

        if let clientID = environment["DEPLOYBAR_OAUTH_\(key)_CLIENT_ID"]?.nilIfBlank {
            return ProviderOAuthClientConfiguration(
                clientID: clientID,
                clientSecret: environment["DEPLOYBAR_OAUTH_\(key)_CLIENT_SECRET"]?.nilIfBlank,
                redirectURI: environment["DEPLOYBAR_OAUTH_\(key)_REDIRECT_URI"]
                    .flatMap(URL.init(string:)) ?? ProviderOAuthAuthorizationBuilder.defaultRedirectURI(for: provider)
            )
        }

        guard let stored = storedConfigurations()[provider.rawValue], let clientID = stored.clientID.nilIfBlank else {
            return nil
        }

        return ProviderOAuthClientConfiguration(
            clientID: clientID,
            clientSecret: stored.clientSecret?.nilIfBlank,
            redirectURI: stored.redirectURI.flatMap(URL.init(string:)) ?? ProviderOAuthAuthorizationBuilder.defaultRedirectURI(for: provider)
        )
    }

    func setupMessage(for provider: ProviderID) -> String {
        let redirectURI = ProviderOAuthAuthorizationBuilder.defaultRedirectURI(for: provider).absoluteString
        return "OAuth client is not configured. Register \(provider.displayName) with callback \(redirectURI), then add its client ID to \(Self.configurationURL.path)."
    }

    private func storedConfigurations() -> [String: StoredConfiguration] {
        guard let data = try? Data(contentsOf: Self.configurationURL) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: StoredConfiguration].self, from: data)) ?? [:]
    }

    private func environmentKey(for provider: ProviderID) -> String {
        switch provider {
        case .digitalOcean:
            return "DIGITALOCEAN"
        case .cloudflarePages:
            return "CLOUDFLAREPAGES"
        case .cloudflareWorkers:
            return "CLOUDFLAREWORKERS"
        default:
            return provider.rawValue.uppercased()
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
