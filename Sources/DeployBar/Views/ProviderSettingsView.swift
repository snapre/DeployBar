import DeployBarCore
import SwiftUI

struct ProviderSettingsView: View {
    @ObservedObject var store: DeploymentStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                toolbar
                refreshPanel
                accountsPanel
                AddProviderTokenView(store: store)
            }
            .padding(.vertical, 2)
        }
    }

    private var toolbar: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Providers")
                    .font(.title2.weight(.semibold))
                Text("\(store.settings.accounts.count) accounts · \(store.settings.refreshCadence.displayName) refresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.refresh(manual: true)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
        }
    }

    private var refreshPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Refresh", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Toggle("Mock", isOn: mockProviderBinding)
                    .toggleStyle(.switch)
            }

            Picker("Cadence", selection: refreshCadenceBinding) {
                ForEach(RefreshCadence.allCases) { cadence in
                    Text(cadence.displayName).tag(cadence)
                }
            }
            .pickerStyle(.segmented)
        }
        .settingsPanel()
    }

    private var accountsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Accounts", systemImage: "key")
                    .font(.headline)
                Spacer()
                Text(store.settings.accounts.isEmpty ? "None" : "\(store.settings.accounts.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if store.settings.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No provider accounts")
                        .font(.subheadline.weight(.semibold))
                    Text("Connect a deployment provider below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.settings.accounts) { account in
                        ProviderAccountBlock(store: store, account: account)
                    }
                }
            }
        }
        .settingsPanel()
    }

    private var refreshCadenceBinding: Binding<RefreshCadence> {
        Binding {
            store.settings.refreshCadence
        } set: { value in
            store.updateSettings { $0.refreshCadence = value }
        }
    }

    private var mockProviderBinding: Binding<Bool> {
        Binding {
            store.settings.showMockProvider
        } set: { value in
            store.updateSettings { $0.showMockProvider = value }
            store.refresh(manual: true)
        }
    }
}

private struct ProviderAccountBlock: View {
    @ObservedObject var store: DeploymentStore
    var account: ProviderAccount

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProviderLogoView(provider: account.provider, size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(accountSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: enabledBinding)
                    .labelsHidden()

                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                Divider()

                if canAutoWatchAll, !account.monitoredTargets.isEmpty {
                    Button {
                        store.clearTargets(from: account.id)
                    } label: {
                        Label("Auto watch latest deployments", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }

                if account.monitoredTargets.isEmpty {
                    Text(canAutoWatchAll ? "Watching latest deployments." : "No target configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(account.monitoredTargets) { target in
                            TargetRow(provider: account.provider, target: target) {
                                store.deleteTarget(targetID: target.id, from: account.id)
                            }
                        }
                    }
                }

                AddMonitoredTargetInline(store: store, account: account) { target in
                    store.addTarget(target, to: account.id)
                }

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        store.deleteAccount(account)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }

    private var accountSubtitle: String {
        let targets = account.monitoredTargets.isEmpty ? "latest" : "\(account.monitoredTargets.count) targets"
        if account.provider == .railway, let kind = account.railwayTokenKind {
            return "\(account.provider.displayName) · \(kind.displayName) · \(targets)"
        }
        return "\(account.provider.displayName) · \(targets)"
    }

    private var canAutoWatchAll: Bool {
        account.provider.targetBehavior.requiredFields.isEmpty
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            account.isEnabled
        } set: { value in
            store.setAccountEnabled(accountID: account.id, isEnabled: value)
        }
    }
}

private struct TargetRow: View {
    var provider: ProviderID
    var target: MonitoredTarget
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProviderLogoView(provider: provider, size: 18, badge: false)

