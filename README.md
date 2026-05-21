# DeployBar

DeployBar is a local-first macOS menu bar app for watching cloud deployment status across providers such as Vercel and Railway.

The project is intentionally native: Swift 6, Swift Package Manager, SwiftUI for popover/settings surfaces, and AppKit `NSStatusItem` for menu bar integration. There is no Electron shell and no backend service.

## Current state

This repository currently contains the first scaffold:

- menu bar app shell with no Dock icon when packaged as an app bundle
- SwiftUI popover showing provider-agnostic deployment snapshots
- settings UI for refresh cadence, mock data, and provider token entry
- Keychain token wrapper using service `com.deploybar.tokens`
- local JSON settings store for non-secret settings
- mock provider with queued/building/ready/failed snapshots
- Vercel REST provider for deployment listing
- Railway GraphQL provider for deployment listing
- Railway read-only discovery for projects, services, and environments
- tests for status mapping, response parsing, provider requests, redaction, and stale refresh behavior

The next implementation phase is richer account discovery, provider diagnostics, and optional failure log tailing.

## Development

Build and test:

```bash
swift build
swift test
```

Run directly from SwiftPM:

```bash
swift run DeployBar
```

Package a local `.app` bundle with `LSUIElement` enabled:

```bash
./Scripts/package_app.sh
open .build/DeployBar.app
```

## Configuration

Non-secret settings are stored as JSON under:

```text
~/Library/Application Support/DeployBar/settings.json
```

API tokens are stored only in Keychain:

```text
service: com.deploybar.tokens
account: <provider>:<token-reference>
```

Provider identity, token references, and monitored targets are stored per account so Vercel and Railway credentials stay isolated.

## Provider plan

### Vercel

Data source: official Vercel REST API, `GET https://api.vercel.com/v6/deployments`.

Confirmed parameters include `teamId`, `slug`, `projectId`, `target`, `branch`, `sha`, `state`, and pagination fields. DeployBar maps `QUEUED`, `INITIALIZING`, `BUILDING`, `READY`, `ERROR`, and `CANCELED` into the unified status model.

### Railway

Data source: Railway Public GraphQL API, `POST https://backboard.railway.com/graphql/v2`.

Confirmed shape uses Relay-style pagination for `deployments(input:, first:, after:)`. Railway account/workspace tokens use `Authorization: Bearer <token>`, while project tokens use `Project-Access-Token: <token>`. Railway targets require at least a service ID and environment ID.

DeployBar can discover Railway resources from Settings. Account/workspace tokens can fill projects, services, and environments. Project tokens can reliably reveal project/environment scope via `projectToken`; service discovery may still require manual service ID entry depending on token permissions.

## Extending providers

Additions should stay provider-local:

1. Add a `ProviderID` case and `ProviderDescriptor`.
2. Implement `DeploymentProvider`.
3. Add provider-specific response models/parser.
4. Register the provider in `DeploymentStore`.
5. Add focused tests for status mapping, parsing, request headers, and failure behavior.

## Privacy

DeployBar is local-first. Tokens are never written to JSON settings, logs, or diagnostic UI. Debug text should pass through redaction before display. The app does not request Full Disk Access, Accessibility, or Screen Recording.

## Attribution

DeployBar is inspired by the product shape and provider architecture ideas in [steipete/CodexBar](https://github.com/steipete/CodexBar), which is MIT licensed. No CodexBar source code is copied in this scaffold.
