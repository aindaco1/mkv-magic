#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_source="$repo_root/Sources/MKVMagic"

set +e
violations="$(
    rg -n --glob '*.swift' --glob '!UserFacingErrorPresentation.swift' \
        'error\.localizedDescription' "$app_source"
)"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
    echo "user-facing technical error bypassed UserFacingErrorPresentation:" >&2
    echo "$violations" >&2
    exit 1
fi
if [[ "$status" -ne 1 ]]; then
    exit "$status"
fi
