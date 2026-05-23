# AI Contributor Guide

This guide is for contributors using AI coding agents to extend DeployBar. Keep changes small, local-first, and easy to review.

## Project Shape

DeployBar is a native macOS menu bar app for monitoring cloud deployment status.

- Language and tooling: Swift 6, Swift Package Manager, SwiftUI, and AppKit.
- Minimum platform: macOS 13.
- Runtime model: no Electron shell, no backend service, no hosted credential sync.
- Trust model: provider tokens stay in macOS Keychain; non-secret settings stay in local JSON.

## Repository Map

- `Package.swift`: SwiftPM package, targets, and platform settings.
- `Sources/DeployBarCore`: provider APIs, status models, settings, refresh coordination, redaction, and parsing logic.
- `Sources/DeployBar`: macOS app shell, menu bar integration, SwiftUI views, notifications, and resources.
- `Tests/DeployBarCoreTests`: focused tests for parsing, mapping, provider requests, redaction, monitored targets, and refresh behavior.
- `docs/index.html`: static marketing/documentation page.
- `docs/assets`: screenshots, icons, provider logos, and website assets.
- `Scripts/package_app.sh`: local `.app` bundle packaging.

## Useful Commands

```bash
swift build
swift test
swift run DeployBar
./Scripts/package_app.sh
open .build/DeployBar.app
```

Run `swift test` for core/provider changes. For app UI changes, also run or package the app and manually check the affected surface.

## How To Work With An AI Agent

Give the agent a concrete goal and the relevant surface area. Good requests are scoped to one provider, one view, one parser, or one behavior.

Before editing, the agent should inspect the current code path with `rg`, `sed`, or SwiftPM test files. Do not ask it to rewrite broad subsystems unless the reason and migration plan are explicit.

After editing, the agent should report:

- files changed
- commands run
- tests that passed or could not run
- any behavior that still needs manual verification

## Architecture Rules

- Keep provider-specific API details inside the provider implementation.
- Keep shared status behavior in `DeployBarCore` models, mappers, and refresh coordination.
- Keep SwiftUI/AppKit app state in `Sources/DeployBar`, especially `DeploymentStore` and `Views`.
- Preserve Swift 6 strict concurrency. Prefer explicit `Sendable` models and keep UI mutation on `@MainActor`.
- Prefer small structs and focused helpers over broad abstractions.

## Adding Or Updating Providers

Provider work should stay provider-local unless shared behavior is genuinely needed.

1. Add or update the `ProviderID` case and target behavior in `Sources/DeployBarCore/DeploymentModels.swift` and `Sources/DeployBarCore/Provider.swift`.
2. Add or update the `ProviderDescriptor` and provider order in `Sources/DeployBarCore/ProviderRegistry.swift`.
3. Implement `DeploymentProvider` in a provider-specific file under `Sources/DeployBarCore`.
4. Map upstream states into `DeploymentStatus` and `DeploymentSeverity` through existing status helpers.
5. Register the provider in `Sources/DeployBar/DeploymentStore.swift`.
6. Add provider-specific tests for request construction, response parsing, status mapping, and failure behavior.

If a provider requires discovery, keep discovery models and parsing close to that provider, and make the Settings UI expose only the minimum fields users need.

## Security And Privacy

DeployBar is local-first. AI-generated changes must preserve that contract.

- Never write provider tokens to JSON settings, logs, screenshots, diagnostics, or tests.
- Use Keychain-backed token storage through the existing token store paths.
- Redact sensitive strings before showing diagnostics.
- Avoid adding telemetry, hosted sync, analytics, crash uploaders, or background network calls unrelated to provider polling.
- Tests must use fixtures or mock clients, not real user credentials.

## UI Guidance

The app UI should stay compact, native, and quiet. It is a menu bar utility, not a dashboard website.

- Match existing SwiftUI view structure and spacing before adding new visual patterns.
- Keep provider settings ergonomic for repeated edits.
- Surface diagnostics without leaking secrets.
- Avoid large decorative UI changes unless the task is explicitly visual design work.

For `docs/index.html`, keep the page static and asset paths relative to `docs/`.

## Review Checklist

Before opening a pull request:

- Run `swift test` when Swift code changed.
- Run `swift build` when app or package structure changed.
- Confirm no secrets, tokens, or local machine paths were introduced.
- Confirm new providers or parsers have focused tests.
- Keep README, privacy, security, and website docs in sync when user-facing behavior changes.

## Good AI Prompts For This Repo

```text
Add support for <provider> deployments. Keep it provider-local, add tests for request construction and parsing, and preserve the Keychain-only token model.
```

```text
Refactor <view/provider/helper> for readability without changing behavior. Run existing tests and explain any behavior you intentionally preserved.
```

```text
Investigate why <status/provider/setting> behaves this way. Read the relevant files first, summarize the current path, then propose the smallest fix.
```
