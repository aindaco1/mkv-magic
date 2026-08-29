#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$repo_root/.github/workflows/security.yml"
build_step="$({
    awk '
        /- name: Build analyzed ARM64 application/ { capture = 1 }
        capture { print }
        /- name: Analyze/ { exit }
    ' "$workflow"
})"
if [[ "$build_step" != *'swift build -c release --arch arm64'* ]]; then
    echo "CodeQL does not build the analyzed ARM64 application" >&2
    exit 1
fi
if [[ "$build_step" != *'-Xswiftc -Onone'* ]]; then
    echo "CodeQL does not disable unnecessary optimizer work" >&2
    exit 1
fi
if [[ "$build_step" == *'x86_64'* || "$build_step" == *'Universal'* ]]; then
    echo "CodeQL redundantly builds a second architecture" >&2
    exit 1
fi
if [[ "$build_step" == *'-c debug'* || "$build_step" == *'--configuration debug'* ]]; then
    echo "CodeQL changed away from the production Release compilation graph" >&2
    exit 1
fi
if grep -Eq '(^|[[:space:]])uses:[[:space:]]+actions/cache@' "$workflow"; then
    echo "CodeQL must compile source instead of restoring mutable build objects" >&2
    exit 1
fi
if ! grep -Fq 'Retain SARIF for extraction regression evidence' "$workflow"; then
    echo "CodeQL does not retain extraction regression evidence" >&2
    exit 1
fi
if ! grep -Fq 'output: codeql-results' "$workflow" ||
    ! grep -Fq 'path: codeql-results/*.sarif' "$workflow"; then
    echo "CodeQL SARIF evidence is not retained from a workspace-local path" >&2
    exit 1
fi
if ! grep -Fq 'swift build -c release --arch arm64 --arch x86_64' \
    "$repo_root/scripts/ci/validate.sh"; then
    echo "Universal application verification is missing from CI" >&2
    exit 1
fi
echo "CodeQL build scope tests passed"
