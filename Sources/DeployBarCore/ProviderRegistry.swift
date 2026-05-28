import Foundation

public struct ProviderRegistry: Sendable {
    private let providers: [ProviderID: any DeploymentProvider]
    private let descriptors: [ProviderID: ProviderDescriptor]

    public init(providers: [any DeploymentProvider], descriptors: [ProviderDescriptor] = Self.defaultDescriptors) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.descriptors = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
    }

    public subscript(id: ProviderID) -> (any DeploymentProvider)? {
        providers[id]
    }

    public var allProviders: [any DeploymentProvider] {
        Self.providerOrder.compactMap { providers[$0] }
    }

    public var allDescriptors: [ProviderDescriptor] {
        Self.providerOrder.compactMap { descriptors[$0] }
    }

    public func descriptor(for id: ProviderID) -> ProviderDescriptor? {
        descriptors[id]
    }

    public static let defaultDescriptors: [ProviderDescriptor] = [
        ProviderDescriptor(
            id: .mock,
            displayName: "Mock",
            defaultEnabled: true,
            requiresToken: false,
            supportsTeamScope: false,
            supportsMonitoredTargets: false,
            requiresMonitoredTargets: false
        ),
        ProviderDescriptor(
            id: .vercel,
            displayName: "Vercel",
            defaultEnabled: false,
            requiresToken: true,
            supportsTeamScope: true,
            supportsMonitoredTargets: true,
            requiresMonitoredTargets: false,
            dashboardURL: URL(string: "https://vercel.com/dashboard")
        ),
        ProviderDescriptor(
            id: .railway,
            displayName: "Railway",
            defaultEnabled: false,
            requiresToken: true,
            supportsTeamScope: false,
            supportsMonitoredTargets: true,
            requiresMonitoredTargets: true,
            dashboardURL: URL(string: "https://railway.com/dashboard")
        ),
        ProviderDescriptor(
            id: .netlify,
            displayName: "Netlify",
            defaultEnabled: false,
            requiresToken: true,
            supportsTeamScope: false,
            supportsMonitoredTargets: true,
            requiresMonitoredTargets: false,
            dashboardURL: URL(string: "https://app.netlify.com")
        ),
        ProviderDescriptor(
            id: .render,
            displayName: "Render",
            defaultEnabled: false,
            requiresToken: true,
            supportsTeamScope: false,
            supportsMonitoredTargets: true,
            requiresMonitoredTargets: false,
            dashboardURL: URL(string: "https://dashboard.render.com")
        ),
        ProviderDescriptor(
            id: .cloudflarePages,
            displayName: "Cloudflare Pages",
            defaultEnabled: false,
            requiresToken: true,
            supportsTeamScope: true,
            supportsMonitoredTargets: true,
            requiresMonitoredTargets: false,
            dashboardURL: URL(string: "https://dash.cloudflare.com")
        ),
        ProviderDescriptor(
            id: .digitalOcean,
            displayName: "DigitalOcean",
            defaultEnabled: false,
            requiresToken: true,
            supportsTeamScope: false,
            supportsMonitoredTargets: true,
            requiresMonitoredTargets: false,
            dashboardURL: URL(string: "https://cloud.digitalocean.com/apps")
        ),
        ProviderDescriptor(
            id: .heroku,
            displayName: "Heroku",
            defaultEnabled: false,
            requiresToken: true,
            supportsTeamScope: false,
            supportsMonitoredTargets: true,
            requiresMonitoredTargets: false,
            dashboardURL: URL(string: "https://dashboard.heroku.com/apps")
        ),
        ProviderDescriptor(
            id: .flyio,
            displayName: "Fly.io",
            defaultEnabled: false,
            requiresToken: true,
            supportsTeamScope: false,
            supportsMonitoredTargets: true,
            requiresMonitoredTargets: false,
            dashboardURL: URL(string: "https://fly.io/dashboard")
        ),
        ProviderDescriptor(
            id: .github,
            displayName: "GitHub",
            defaultEnabled: false,
            requiresToken: true,
            supportsTeamScope: false,
            supportsMonitoredTargets: true,
            requiresMonitoredTargets: true,
            dashboardURL: URL(string: "https://github.com")
        ),
        ProviderDescriptor(
            id: .gitlab,
            displayName: "GitLab",
            defaultEnabled: false,
            requiresToken: true,
            supportsTeamScope: true,
            supportsMonitoredTargets: true,
            requiresMonitoredTargets: true,
            dashboardURL: URL(string: "https://gitlab.com")
        )
    ]

    private static let providerOrder: [ProviderID] = [
        .mock,
        .vercel,
        .railway,
        .netlify,
        .render,
        .cloudflarePages,
        .digitalOcean,
        .heroku,
        .flyio,
        .github,
        .gitlab
    ]
}
