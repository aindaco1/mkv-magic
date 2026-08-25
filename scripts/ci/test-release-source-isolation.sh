#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_workflow="$repo_root/.github/workflows/release.yml"
package_gate="$repo_root/scripts/ci/package-gate.sh"

source_step="$({
    awk '
        /- name: Validate source/ { capture = 1 }
        capture { print }
        /- name: Build verified Universal media runtime/ { exit }
    ' "$release_workflow"
})"
for required_fragment in \
    'MKV_MAGIC_TOOL_SOURCE_ROOT: ""' \
    'MKV_MAGIC_REQUIRE_TOOLS: "0"' \
    'run: ./scripts/ci/local-gate.sh'; do
    if [[ "$source_step" != *"$required_fragment"* ]]; then
        echo "release source gate does not isolate: $required_fragment" >&2
        exit 1
    fi
done

for required_fragment in \
    "export MKV_MAGIC_TOOL_SOURCE_ROOT=''" \
    'export MKV_MAGIC_REQUIRE_TOOLS=0'; do
    if ! grep -Fqx "$required_fragment" "$package_gate"; then
        echo "package gate does not isolate: $required_fragment" >&2
        exit 1
    fi
done

echo "release source isolation tests passed"
