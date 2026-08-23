# Security policy

## Supported versions

Until the first public release, security fixes are made on `main`. After v1,
the latest stable release receives security support.

## Reporting

Report vulnerabilities privately through GitHub's private vulnerability
reporting for this repository. Do not include private media, credentials,
security bookmarks, or full personal paths. A minimal synthetic reproduction
and sanitized diagnostic report are preferred.

## Product boundary

MKV Magic processes selected files locally. The main application has no client
or server network entitlement. A user-initiated update check is delegated to
Sparkle's separately sandboxed services and accepts only signed updates.

The application never executes arbitrary shell text and never falls back to
tools found on `PATH`. Bundled executables, linked libraries, manifests,
licenses, architectures, signatures, and entitlements are release-gated.

## Automated analysis

CodeQL runs on every push to `main` and on a weekly schedule. While this
repository is private without GitHub Advanced Security, the workflow retains
its SARIF result as a short-lived Actions artifact instead of attempting an
unsupported code-scanning upload. It automatically uploads results to GitHub
code scanning when the repository becomes public.
