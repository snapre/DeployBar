import Foundation

public struct ProviderTokenLink: Equatable, Sendable {
    public var title: String
    public var url: URL
    public var help: String

    public init(title: String, url: URL, help: String) {
        self.title = title
        self.url = url
        self.help = help
    }
}

public extension ProviderID {
    func tokenLink(
        railwayTokenKind: RailwayTokenKind? = nil,
        gitLabAPIBaseURL: String? = nil
    ) -> ProviderTokenLink? {
        switch self {
        case .mock:
            return nil
        case .vercel:
            return tokenLink(
                title: "Get Token",
                url: "https://vercel.com/account/settings/tokens",
                help: "Open Vercel account tokens."
            )
        case .railway:
            if railwayTokenKind == .accountOrWorkspace {
                return tokenLink(
                    title: "Get Token",
                    url: "https://railway.com/account/tokens",
                    help: "Open Railway account and workspace tokens."
                )
            }
            return tokenLink(
                title: "Get Token",
                url: "https://railway.com/dashboard",
                help: "Open Railway dashboard. Project tokens are under the selected project's settings tokens page."
            )
        case .netlify:
            return tokenLink(
                title: "Get Token",
                url: "https://app.netlify.com/user/applications#personal-access-tokens",
                help: "Open Netlify personal access tokens."
            )
        case .render:
            return tokenLink(
                title: "Get Token",
                url: "https://dashboard.render.com/u/settings?add-api-key=",
                help: "Open Render account settings and create an API key."
            )
        case .cloudflarePages:
            return tokenLink(
                title: "Create Pages Token",
                url: cloudflarePagesTokenURL(),
                help: "Open Cloudflare with Pages Read and Memberships Read already selected."
            )
        case .digitalOcean:
            return tokenLink(
                title: "Get Token",
                url: "https://cloud.digitalocean.com/account/api/tokens",
                help: "Open DigitalOcean personal access tokens."
            )
        case .heroku:
            return tokenLink(
                title: "Get Token",
                url: "https://dashboard.heroku.com/account",
                help: "Open Heroku account settings. The API key is listed there for non-SSO accounts."
            )
        case .flyio:
            return tokenLink(
                title: "Create Token",
                url: "https://fly.io/docs/security/tokens/",
                help: "Create a Fly.io `FlyV1` token with `fly tokens create readonly` for discovery, or another app/org token for the apps you want to watch."
            )
        case .github:
            return tokenLink(
                title: "Create Read Token",
                url: githubTokenURL(),
                help: "Open GitHub with Deployments read access preselected."
            )
        case .gitlab:
            return tokenLink(
                title: "Create Read Token",
                url: gitLabTokenURL(baseURL: gitLabAPIBaseURL),
                help: "Open GitLab with read_api preselected."
            )
        }
    }

    private func tokenLink(title: String, url: String, help: String) -> ProviderTokenLink? {
        guard let url = URL(string: url) else { return nil }
        return ProviderTokenLink(title: title, url: url, help: help)
    }

    private func tokenLink(title: String, url: URL?, help: String) -> ProviderTokenLink? {
        guard let url else { return nil }
        return ProviderTokenLink(title: title, url: url, help: help)
    }

    private func cloudflarePagesTokenURL() -> URL? {
        var components = URLComponents(string: "https://dash.cloudflare.com/profile/api-tokens")
        components?.queryItems = [
            URLQueryItem(name: "permissionGroupKeys", value: #" [{"key":"page","type":"read"},{"key":"memberships","type":"read"}] "#.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "accountId", value: "*"),
            URLQueryItem(name: "zoneId", value: "all"),
            URLQueryItem(name: "name", value: "DeployBar Pages Read")
        ]
        return components?.url
    }

    private func githubTokenURL() -> URL? {
        var components = URLComponents(string: "https://github.com/settings/personal-access-tokens/new")
        components?.queryItems = [
            URLQueryItem(name: "name", value: "DeployBar"),
            URLQueryItem(name: "description", value: "Read deployment status for DeployBar"),
            URLQueryItem(name: "expires_in", value: "90"),
            URLQueryItem(name: "deployments", value: "read")
        ]
        return components?.url
    }

    private func gitLabTokenURL(baseURL rawBaseURL: String?) -> URL? {
        var baseURL = URL(string: "https://gitlab.com")!

        if let rawBaseURL = rawBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawBaseURL.isEmpty {
            let normalized = rawBaseURL.hasPrefix("http://") || rawBaseURL.hasPrefix("https://")
                ? rawBaseURL
                : "https://\(rawBaseURL)"
            if var components = URLComponents(string: normalized) {
                components.path = components.path
                    .replacingOccurrences(of: "/api/v4", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !components.path.isEmpty {
                    components.path = "/\(components.path)"
                }
                components.query = nil
                components.fragment = nil
                if let url = components.url {
                    baseURL = url
                }
            }
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "\(basePath.isEmpty ? "" : "/\(basePath)")/-/user_settings/personal_access_tokens"
        components.queryItems = [
            URLQueryItem(name: "name", value: "DeployBar"),
            URLQueryItem(name: "description", value: "Read deployment status for DeployBar"),
            URLQueryItem(name: "scopes", value: "read_api")
        ]
        return components.url
    }
}
