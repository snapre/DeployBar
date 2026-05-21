# Security Policy

DeployBar is a local-first macOS app. The app does not run a backend service, does not proxy provider API traffic, and stores provider tokens in the user's macOS Keychain.

## Supported versions

DeployBar is currently pre-release software. Security fixes are applied to the `main` branch and will be included in future tagged releases.

## Reporting a vulnerability

Please report security issues privately.

- Preferred: use GitHub's private vulnerability reporting flow for this repository, if available.
- If private reporting is not available, open a minimal GitHub issue that says a security report is available, without posting tokens, exploit details, logs, screenshots, or personally identifiable information.

We aim to acknowledge reports within 7 days. Fix timing depends on severity, reproducibility, and whether the issue affects local credentials, provider tokens, or remote code execution.

## Scope

Security-sensitive areas include:

- Keychain token storage and retrieval
- token redaction in logs, diagnostics, settings, and UI
- provider API request construction and authentication headers
- handling of custom GitLab API base URLs
- app packaging, signing, and update/distribution workflows

Out of scope:

- provider-side outages or API behavior outside DeployBar's control
- issues requiring physical access to an unlocked Mac
- reports based only on the app being able to read tokens that the user explicitly saved into DeployBar
- social engineering, denial-of-service against third-party providers, or automated high-volume probing

## No bug bounty

DeployBar does not currently run a paid vulnerability bounty program.

## Disclosure

Please give maintainers a reasonable opportunity to investigate and release a fix before public disclosure. We will credit reporters when requested, unless anonymity is preferred.
