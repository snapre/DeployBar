import AppKit
import DeployBarCore
import SwiftUI

struct AddProviderTokenView: View {
    @ObservedObject var store: DeploymentStore
    @Environment(\.openURL) private var openURL

    @State private var provider: ProviderID = .vercel
    @State private var displayName = ""
    @State private var token = ""
    @State private var teamID = ""
    @State private var teamSlug = ""
    @State private var railwayTokenKind: RailwayTokenKind = .accountOrWorkspace
    @State private var authHeader: ProviderAuthHeader?
    @State private var projectID = ""
    @State private var projectName = ""
    @State private var serviceID = ""
    @State private var serviceName = ""
    @State private var environmentID = ""
    @State private var environmentName = ""
    @State private var branch = ""
    @State private var validationMessage: String?
    @State private var isDiscoveringRailway = false
    @State private var isDiscoveringProvider = false
    @State private var isConnectingOAuth = false
    @State private var railwayProjects: [RailwayProjectResource] = []
    @State private var discoveredTargets: [MonitoredTarget] = []
    @State private var discoveredScopes: [ProviderScopeResource] = []
    @State private var selectedDiscoveredTargetID = ""
    @State private var showsCloudflareManualAccountID = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker("Provider", selection: $provider) {
                ForEach(store.providerDescriptors) { descriptor in
                    Text(descriptor.displayName)
                        .tag(descriptor.id)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Account label", text: $displayName)
                HStack(spacing: 8) {
                    SecureField("API token", text: $token)
                    Button {
                        pasteToken()
                    } label: {
                        Label(pasteTokenButtonTitle, systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help(pasteTokenButtonHelp)

                    if let tokenLink {
                        Button {
                            openURL(tokenLink.url)
                        } label: {
                            Label(tokenLink.title, systemImage: "key")
                        }
                        .buttonStyle(.bordered)
                        .help(tokenLink.help)
                    }

                    if supportsOAuth {
                        Button {
                            Task {
                                await connectOAuth()
                            }
                        } label: {
                            Label(isConnectingOAuth ? "Connecting" : "OAuth Connect", systemImage: "person.badge.key")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isConnectingOAuth)
                        .help("Authorize \(provider.displayName) in the browser and save the returned access token.")
                    }
                }

                providerSpecificFields
                targetFields
            }

            HStack(alignment: .center) {
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    addAccount()
                } label: {
                    Label("Connect", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canConnect)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: provider) { _ in
            validationMessage = nil
            resetProviderScopedFields()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                ProviderLogoView(provider: provider, size: 22)
                Text("Connect Provider")
                    .font(.headline)
            }
            Spacer()
            Text(provider.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var providerSpecificFields: some View {
        if provider == .vercel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Team ID", text: $teamID)
                    TextField("Team slug", text: $teamSlug)
                }
                smartDiscoveryFields
            }
        } else if provider == .cloudflarePages {
            VStack(alignment: .leading, spacing: 8) {
                if !discoveredScopes.isEmpty {
                    Picker("Account", selection: $teamID) {
                        ForEach(discoveredScopes) { scope in
                            Text(scope.name).tag(scope.id)
                        }
                    }
                    .onChange(of: teamID) { _ in
                        resetDiscoveredTargets()
                    }
                } else if showsCloudflareManualAccountID || teamID.nilIfEmpty != nil {
                    HStack(spacing: 8) {
                        TextField("Cloudflare account ID", text: $teamID)
                        Button {
                            showsCloudflareManualAccountID = false
                            teamID = ""
                            resetDiscoveredTargets()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Hide manual account ID.")
                    }
                } else {
                    Button {
                        showsCloudflareManualAccountID = true
                    } label: {
                        Label("Manual Account ID", systemImage: "number")
                    }
                    .buttonStyle(.bordered)
                    .help("Use this only if account discovery cannot read your Cloudflare accounts.")
                }

                smartDiscoveryFields
            }
        } else if provider == .gitlab {
            VStack(alignment: .leading, spacing: 8) {
                TextField("GitLab API base URL", text: $teamSlug)
                smartDiscoveryFields
            }
        } else if provider == .railway {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Token type", selection: $railwayTokenKind) {
                    ForEach(RailwayTokenKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: railwayTokenKind) { _ in
                    resetRailwayDiscovery()
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await discoverRailwayResources()
                        }
                    } label: {
                        Label(isDiscoveringRailway ? "Discovering" : "Discover Railway", systemImage: "sparkle.magnifyingglass")
                    }
                    .disabled(token.nilIfEmpty == nil || isDiscoveringRailway)

                    Text(railwayDiscoveryHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } else if supportsSmartDiscovery {
            smartDiscoveryFields
        }
    }

    @ViewBuilder
    private var smartDiscoveryFields: some View {
        if supportsSmartDiscovery {
            HStack(spacing: 8) {
                Button {
                    Task {
                        await discoverProviderResources()
                    }
                } label: {
                    Label(isDiscoveringProvider ? "Discovering" : "Smart Discover", systemImage: "sparkle.magnifyingglass")
                }
                .disabled(token.nilIfEmpty == nil || isDiscoveringProvider)

                Text(smartDiscoveryHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var targetFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(targetSectionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if provider == .railway {
                railwayTargetFields
            } else if provider == .vercel {
                discoveredTargetPicker
                HStack(spacing: 8) {
                    TextField("Project ID", text: $projectID)
                    TextField("Project name", text: $projectName)
                }
                HStack(spacing: 8) {
                    TextField("Target", text: $environmentName)
                    TextField("Branch", text: $branch)
                }
            } else {
                genericTargetFields
            }
        }
    }

    @ViewBuilder
    private var genericTargetFields: some View {
        let labels = targetInputLabels
        discoveredTargetPicker
        if provider.targetBehavior.displayFields.contains(.project) {
            HStack(spacing: 8) {
                TextField(labels.projectID, text: $projectID)
                TextField(labels.projectName, text: $projectName)
            }
        }
        if provider.targetBehavior.displayFields.contains(.service) {
            HStack(spacing: 8) {
                TextField(labels.serviceID, text: $serviceID)
                TextField(labels.serviceName, text: $serviceName)
            }
        }
        if provider.targetBehavior.displayFields.contains(.environment) {
            HStack(spacing: 8) {
                TextField(labels.environmentID, text: $environmentID)
                TextField(labels.environmentName, text: $environmentName)
            }
        }
        if provider.targetBehavior.displayFields.contains(.branch) {
            TextField(labels.branch, text: $branch)
        }
    }

    @ViewBuilder
    private var discoveredTargetPicker: some View {
        if supportsSmartDiscovery, !discoveredTargets.isEmpty {
            Picker("Discovered", selection: $selectedDiscoveredTargetID) {
                Text(provider.targetBehavior.emptyTargetName).tag("")
                ForEach(discoveredTargets) { target in
                    Text(target.displayName(for: provider)).tag(target.id)
                }
            }
            .onChange(of: selectedDiscoveredTargetID) { _ in
                applySelectedDiscoveredTarget()
            }
        }
    }

    @ViewBuilder
    private var railwayTargetFields: some View {
        if railwayProjects.isEmpty {
            HStack(spacing: 8) {
                TextField("Project ID", text: $projectID)
                TextField("Project name", text: $projectName)
            }
            HStack(spacing: 8) {
                TextField("Service ID", text: $serviceID)
                TextField("Service name", text: $serviceName)
            }
            HStack(spacing: 8) {
                TextField("Environment ID", text: $environmentID)
                TextField("Environment name", text: $environmentName)
            }
        } else {
            Picker("Project", selection: $projectID) {
                ForEach(railwayProjects) { project in
                    Text(project.name).tag(project.id)
                }
            }
            .onChange(of: projectID) { _ in
                applySelectedProject()
            }

            if let project = selectedRailwayProject, !project.services.isEmpty {
                Picker("Service", selection: $serviceID) {
                    ForEach(project.services) { service in
                        Text(service.name).tag(service.id)
                    }
                }
                .onChange(of: serviceID) { _ in
                    serviceName = selectedRailwayService?.name ?? serviceName
                }
            } else {
                HStack(spacing: 8) {
                    TextField("Service ID", text: $serviceID)
                    TextField("Service name", text: $serviceName)
                }
            }

            if let project = selectedRailwayProject, !project.environments.isEmpty {
                Picker("Environment", selection: $environmentID) {
                    ForEach(project.environments) { environment in
                        Text(environment.name).tag(environment.id)
                    }
                }
                .onChange(of: environmentID) { _ in
                    environmentName = selectedRailwayEnvironment?.name ?? environmentName
                }
            } else {
                HStack(spacing: 8) {
                    TextField("Environment ID", text: $environmentID)
                    TextField("Environment name", text: $environmentName)
                }
            }
        }
    }

    private var canConnect: Bool {
        token.nilIfEmpty != nil && providerScopeIsValid && requiredTargetIsValid
    }

    private var providerScopeIsValid: Bool {
        provider != .cloudflarePages || teamID.nilIfEmpty != nil
    }

    private var requiredTargetIsValid: Bool {
        let behavior = provider.targetBehavior
        if behavior.requiredFields.isEmpty {
            return true
        }
        return currentTarget.satisfiesRequiredFields(using: behavior)
    }

    private var targetSectionTitle: String {
        provider.targetBehavior.requiredFields.isEmpty ? "Optional Filter" : "Initial Target"
    }

    private var tokenLink: ProviderTokenLink? {
        provider.tokenLink(
            railwayTokenKind: provider == .railway ? railwayTokenKind : nil,
            gitLabAPIBaseURL: provider == .gitlab ? teamSlug.nilIfEmpty : nil
        )
    }

    private var oauthDescriptor: ProviderOAuthDescriptor? {
        provider.oauthDescriptor(gitLabAPIBaseURL: provider == .gitlab ? teamSlug.nilIfEmpty : nil)
    }

    private var supportsOAuth: Bool {
        false
    }

    private var canDiscoverAfterPaste: Bool {
        provider == .railway || supportsSmartDiscovery
    }

    private var pasteTokenButtonTitle: String {
        if provider == .cloudflarePages {
            return "Paste & Find Pages"
        }
        return canDiscoverAfterPaste ? "Paste & Discover" : "Paste Token"
    }

    private var pasteTokenButtonHelp: String {
        if provider == .cloudflarePages {
            return "Paste a Cloudflare token from the clipboard and find accounts and Pages projects."
        }
        return canDiscoverAfterPaste
            ? "Paste a token from the clipboard and immediately discover available resources."
            : "Paste a token from the clipboard."
    }

    private var railwayDiscoveryHint: String {
        if isDiscoveringRailway {
            return "Reading projects, services, and environments."
        }
        if railwayProjects.isEmpty {
            return railwayTokenKind == .project
                ? "Project tokens can reveal project/environment scope; service may still need manual entry."
                : "Use account/workspace token to fill projects, services, and environments."
        }
        return "Found \(railwayProjects.count) project\(railwayProjects.count == 1 ? "" : "s")."
    }

    private var supportsSmartDiscovery: Bool {
        switch provider {
        case .vercel, .netlify, .render, .cloudflarePages, .digitalOcean, .heroku, .github, .gitlab:
            true
        case .mock, .railway:
            false
        }
    }

    private var smartDiscoveryHint: String {
        if isDiscoveringProvider {
            return provider == .cloudflarePages && teamID.nilIfEmpty == nil
                ? "Finding Cloudflare accounts and Pages projects."
                : "Finding projects, apps, and services."
        }
        if !discoveredTargets.isEmpty {
            let noun = discoveredTargets.count == 1 ? "resource" : "resources"
            if !provider.targetBehavior.requiredFields.isEmpty {
                return "Found \(discoveredTargets.count) \(noun). Choose one to enable Connect."
            }
            return "Found \(discoveredTargets.count) \(noun). Leave blank to watch all, or choose a filter."
        }
        if provider == .cloudflarePages, !discoveredScopes.isEmpty {
            return "Found \(discoveredScopes.count) account\(discoveredScopes.count == 1 ? "" : "s"). Run discovery again after changing accounts."
        }
        if provider == .cloudflarePages {
            return teamID.nilIfEmpty == nil
                ? "Paste a Pages Read + Memberships Read token to find accounts and projects."
                : "List Pages projects for this account."
        }
        return "Validate the token and list available resources."
    }

    private var selectedRailwayProject: RailwayProjectResource? {
        railwayProjects.first { $0.id == projectID }
    }

    private var selectedRailwayService: RailwayServiceResource? {
        selectedRailwayProject?.services.first { $0.id == serviceID }
    }

    private var selectedRailwayEnvironment: RailwayEnvironmentResource? {
        selectedRailwayProject?.environments.first { $0.id == environmentID }
    }

    private func addAccount() {
        guard canConnect else {
            validationMessage = validationErrorMessage
            return
        }

        let tokenReference = UUID().uuidString
        let target = initialTarget()
        let account = ProviderAccount(
            provider: provider,
            displayName: displayName.nilIfEmpty ?? provider.displayName,
            tokenReference: tokenReference,
            teamID: teamID.nilIfEmpty,
            teamSlug: teamSlug.nilIfEmpty,
            railwayTokenKind: provider == .railway ? railwayTokenKind : nil,
            authHeader: authHeader,
            monitoredTargets: target.map { [$0] } ?? []
        )

        store.addAccount(account, token: token)
        resetAllFields()
    }

    private func initialTarget() -> MonitoredTarget? {
        let target = currentTarget
        let behavior = provider.targetBehavior
        if behavior.displayFields.isEmpty {
            return nil
        }
        if !behavior.requiredFields.isEmpty {
            return target
        }
        return target.hasAnyScopeValue ? target : nil
    }

    private var currentTarget: MonitoredTarget {
        MonitoredTarget(
            projectID: projectID.nilIfEmpty,
            projectName: projectName.nilIfEmpty,
            serviceID: serviceID.nilIfEmpty,
            serviceName: serviceName.nilIfEmpty,
            environmentID: environmentID.nilIfEmpty,
            environmentName: environmentName.nilIfEmpty,
            branch: branch.nilIfEmpty
        )
    }

    private var validationErrorMessage: String {
        if token.nilIfEmpty == nil {
            return "API token is required."
        }
        if provider == .cloudflarePages, teamID.nilIfEmpty == nil {
            return "Cloudflare Pages requires an account ID."
        }
        if !provider.targetBehavior.requiredFields.isEmpty {
            return "\(provider.displayName) needs an initial target."
        }
        return "Provider settings are incomplete."
    }

    private func resetProviderScopedFields() {
        teamID = ""
        teamSlug = ""
        authHeader = nil
        resetRailwayDiscovery()
        resetSmartDiscovery()
    }

    private func resetRailwayDiscovery() {
        resetTargetFields()
        railwayProjects = []
    }

    private func resetTargetFields() {
        projectID = ""
        projectName = ""
        serviceID = ""
        serviceName = ""
        environmentID = ""
        environmentName = ""
        branch = ""
    }

    private func resetSmartDiscovery() {
        isDiscoveringProvider = false
        discoveredTargets = []
        discoveredScopes = []
        selectedDiscoveredTargetID = ""
        showsCloudflareManualAccountID = false
    }

    private func resetDiscoveredTargets() {
        discoveredTargets = []
        selectedDiscoveredTargetID = ""
        resetTargetFields()
    }

    private func resetAllFields() {
        displayName = ""
        token = ""
        validationMessage = nil
        resetProviderScopedFields()
    }

    private var targetInputLabels: TargetInputLabels {
        TargetInputLabels(provider: provider)
    }

    private func pasteToken() {
        guard let pastedToken = NSPasteboard.general.string(forType: .string)?.nilIfEmpty else {
            validationMessage = "Clipboard does not contain a token."
            return
        }

        token = pastedToken
        authHeader = nil
        validationMessage = nil

        guard canDiscoverAfterPaste else { return }
        Task {
            if provider == .railway {
                await discoverRailwayResources(token: pastedToken)
            } else {
                await discoverProviderResources(token: pastedToken)
            }
        }
    }

    private func discoverRailwayResources(token overrideToken: String? = nil) async {
        guard let token = overrideToken ?? token.nilIfEmpty else {
            validationMessage = "API token is required before discovery."
            return
        }

        isDiscoveringRailway = true
        validationMessage = nil
        let result = await store.discoverRailwayResources(token: token, tokenKind: railwayTokenKind)
        isDiscoveringRailway = false

        if let issue = result.issues.first {
            validationMessage = issue.message
            railwayProjects = []
            return
        }

        railwayProjects = result.projects
        if railwayProjects.isEmpty {
            validationMessage = "No Railway projects were discovered for this token."
        } else {
            applyFirstRailwaySelection()
        }
    }

    private func connectOAuth() async {
        guard let descriptor = oauthDescriptor else {
            validationMessage = "OAuth is not supported for \(provider.displayName) yet."
            return
        }

        isConnectingOAuth = true
        validationMessage = nil
        do {
            let connector = ProviderOAuthConnector()
            let oauthToken = try await connector.authorize(
                provider: provider,
                gitLabAPIBaseURL: provider == .gitlab ? teamSlug.nilIfEmpty : nil
            )
            token = oauthToken.accessToken
            authHeader = descriptor.storesAsBearerToken ? .bearer : nil

            if provider == .railway {
                railwayTokenKind = .accountOrWorkspace
                await discoverRailwayResources(token: oauthToken.accessToken)
            } else if supportsSmartDiscovery {
                await discoverProviderResources(token: oauthToken.accessToken)
            }

            if canConnect {
                addAccount()
            } else {
                validationMessage = "OAuth authorized. Choose the required target, then Connect."
            }
        } catch {
            validationMessage = "OAuth failed: \(error.localizedDescription)"
        }
        isConnectingOAuth = false
    }

    private func discoverProviderResources(token overrideToken: String? = nil) async {
        guard let token = overrideToken ?? token.nilIfEmpty else {
            validationMessage = "API token is required before discovery."
            return
        }
        guard supportsSmartDiscovery else {
            validationMessage = "\(provider.displayName) discovery is not supported yet."
            return
        }

        isDiscoveringProvider = true
        validationMessage = nil

        if provider == .cloudflarePages, teamID.nilIfEmpty == nil {
            let accountResult = await store.discoverCloudflareAccounts(token: token)
            if let issue = accountResult.issues.first {
                validationMessage = issue.message
                discoveredScopes = []
                discoveredTargets = []
                isDiscoveringProvider = false
                return
            }

            discoveredScopes = accountResult.scopes
            if let firstScope = discoveredScopes.first {
                teamID = firstScope.id
                showsCloudflareManualAccountID = false
            } else {
                validationMessage = "No Cloudflare accounts were found. Create a Pages token with Memberships Read, or enter the account ID manually."
                discoveredTargets = []
                isDiscoveringProvider = false
                return
            }
        }

        let result = await store.discoverProviderTargets(
            provider: provider,
            token: token,
            teamID: teamID.nilIfEmpty,
            teamSlug: teamSlug.nilIfEmpty,
            authHeader: authHeader
        )
        isDiscoveringProvider = false

        if let issue = result.issues.first {
            validationMessage = issue.message
            discoveredTargets = []
            selectedDiscoveredTargetID = ""
            return
        }

        discoveredTargets = result.targets
        selectedDiscoveredTargetID = ""
        resetTargetFields()

        if discoveredTargets.isEmpty {
            validationMessage = "No \(provider.displayName) resources were discovered for this token."
        }
    }

    private func applySelectedDiscoveredTarget() {
        guard let target = discoveredTargets.first(where: { $0.id == selectedDiscoveredTargetID }) else {
            resetTargetFields()
            return
        }

        projectID = target.projectID ?? ""
        projectName = target.projectName ?? ""
        serviceID = target.serviceID ?? ""
        serviceName = target.serviceName ?? ""
        environmentID = target.environmentID ?? ""
        environmentName = target.environmentName ?? ""
        branch = target.branch ?? ""
    }

    private func applyFirstRailwaySelection() {
        guard let project = railwayProjects.first else { return }
        projectID = project.id
        projectName = project.name
        serviceID = project.services.first?.id ?? serviceID
        serviceName = project.services.first?.name ?? serviceName
        environmentID = project.environments.first?.id ?? environmentID
        environmentName = project.environments.first?.name ?? environmentName
    }

    private func applySelectedProject() {
        guard let project = selectedRailwayProject else { return }
        projectName = project.name
        serviceID = project.services.first?.id ?? ""
        serviceName = project.services.first?.name ?? ""
        environmentID = project.environments.first?.id ?? ""
        environmentName = project.environments.first?.name ?? ""
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