            Text(target.displayName(for: provider))
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct AddMonitoredTargetInline: View {
    @ObservedObject var store: DeploymentStore
    var account: ProviderAccount
    var onAdd: (MonitoredTarget) -> Void

    @State private var projectID = ""
    @State private var projectName = ""
    @State private var serviceID = ""
    @State private var serviceName = ""
    @State private var environmentID = ""
    @State private var environmentName = ""
    @State private var branch = ""
    @State private var isExpanded = false
    @State private var isDiscoveringRailway = false
    @State private var isDiscoveringVercel = false
    @State private var isDiscoveringProvider = false
    @State private var railwayProjects: [RailwayProjectResource] = []
    @State private var vercelProjects: [VercelProjectResource] = []
    @State private var discoveredTargets: [MonitoredTarget] = []
    @State private var selectedDiscoveredTargetID = ""
    @State private var discoveryMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                Label("Add Target", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if provider == .railway {
                        railwayDiscoveryHeader
                        railwayTargetFields
                    } else if provider == .vercel {
                        vercelDiscoveryHeader
                        vercelTargetFields
                    } else {
                        genericDiscoveryHeader
                        genericTargetFields
                    }

                    HStack {
                        Spacer()
                        Button("Add") {
                            addCurrentTarget()
                        }
                        .disabled(!canAdd)
                    }

                    if isDuplicateTarget {
                        Label("This target is already added.", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var provider: ProviderID {
        account.provider
    }

    @ViewBuilder
    private var genericDiscoveryHeader: some View {
        if supportsGenericSmartDiscovery {
            HStack(spacing: 8) {
                Button {
                    Task {
                        await discoverProviderTargets()
                    }
                } label: {
                    Label(isDiscoveringProvider ? "Discovering" : "Smart Discover", systemImage: "sparkle.magnifyingglass")
                }
                .disabled(isDiscoveringProvider)

                Text(discoveryMessage ?? genericDiscoveryHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var vercelDiscoveryHeader: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await discoverVercelResources()
                }
            } label: {
                Label(isDiscoveringVercel ? "Discovering" : "Discover", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(isDiscoveringVercel)

            if let discoveryMessage {
                Text(discoveryMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Select a project, or leave targets empty to watch all latest deployments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var vercelTargetFields: some View {
        if vercelProjects.isEmpty {
            HStack(spacing: 8) {
                TextField("Project ID", text: $projectID)
                TextField("Project name", text: $projectName)
            }
            HStack(spacing: 8) {
                TextField("Target", text: $environmentName)
                TextField("Branch", text: $branch)
            }
        } else if availableVercelProjects.isEmpty {
            Text("All discovered Vercel projects are already added.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Picker("Project", selection: $projectID) {
                ForEach(availableVercelProjects) { project in
                    Text(project.name).tag(project.id)
                }
            }
            .onChange(of: projectID) { _ in
                applySelectedVercelProject()
            }

            Picker("Environment", selection: $environmentName) {
                Text("All environments").tag("")
                ForEach(vercelEnvironmentOptions, id: \.self) { environment in
                    Text(environment.capitalized).tag(environment)
                }
            }

            Picker("Branch", selection: $branch) {
                Text("All branches").tag("")
                ForEach(vercelBranchOptions, id: \.self) { branch in
                    Text(branch).tag(branch)
                }
            }
        }
    }

    @ViewBuilder
    private var railwayDiscoveryHeader: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await discoverRailwayResources()
                }
            } label: {
                Label(isDiscoveringRailway ? "Discovering" : "Discover", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(isDiscoveringRailway)

            if let discoveryMessage {
                Text(discoveryMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(account.railwayTokenKind == .project ? "Project tokens may still need service ID." : "Fill from Railway projects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        } else if availableRailwayProjects.isEmpty {
            Text("All discovered Railway targets are already added.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Picker("Project", selection: $projectID) {
                ForEach(availableRailwayProjects) { project in
                    Text(project.name).tag(project.id)
                }
            }
            .onChange(of: projectID) { _ in
                applySelectedProject()
            }

            if let project = selectedRailwayProject, !project.services.isEmpty {
                Picker("Service", selection: $serviceID) {
                    ForEach(availableRailwayServices) { service in
                        Text(service.name).tag(service.id)
                    }
                }
                .onChange(of: serviceID) { _ in
                    serviceName = selectedRailwayService?.name ?? serviceName
                    applyFirstAvailableRailwayEnvironment()
                }
            } else {
                HStack(spacing: 8) {
                    TextField("Service ID", text: $serviceID)
                    TextField("Service name", text: $serviceName)
                }
            }

            if let project = selectedRailwayProject, !project.environments.isEmpty {
                Picker("Environment", selection: $environmentID) {
                    ForEach(availableRailwayEnvironments) { environment in
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
        if supportsGenericSmartDiscovery, !availableDiscoveredTargets.isEmpty {
            Picker("Discovered", selection: $selectedDiscoveredTargetID) {
                Text("Choose target").tag("")
                ForEach(availableDiscoveredTargets) { target in
                    Text(target.displayName(for: provider)).tag(target.id)
                }
            }
            .onChange(of: selectedDiscoveredTargetID) { _ in
                applySelectedDiscoveredTarget()
            }
        } else if supportsGenericSmartDiscovery, !discoveredTargets.isEmpty {
            Text("All discovered \(provider.displayName) targets are already added.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var target: MonitoredTarget {
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

    private var canAdd: Bool {
        let behavior = provider.targetBehavior
        let hasRequiredFields = !behavior.displayFields.isEmpty &&
            (behavior.requiredFields.isEmpty ? target.hasAnyScopeValue : target.satisfiesRequiredFields(using: behavior))
        return hasRequiredFields && !isDuplicateTarget
    }

    private var isDuplicateTarget: Bool {
        account.monitoredTargets.contains { $0.matchesScope(of: target, for: provider) }
    }

    private var supportsGenericSmartDiscovery: Bool {
        switch provider {
        case .netlify, .render, .cloudflarePages, .digitalOcean, .heroku, .flyio, .github, .gitlab:
            true
        case .mock, .vercel, .railway:
            false
        }
    }

    private var genericDiscoveryHint: String {
        if isDiscoveringProvider {
            return "Reading saved \(provider.displayName) token."
        }
        if !availableDiscoveredTargets.isEmpty {
            return "Found \(availableDiscoveredTargets.count) available target\(availableDiscoveredTargets.count == 1 ? "" : "s")."
        }
        if !discoveredTargets.isEmpty {
            return "All discovered \(provider.displayName) targets are already added."
        }
        return "Find targets from the saved token."
    }

    private var availableDiscoveredTargets: [MonitoredTarget] {
        discoveredTargets.excludingTargets(account.monitoredTargets, for: provider)
    }

    private var selectedRailwayProject: RailwayProjectResource? {
        availableRailwayProjects.first { $0.id == projectID }
    }

    private var selectedRailwayService: RailwayServiceResource? {
        availableRailwayServices.first { $0.id == serviceID }
    }

    private var selectedRailwayEnvironment: RailwayEnvironmentResource? {
        availableRailwayEnvironments.first { $0.id == environmentID }
    }

    private func resetTargetInputs() {
        projectID = ""
        projectName = ""
        serviceID = ""
        serviceName = ""
        environmentID = ""
        environmentName = ""
        branch = ""
        selectedDiscoveredTargetID = ""
    }

    private func reset() {
        resetTargetInputs()
        discoveryMessage = nil
        railwayProjects = []
        vercelProjects = []
        discoveredTargets = []
    }

    private var selectedVercelProject: VercelProjectResource? {
        availableVercelProjects.first { $0.id == projectID }
    }

    private var vercelEnvironmentOptions: [String] {
        let defaults = ["production", "preview", "staging"]
        let discovered = selectedVercelProject?.environments ?? []
        return (defaults + discovered).deduplicated().filter { environment in
            !isExistingTarget(
                MonitoredTarget(
                    projectID: selectedVercelProject?.id,
                    projectName: selectedVercelProject?.name,
                    environmentName: environment,
                    branch: branch.nilIfEmpty
                )
            )
        }
    }

    private var vercelBranchOptions: [String] {
        (selectedVercelProject?.branches ?? []).filter { candidateBranch in
            !isExistingTarget(
                MonitoredTarget(
                    projectID: selectedVercelProject?.id,
                    projectName: selectedVercelProject?.name,
                    environmentName: environmentName.nilIfEmpty,
                    branch: candidateBranch
                )
            )
        }
    }

    private var availableVercelProjects: [VercelProjectResource] {
        vercelProjects.filter { project in
            !isExistingTarget(MonitoredTarget(projectID: project.id, projectName: project.name))
        }
    }

    private var availableRailwayProjects: [RailwayProjectResource] {
        railwayProjects.filter { project in
            if project.services.isEmpty || project.environments.isEmpty {
                return true
            }
            return project.services.contains { service in
                project.environments.contains { environment in
                    !isExistingTarget(railwayTarget(project: project, service: service, environment: environment))
                }
            }
        }
    }

    private var availableRailwayServices: [RailwayServiceResource] {
        guard let project = selectedRailwayProject else { return [] }
        return availableRailwayServices(in: project)
    }

    private var availableRailwayEnvironments: [RailwayEnvironmentResource] {
        guard let project = selectedRailwayProject else { return [] }
        let service = availableRailwayServices.first { $0.id == serviceID }
        return availableRailwayEnvironments(in: project, service: service)
    }

    private func availableRailwayServices(in project: RailwayProjectResource) -> [RailwayServiceResource] {
        guard !project.environments.isEmpty else { return project.services }
        return project.services.filter { service in
            project.environments.contains { environment in
                !isExistingTarget(railwayTarget(project: project, service: service, environment: environment))
            }
        }
    }

    private func availableRailwayEnvironments(in project: RailwayProjectResource, service: RailwayServiceResource?) -> [RailwayEnvironmentResource] {
        guard let service else { return project.environments }
        return project.environments.filter { environment in
            !isExistingTarget(railwayTarget(project: project, service: service, environment: environment))
        }
    }

    private func railwayTarget(
        project: RailwayProjectResource,
        service: RailwayServiceResource,
        environment: RailwayEnvironmentResource
    ) -> MonitoredTarget {
        MonitoredTarget(
            projectID: project.id,
            projectName: project.name,
            serviceID: service.id,
            serviceName: service.name,
            environmentID: environment.id,
            environmentName: environment.name
        )
    }

    private func isExistingTarget(_ candidate: MonitoredTarget) -> Bool {
        account.monitoredTargets.contains { $0.matchesScope(of: candidate, for: provider) }
    }

    private var targetInputLabels: TargetInputLabels {
        TargetInputLabels(provider: provider)
    }

    private func addCurrentTarget() {
        let addedTarget = target
        onAdd(addedTarget)

        if discoveredTargets.isEmpty {
            reset()
            isExpanded = false
            return
        }

        discoveredTargets.removeAll { $0.matchesScope(of: addedTarget, for: provider) }
        resetTargetInputs()

        if availableDiscoveredTargets.isEmpty {
            discoveryMessage = "All discovered \(provider.displayName) targets are already added."
        } else {
            discoveryMessage = "Found \(availableDiscoveredTargets.count) available target\(availableDiscoveredTargets.count == 1 ? "" : "s")."
            applyFirstDiscoveredTarget()
        }
    }

    private func discoverProviderTargets() async {
        isDiscoveringProvider = true
        discoveryMessage = nil
        let result = await store.discoverProviderTargets(for: account)
        isDiscoveringProvider = false

        if let issue = result.issues.first {
            discoveryMessage = issue.message
            discoveredTargets = []
            resetTargetInputs()
            return
        }

        discoveredTargets = result.targets.deduplicatedTargets(for: provider)
        resetTargetInputs()

        if discoveredTargets.isEmpty {
            discoveryMessage = "No \(provider.displayName) targets were discovered."
        } else if availableDiscoveredTargets.isEmpty {
            discoveryMessage = "All discovered \(provider.displayName) targets are already added."
        } else {
            discoveryMessage = "Found \(availableDiscoveredTargets.count) available target\(availableDiscoveredTargets.count == 1 ? "" : "s")."
            applyFirstDiscoveredTarget()
        }
    }

    private func applyFirstDiscoveredTarget() {
        guard let target = availableDiscoveredTargets.first else { return }
        selectedDiscoveredTargetID = target.id
        applyDiscoveredTarget(target)
    }

    private func applySelectedDiscoveredTarget() {
        guard let target = availableDiscoveredTargets.first(where: { $0.id == selectedDiscoveredTargetID }) else {
            resetTargetInputs()
            return
        }
        applyDiscoveredTarget(target)
    }

    private func applyDiscoveredTarget(_ target: MonitoredTarget) {
        projectID = target.projectID ?? ""
        projectName = target.projectName ?? ""
        serviceID = target.serviceID ?? ""
        serviceName = target.serviceName ?? ""
        environmentID = target.environmentID ?? ""
        environmentName = target.environmentName ?? ""
        branch = target.branch ?? ""
    }

    private func discoverVercelResources() async {
        isDiscoveringVercel = true
        let result = await store.discoverVercelResources(for: account)
        isDiscoveringVercel = false

        if let issue = result.issues.first {
            discoveryMessage = issue.message
            vercelProjects = []
            return
        }

        vercelProjects = result.projects
        if vercelProjects.isEmpty {
            discoveryMessage = "No Vercel projects found."
        } else if availableVercelProjects.isEmpty {
            discoveryMessage = "All discovered Vercel projects are already added."
        } else {
            discoveryMessage = "Found \(availableVercelProjects.count) available project\(availableVercelProjects.count == 1 ? "" : "s")."
            applyFirstVercelSelection()
        }
    }

    private func applyFirstVercelSelection() {
        guard let project = availableVercelProjects.first else { return }
        projectID = project.id
        projectName = project.name
        environmentName = ""
        branch = ""
    }

    private func applySelectedVercelProject() {
        guard let project = selectedVercelProject else { return }
        projectName = project.name
        environmentName = ""
        branch = ""
    }

    private func discoverRailwayResources() async {
        isDiscoveringRailway = true
        let result = await store.discoverRailwayResources(for: account)
        isDiscoveringRailway = false

        if let issue = result.issues.first {
            discoveryMessage = issue.message
            railwayProjects = []
            return
        }

        railwayProjects = result.projects
        if railwayProjects.isEmpty {
            discoveryMessage = "No Railway projects found."
        } else if availableRailwayProjects.isEmpty {
            discoveryMessage = "All discovered Railway targets are already added."
        } else {
            discoveryMessage = "Found \(availableRailwayProjects.count) project\(availableRailwayProjects.count == 1 ? "" : "s") with available targets."
            applyFirstRailwaySelection()
        }
    }

    private func applyFirstRailwaySelection() {
        guard let project = availableRailwayProjects.first else { return }
        applyRailwayProject(project)
    }

    private func applyRailwayProject(_ project: RailwayProjectResource) {
        projectID = project.id
        projectName = project.name
        let service = availableRailwayServices(in: project).first
        serviceID = service?.id ?? ""
        serviceName = service?.name ?? ""
        let environment = availableRailwayEnvironments(in: project, service: service).first
        environmentID = environment?.id ?? ""
        environmentName = environment?.name ?? ""
    }

    private func applySelectedProject() {
        guard let project = selectedRailwayProject else { return }
        applyRailwayProject(project)
    }

    private func applyFirstAvailableRailwayEnvironment() {
        let environment = availableRailwayEnvironments.first
        environmentID = environment?.id ?? ""
        environmentName = environment?.name ?? ""
    }
}

private extension Array where Element == String {
    func deduplicated() -> [String] {
        var seen = Set<String>()
        return filter { value in
            seen.insert(value).inserted
        }
    }
}

struct TargetInputLabels {
    var projectID = "Project ID"
    var projectName = "Project name"
    var serviceID = "Service ID"
    var serviceName = "Service name"
    var environmentID = "Environment ID"
    var environmentName = "Environment name"
    var branch = "Branch"

    init(provider: ProviderID) {
        switch provider {
        case .mock, .vercel, .railway:
            break
        case .netlify:
            projectID = "Site ID"
            projectName = "Site name"
            environmentName = "Context"
        case .render:
            serviceID = "Service ID"
            serviceName = "Service name"
            environmentName = "Service type"
        case .cloudflarePages:
            projectID = "Project ID"
            projectName = "Project name"
        case .digitalOcean:
            projectID = "App ID"
            projectName = "App name"
            serviceID = "Component ID"
            serviceName = "Component name"
            environmentName = "Phase"
        case .heroku:
            projectID = "App ID"
            projectName = "App name"
        case .flyio:
            projectID = "App name"
            projectName = "Label"
        case .github:
            projectID = "Repository"
            projectName = "Repository label"
            environmentName = "Environment"
        case .gitlab:
            projectID = "Project ID"
            projectName = "Project path"
            environmentName = "Environment"
        }
    }
}

private extension View {
    func settingsPanel() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}
