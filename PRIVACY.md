# Privacy Policy

DeployBar is designed to be local-first. The app has no DeployBar backend service and does not collect telemetry.

## What DeployBar stores

DeployBar stores:

- provider API tokens in macOS Keychain under service `com.deploybar.tokens`
- non-secret settings as local JSON under `~/Library/Application Support/DeployBar/settings.json`
- provider account metadata, token references, refresh cadence, and monitored target configuration in local settings

DeployBar does not intentionally write provider API tokens to JSON settings, logs, diagnostics, or exported text.

## What leaves your Mac

DeployBar connects directly from your Mac to the deployment providers you configure, such as Vercel, Railway, Netlify, Render, Cloudflare Pages, DigitalOcean, Heroku, GitHub, and GitLab.

Those provider API requests may include:

- your provider API token or access token in the provider's required authentication header
- project, repository, service, environment, branch, team, account, or deployment identifiers needed to fetch deployment status
- a custom GitLab API base URL if you configure a self-managed GitLab instance

DeployBar does not proxy this traffic through a DeployBar-operated service.

## Notifications

DeployBar may request macOS notification permission to alert you when deployments become ready, fail, cancel, or are removed. Notification delivery is handled by macOS.

## Permissions

DeployBar does not require Full Disk Access, Accessibility, Screen Recording, Contacts, Calendar, Location, or Microphone permissions.

## Diagnostics

DeployBar shows provider refresh issues and diagnostics locally. Diagnostic text should pass through token redaction before display.

## Project website

The DeployBar website is a static site. It may be hosted through GitHub Pages and may load static provider logo assets from a public CDN. The website is separate from the macOS app and is not required for the app to run.

## Changes

Privacy behavior may change as the project evolves. Material changes should be reflected in this file before release.
