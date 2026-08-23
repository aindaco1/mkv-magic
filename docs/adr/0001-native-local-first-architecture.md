# ADR 0001: Native local-first architecture

- Status: Accepted
- Date: 2026-08-22

## Context

MKV Magic must remain lightweight on Intel Macs while coordinating bundled
FFmpeg and MKVToolNix processes, durable workflows, verification, and a simple
macOS interface.

## Decision

Use a package-first Swift 6 architecture with an AppKit application shell.
Keep domain, planning, system execution, media adapters, and UI in separate
targets. Process media locally; do not require accounts, telemetry, uploads,
web-hosted UI, or LLMs.

Runtime executables are packaged, pinned, signed, and resolved by exact path.
Development may opt into an explicit tool root, but there is no `PATH` fallback.

## Consequences

The app has a small native baseline and testable policy layers. We accept the
work of building and signing Universal sidecars and writing AppKit components
instead of adopting a web wrapper or a system-installed tool dependency.
