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
if [[ "$build_step" == *'x86_64'* || "$build_step" == *'Universal'* ]]; then
    echo "CodeQL redundantly builds a second architecture" >&2
    exit 1
fi
if ! grep -Fq 'swift build -c release --arch arm64 --arch x86_64' \
    "$repo_root/scripts/ci/validate.sh"; then
    echo "Universal application verification is missing from CI" >&2
    exit 1
fi
echo "CodeQL build scope tests passed"
