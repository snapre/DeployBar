#if DEBUG
import AppKit
import Darwin
import DeployBarCore
import SwiftUI

@MainActor
enum WebsiteScreenshotRenderer {
    static func renderIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments

        if let flagIndex = arguments.firstIndex(of: "--render-website-screenshots") {
            guard arguments.indices.contains(flagIndex + 1) else {
                fputs("Missing output directory for --render-website-screenshots.\n", stderr)
                exit(EX_USAGE)
            }

            do {
                try renderAll(to: URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true))
                exit(EXIT_SUCCESS)
            } catch {
                fputs("Could not render website screenshots: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }

        guard let flagIndex = arguments.firstIndex(of: "--render-website-screenshot") else {
            return false
        }

        guard arguments.indices.contains(flagIndex + 1) else {
            fputs("Missing output path for --render-website-screenshot.\n", stderr)
            exit(EX_USAGE)
        }

        do {
            let now = Date()
            try render(group: WebsitePreviewFixture.groups(now: now)[0], updatedAt: now, to: URL(fileURLWithPath: arguments[flagIndex + 1]))
            exit(EXIT_SUCCESS)
        } catch {
            fputs("Could not render website screenshot: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func renderAll(to outputDirectory: URL) throws {
        let now = Date()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for group in WebsitePreviewFixture.groups(now: now) {
            try render(
                group: group,
                updatedAt: now,
                to: outputDirectory.appendingPathComponent(group.filename)
            )
        }
    }

    private static func render(group: WebsitePreviewGroup, updatedAt: Date, to outputURL: URL) throws {
        let store = DeploymentStore(
            settingsStore: SettingsStore(settingsURL: FileManager.default.temporaryDirectory.appendingPathComponent("deploybar-website-preview-\(group.index)-settings.json"))
        )
        store.loadWebsitePreview(snapshots: group.snapshots, lastRefreshAt: updatedAt)

        let view = WebsitePopoverScreenshot(store: store)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: WebsitePopoverScreenshot.size.width, height: WebsitePopoverScreenshot.size.height)

        guard let image = renderer.cgImage else {
            throw CocoaError(.coderInvalidValue)
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: [.atomic])
    }
}

private struct WebsitePreviewGroup {
    var index: Int
    var filename: String
    var snapshots: [DeploymentSnapshot]
}

private struct WebsitePopoverScreenshot: View {
    static let size = CGSize(width: DeploymentPopoverView.preferredWidth, height: 786)

    @ObservedObject var store: DeploymentStore

    var body: some View {
        DeploymentPopoverView(store: store, usesScrollView: false)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.34), lineWidth: 1)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

private enum WebsitePreviewFixture {
    static func groups(now: Date) -> [WebsitePreviewGroup] {
        let snapshots = snapshots(now: now)
        let snapshotsByProvider = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.provider, $0) })
        let groups: [[ProviderID]] = [
            [.vercel, .railway, .github],
            [.netlify, .render, .cloudflarePages],
            [.digitalOcean, .heroku, .gitlab]
        ]

