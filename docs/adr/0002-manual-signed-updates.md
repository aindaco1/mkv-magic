# ADR 0002: Manual signed updates without main-app networking

- Status: Accepted
- Date: 2026-08-22

## Context

The public app needs a trustworthy update path without turning the media
application into a general network client.

## Decision

Pin an exact reviewed Sparkle 2 release. Expose `Check for Updates…` as a
user-initiated action. Disable automatic checks and automatic installation.
The main app carries no network entitlement; Sparkle's sandboxed Downloader and
Installer services own update networking.

Update archives and the appcast require a dedicated MKV Magic Ed25519 key.
Release automation signs nested Sparkle services inside out and generates the
feed only from the final notarized ZIP.

Release acceptance uses Sparkle's external updater driver from that same pinned
source revision. It replaces only a temporary copy of the prior app from a
loopback-only feed whose archive signature must match the downloaded draft
appcast. No alternate-feed control is compiled into the shipped application.

## Consequences

Update checks are explicit and cryptographically authenticated. The dedicated
private key becomes release-critical offline material and must never enter Git
or ordinary CI. CI exercises real replacement with a one-time disposable key
and proves that a mismatched key is rejected without changing the prior build.
