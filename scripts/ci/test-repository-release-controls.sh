#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-release-controls-test.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

repository_json="$test_root/repository.json"
immutable_json="$test_root/immutable.json"
rulesets_json="$test_root/rulesets.json"
validator="$repo_root/scripts/release/repository-release-controls-verification.sh"
release_workflow="$repo_root/.github/workflows/release.yml"

jq -n '{private: false, visibility: "public"}' > "$repository_json"
jq -n '{enabled: true, enforced_by_owner: false}' > "$immutable_json"
jq -n '[{
    id: 42,
    target: "tag",
    enforcement: "active",
    bypass_actors: [],
    conditions: {
        ref_name: {
            include: ["refs/tags/v*"],
            exclude: []
        }
    },
    rules: [
        {type: "deletion"},
        {type: "non_fast_forward"}
    ]
}]' > "$rulesets_json"

run_valid() {
    "$validator" "$repository_json" "$immutable_json" "$rulesets_json" \
        >/dev/null
}

expect_rejection() {
    local description="$1"
    local rejected_path="$2"
    shift 2
    if "$validator" "$@" >/dev/null 2>&1; then
        echo "release-control verifier accepted $description at $rejected_path" >&2
        exit 1
    fi
}

run_valid

# This is intentionally a literal workflow source fragment.
# shellcheck disable=SC2016
if ! grep -Fq 'GH_TOKEN: ${{ secrets.RELEASE_CONTROLS_READ_TOKEN }}' \
    "$release_workflow"; then
    echo "release controls are not using the narrow environment credential" >&2
    exit 1
fi

linked_repository="$test_root/linked-repository.json"
ln -s "$repository_json" "$linked_repository"
expect_rejection "symbolic-link evidence" "$linked_repository" \
    "$linked_repository" "$immutable_json" "$rulesets_json"

oversized_repository="$test_root/oversized-repository.json"
dd if=/dev/zero of="$oversized_repository" bs=1048577 count=1 2>/dev/null
expect_rejection "oversized evidence" "$oversized_repository" \
    "$oversized_repository" "$immutable_json" "$rulesets_json"

private_repository="$test_root/private-repository.json"
jq '.private = true | .visibility = "private"' \
    "$repository_json" > "$private_repository"
expect_rejection "a private repository" "$private_repository" \
    "$private_repository" "$immutable_json" "$rulesets_json"

mutable_releases="$test_root/mutable-releases.json"
jq '.enabled = false' "$immutable_json" > "$mutable_releases"
expect_rejection "mutable releases" "$mutable_releases" \
    "$repository_json" "$mutable_releases" "$rulesets_json"

inactive_ruleset="$test_root/inactive-ruleset.json"
jq '.[0].enforcement = "evaluate"' "$rulesets_json" > "$inactive_ruleset"
expect_rejection "an inactive tag ruleset" "$inactive_ruleset" \
    "$repository_json" "$immutable_json" "$inactive_ruleset"

bypass_ruleset="$test_root/bypass-ruleset.json"
jq '.[0].bypass_actors = [{actor_id: 5, actor_type: "RepositoryRole"}]' \
    "$rulesets_json" > "$bypass_ruleset"
expect_rejection "a bypassable tag ruleset" "$bypass_ruleset" \
    "$repository_json" "$immutable_json" "$bypass_ruleset"

deletable_ruleset="$test_root/deletable-ruleset.json"
jq '.[0].rules = [{type: "non_fast_forward"}]' \
    "$rulesets_json" > "$deletable_ruleset"
expect_rejection "a deletable release tag" "$deletable_ruleset" \
    "$repository_json" "$immutable_json" "$deletable_ruleset"

movable_ruleset="$test_root/movable-ruleset.json"
jq '.[0].rules = [{type: "deletion"}]' \
    "$rulesets_json" > "$movable_ruleset"
expect_rejection "a force-updatable release tag" "$movable_ruleset" \
    "$repository_json" "$immutable_json" "$movable_ruleset"

wrong_pattern="$test_root/wrong-pattern.json"
jq '.[0].conditions.ref_name.include = ["refs/tags/beta-*"]' \
    "$rulesets_json" > "$wrong_pattern"
expect_rejection "a ruleset that misses version tags" "$wrong_pattern" \
    "$repository_json" "$immutable_json" "$wrong_pattern"

echo "repository release-control tests passed"
