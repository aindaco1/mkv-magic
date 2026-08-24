#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "usage: $0 <owner/repository>" >&2
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
repository="$1"
control_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-release-controls.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$control_root"
}
trap cleanup EXIT

repository_json="$control_root/repository.json"
immutable_json="$control_root/immutable-releases.json"
ruleset_list_json="$control_root/ruleset-list.json"
rulesets_json="$control_root/rulesets.json"

gh api --method GET "repos/$repository" > "$repository_json"
gh api --method GET "repos/$repository/immutable-releases" > "$immutable_json"
gh api --method GET "repos/$repository/rulesets?per_page=100" > "$ruleset_list_json"

ruleset_files=()
while IFS= read -r ruleset_id; do
    if [[ ! "$ruleset_id" =~ ^[1-9][0-9]*$ ]]; then
        echo "repository returned an invalid ruleset identifier" >&2
        exit 1
    fi
    ruleset_file="$control_root/ruleset-$ruleset_id.json"
    gh api --method GET "repos/$repository/rulesets/$ruleset_id" > "$ruleset_file"
    ruleset_files+=("$ruleset_file")
done < <(jq -r '.[]?.id' "$ruleset_list_json")

if [[ ${#ruleset_files[@]} -eq 0 ]]; then
    printf '[]\n' > "$rulesets_json"
else
    jq -s '.' "${ruleset_files[@]}" > "$rulesets_json"
fi

"$repo_root/scripts/release/repository-release-controls-verification.sh" \
    "$repository_json" "$immutable_json" "$rulesets_json"
