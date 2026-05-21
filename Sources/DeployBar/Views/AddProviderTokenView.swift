import DeployBarCore
import SwiftUI

struct AddProviderTokenView: View {
    @ObservedObject var store: DeploymentStore

    @State private var provider: ProviderID = .vercel
    @State private var displayName = ""
    @State private var token = ""
    @State private var teamID = ""
    @State private var teamSlug = ""
    @State private var railwayTokenKind: RailwayTokenKind = .project
    @State private var projectID = ""
    @State private var projectName = ""
    @State private var serviceID = ""
    @State private var serviceName = ""
    @State private var environmentID = ""
    @State private var environmentName = ""
    @State private var branch = ""
    @State private var validationMessage: String?
    @State private var isDiscoveringRailway = false
    @State private var railwayProjects: [RailwayProjectResource] = []

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
                SecureField("API token", text: $token)

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
        .onChange(of: provider) {
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
            HStack(spacing: 8) {
                TextField("Team ID", text: $teamID)
                TextField("Team slug", text: $teamSlug)
            }
        } else if provider == .cloudflarePages {
            TextField("Cloudflare account ID", text: $teamID)
        } else if provider == .gitlab {
            TextField("GitLab API base URL", text: $teamSlug)
        } else if provider == .railway {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Token type", selection: $railwayTokenKind) {
                    ForEach(RailwayTokenKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: railwayTokenKind) {
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

                    Text(discoveryHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
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
            .onChange(of: projectID) {
                applySelectedProject()
            }

            if let project = selectedRailwayProject, !project.services.isEmpty {
                Picker("Service", selection: $serviceID) {
                    ForEach(project.services) { service in
                        Text(service.name).tag(service.id)
                    }
                }
                .onChange(of: serviceID) {
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
                .onChange(of: environmentID) {
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

    private var discoveryHint: String {
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
        resetRailwayDiscovery()
    }

    private func resetRailwayDiscovery() {
        projectID = ""
        projectName = ""
        serviceID = ""
        serviceName = ""
        environmentID = ""
        environmentName = ""
        branch = ""
        railwayProjects = []
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

    private func discoverRailwayResources() async {
        guard let token = token.nilIfEmpty else {
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
