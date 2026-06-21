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
- Whether the issue affects the native macOS app, SwiftPM CLI (ChronoframeCLI), or both.
- Clear reproduction steps using synthetic files when possible.
- Any relevant log excerpt with personal paths and metadata removed.

## In Scope

- Source files being modified, moved, renamed, or deleted unexpectedly.
- Destination overwrite or collision bugs.
- Hash-verification, audit-receipt, Trash, hard-delete, or revert bypasses.
- Preview/executor divergence, stale-plan deletion, quarantine escape, pair-unit rollback, or recovery-journal omissions.
- Concurrent app, CLI, App Intent, scan, commit, revert, or reorganize operations reaching the same destination despite the operation lock.
- Interrupted-run recovery that treats an inaccessible path as missing, mutates ambiguous state, or loses the ability to account for a moved file.
- Unsafe handling of symlinks, aliases, package contents, or unusual filesystem entries.
- Security-scoped bookmark, App Sandbox, external-volume, or Trash behavior that weakens the same guarantees in a distributed build.
- Dependency or packaging vulnerabilities that affect shipped Chronoframe builds.

## Out Of Scope

- Reports that require access to another person's device, account, or private media.
- Social engineering.
- Denial-of-service cases that require intentionally enormous synthetic inputs unless they expose a realistic data-loss path.

## Response

I aim to acknowledge valid reports within a few days, confirm impact, and coordinate a fix or mitigation before public disclosure.

For the intended safety model and artifact map, see
[Safety and Recovery](docs/SAFETY_AND_RECOVERY.md). Preserve pending receipts,
journals, quarantine paths, and the destination cache when collecting evidence
from an interrupted run.