        return groups.enumerated().map { offset, providers in
            WebsitePreviewGroup(
                index: offset + 1,
                filename: "deploybar-provider-preview-\(offset + 1).png",
                snapshots: providers.compactMap { snapshotsByProvider[$0] }
            )
        }
    }

    private static func snapshots(now: Date) -> [DeploymentSnapshot] {
        [
            DeploymentSnapshot(
                id: "website-cloudflare-pages",
                provider: .cloudflarePages,
                projectName: "docs-site",
                environmentName: "Production",
                branch: "main",
                commitSha: "2ad71f9",
                commitMessage: "Rebuild docs search index",
                actor: "nora",
                status: .building,
                createdAt: now.addingTimeInterval(-240),
                startedAt: now.addingTimeInterval(-210),
                dashboardURL: URL(string: "https://dash.cloudflare.com"),
                lastUpdatedAt: now
            ),
            DeploymentSnapshot(
                id: "website-github",
                provider: .github,
                projectName: "snapre/deploybar",
                environmentName: "Release",
                branch: "main",
                commitSha: "88b62ca",
                commitMessage: "Publish notarized macOS build",
                actor: "snapre",
                status: .success,
                createdAt: now.addingTimeInterval(-87800),
                startedAt: now.addingTimeInterval(-87780),
                finishedAt: now.addingTimeInterval(-87620),
                duration: 160,
                dashboardURL: URL(string: "https://github.com/snapre/DeployBar/deployments"),
                lastUpdatedAt: now
            ),
            DeploymentSnapshot(
                id: "website-vercel",
                provider: .vercel,
                projectName: "dashboard-web",
                environmentName: "Production",
                branch: "main",
                commitSha: "9f42ac1",
                commitMessage: "Ship usage overview",
                actor: "mira",
                status: .ready,
                createdAt: now.addingTimeInterval(-85600),
                startedAt: now.addingTimeInterval(-85520),
                finishedAt: now.addingTimeInterval(-85420),
                duration: 100,
                dashboardURL: URL(string: "https://vercel.com"),
                deploymentURL: URL(string: "https://dashboard.example.com"),
                lastUpdatedAt: now
            ),
            DeploymentSnapshot(
                id: "website-railway",
                provider: .railway,
                projectName: "control-plane",
                serviceName: "api-service",
                environmentName: "Production",
                branch: "main",
                commitSha: "3b7a14d",
                commitMessage: "Rotate worker health checks",
                actor: "alex",
                status: .success,
                createdAt: now.addingTimeInterval(-87200),
                startedAt: now.addingTimeInterval(-87100),
                finishedAt: now.addingTimeInterval(-86940),
                duration: 160,
                dashboardURL: URL(string: "https://railway.app"),
                lastUpdatedAt: now
            ),
            DeploymentSnapshot(
                id: "website-netlify",
                provider: .netlify,
                projectName: "marketing-site",
                environmentName: "Deploy Preview",
                branch: "pricing-refresh",
                commitSha: "4c23e10",
                commitMessage: "Refresh pricing hero copy",
                actor: "sam",
                status: .queued,
                createdAt: now.addingTimeInterval(-120),
                dashboardURL: URL(string: "https://app.netlify.com"),
                lastUpdatedAt: now
            ),
            DeploymentSnapshot(
                id: "website-gitlab",
                provider: .gitlab,
                projectName: "platform/mobile-api",
                environmentName: "Staging",
                branch: "release/0.2",
                commitSha: "77dc901",
                commitMessage: "Prepare staged rollout",
                actor: "li",
                status: .failed,
                createdAt: now.addingTimeInterval(-960),
                startedAt: now.addingTimeInterval(-880),
                finishedAt: now.addingTimeInterval(-760),
                duration: 120,
                dashboardURL: URL(string: "https://gitlab.com"),
                errorMessage: "Pipeline failed before deploy.",
                lastUpdatedAt: now
            ),
            DeploymentSnapshot(
                id: "website-render",
                provider: .render,
                projectName: "image-proxy",
                serviceName: "web-service",
                environmentName: "Production",
                branch: "main",
                commitSha: "a0c29be",
                commitMessage: "Tune cache headers",
                actor: "mira",
                status: .deploying,
                createdAt: now.addingTimeInterval(-390),
                startedAt: now.addingTimeInterval(-320),
                dashboardURL: URL(string: "https://dashboard.render.com"),
                deploymentURL: URL(string: "https://img.example.com"),
                lastUpdatedAt: now
            ),
            DeploymentSnapshot(
                id: "website-digital-ocean",
                provider: .digitalOcean,
                projectName: "billing-app",
                serviceName: "worker",
                environmentName: "Live",
                branch: "main",
                commitSha: "0ff19ab",
                commitMessage: "Reconcile usage events",
                actor: "nora",
                status: .success,
                createdAt: now.addingTimeInterval(-94700),
                startedAt: now.addingTimeInterval(-94620),
                finishedAt: now.addingTimeInterval(-94410),
                duration: 210,
                dashboardURL: URL(string: "https://cloud.digitalocean.com/apps"),
                lastUpdatedAt: now
            ),
            DeploymentSnapshot(
                id: "website-heroku",
                provider: .heroku,
                projectName: "ops-console",
                environmentName: "Review",
                branch: "incident-drill",
                commitSha: "f6c44d2",
                commitMessage: "Promote review app checks",
                actor: "alex",
                status: .failed,
                createdAt: now.addingTimeInterval(-820),
                startedAt: now.addingTimeInterval(-760),
                finishedAt: now.addingTimeInterval(-710),
                duration: 50,
                dashboardURL: URL(string: "https://dashboard.heroku.com"),
                errorMessage: "Release phase command failed.",
                lastUpdatedAt: now
            )
        ]
    }
}
#endif
