# Security Policy

Chronoframe is built around one promise: originals should remain untouched. Please report any vulnerability or data-safety issue that could weaken that promise.

## Supported Versions

Security review focuses on:

- The latest published GitHub release.
- The current `main` branch.

Older releases may receive fixes when the issue is severe and the fix can be applied safely.

## Reporting A Vulnerability

Use GitHub's private vulnerability reporting flow for this repository. Please do not open a public issue for security-sensitive reports.

Helpful reports include:

- The Chronoframe version or commit.
- macOS version and storage setup.
- Whether the issue affects the native app, Python CLI, or both.
- Clear reproduction steps using synthetic files when possible.
- Any relevant log excerpt with personal paths and metadata removed.

## In Scope

- Source files being modified, moved, renamed, or deleted unexpectedly.
- Destination overwrite or collision bugs.
- Hash-verification, audit-receipt, Trash, hard-delete, or revert bypasses.
- Unsafe handling of symlinks, aliases, package contents, or unusual filesystem entries.
- Dependency or packaging vulnerabilities that affect shipped Chronoframe builds.

## Out Of Scope

- Reports that require access to another person's device, account, or private media.
- Social engineering.
- Denial-of-service cases that require intentionally enormous synthetic inputs unless they expose a realistic data-loss path.

## Response

I aim to acknowledge valid reports within a few days, confirm impact, and coordinate a fix or mitigation before public disclosure.
