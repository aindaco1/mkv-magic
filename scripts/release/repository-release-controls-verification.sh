#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <repository.json> <immutable-releases.json> <rulesets.json>" >&2
    exit 64
fi

repository_json="$1"
immutable_json="$2"
rulesets_json="$3"

for evidence_path in "$repository_json" "$immutable_json" "$rulesets_json"; do
    if [[ "$evidence_path" != /* || ! -f "$evidence_path" || -L "$evidence_path" ]]; then
        echo "repository release-control evidence is missing or unsafe" >&2
        exit 1
    fi
    evidence_size="$(stat -f %z "$evidence_path")"
    if [[ ! "$evidence_size" =~ ^[0-9]+$ || "$evidence_size" -gt 1048576 ]]; then
        echo "repository release-control evidence is unbounded" >&2
        exit 1
    fi
done

if ! jq -e '
    type == "object" and
    .private == false and
    .visibility == "public"
' "$repository_json" >/dev/null; then
    echo "public release requires a public open-source repository" >&2
    exit 1
fi

if ! jq -e '
    type == "object" and
    .enabled == true
' "$immutable_json" >/dev/null; then
    echo "public release requires GitHub immutable releases to be enabled" >&2
    exit 1
fi

if ! jq -e '
    type == "array" and
    any(.[];
        .target == "tag" and
        .enforcement == "active" and
        ((.bypass_actors // []) | type == "array" and length == 0) and
        ((.conditions.ref_name.include // []) |
            type == "array" and
            any(. == "refs/tags/v*" or . == "~ALL")) and
        ((.conditions.ref_name.exclude // []) |
            type == "array" and length == 0) and
        ([.rules[]?.type] |
            index("deletion") != null and
            index("non_fast_forward") != null)
    )
' "$rulesets_json" >/dev/null; then
    echo "public release requires an active no-bypass v* tag ruleset that blocks deletion and force updates" >&2
    exit 1
fi

echo "repository release controls verified"
