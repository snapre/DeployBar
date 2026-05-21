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
        ProviderID.allCases.compactMap { providers[$0] }
    }

    public var allDescriptors: [ProviderDescriptor] {
        ProviderID.allCases.compactMap { descriptors[$0] }
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
        )
    ]
}
