#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "usage: $0 <owner/repository> <commit> <absolute-runtime-destination> <absolute-source-cache-destination>" >&2
    exit 64
fi
repository="$1"
commit="$2"
tool_destination="$3"
cache_destination="$4"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/ci/tool-source-cache.sh"

if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ || \
      ! "$commit" =~ ^[a-f0-9]{40}$ || \
      "$tool_destination" != /* || "$cache_destination" != /* || \
      -e "$tool_destination" || -L "$tool_destination" || \
      -e "$cache_destination" || -L "$cache_destination" ]]; then
    echo "invalid verified CI runtime destination" >&2
    exit 64
fi
for required_command in gh jq python3 shasum; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "missing required CI runtime restore command: $required_command" >&2
        exit 1
    fi
done

required_run() {
    local workflow="$1"
    local runs
    runs="$(
        gh run list --repo "$repository" --workflow "$workflow" \
            --commit "$commit" --branch main --event push --status success \
            --limit 10 \
            --json databaseId,attempt,conclusion,event,headBranch,headSha,status
    )"
    jq -er --arg commit "$commit" '
        [ .[] | select(
            .headSha == $commit and .headBranch == "main" and
            .event == "push" and .status == "completed" and
            .conclusion == "success" and
            (.databaseId | type == "number") and
            (.attempt | type == "number")
        ) ]
        | if length == 0 then error("missing exact successful workflow run")
          else sort_by(.databaseId) | last | [.databaseId, .attempt] | @tsv
          end
    ' <<< "$runs"
}

ci_run="$(required_run CI)"
codeql_run="$(required_run CodeQL)"
ci_run_id="${ci_run%%$'\t'*}"
ci_run_attempt="${ci_run#*$'\t'}"
codeql_run_id="${codeql_run%%$'\t'*}"

work_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-ci-runtime-restore.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$work_root"
}
trap cleanup EXIT
artifact_name="mkv-magic-verified-runtime-$commit"
gh run download "$ci_run_id" --repo "$repository" \
    --name "$artifact_name" --dir "$work_root/download"
archive="$work_root/download/mkv-magic-ci-runtime-$commit.tar.gz"
if [[ ! -f "$archive" || -L "$archive" ]]; then
    echo "exact CI runtime artifact is missing or unsafe" >&2
    exit 1
fi

gh attestation verify "$archive" \
    --repo "$repository" \
    --signer-workflow "github.com/$repository/.github/workflows/ci.yml" \
    --source-ref refs/heads/main \
    --source-digest "$commit" \
    --deny-self-hosted-runners >/dev/null

extract_root="$work_root/extracted"
python3 "$repo_root/scripts/tools/extract-ci-runtime.py" \
    "$archive" "$extract_root"
bundle_root="$extract_root/mkv-magic-ci-runtime"
metadata="$bundle_root/metadata.json"
runtime="$bundle_root/runtime"
sources="$bundle_root/sources"
if [[ ! -f "$metadata" || -L "$metadata" ]] || ! jq -e \
    --arg repository "$repository" \
    --arg commit "$commit" \
    --argjson runID "$ci_run_id" \
    --argjson runAttempt "$ci_run_attempt" '
      (keys | sort) == [
        "buildScriptSHA256", "commit", "repository", "runAttempt", "runID",
        "runner", "runtimeManifestSHA256", "schema", "sourceIndexSHA256",
        "workflow", "xcodeVersion"
      ] and
      .schema == "mkv-magic-ci-runtime-v1" and
      .repository == $repository and .commit == $commit and
      .workflow == ".github/workflows/ci.yml" and
      .runID == $runID and .runAttempt == $runAttempt and
      .runner == "github-hosted" and .xcodeVersion == "Xcode 26.3" and
      ([.runtimeManifestSHA256, .sourceIndexSHA256, .buildScriptSHA256]
        | all(type == "string" and test("^[a-f0-9]{64}$")))
    ' "$metadata" >/dev/null; then
    echo "CI runtime provenance metadata is invalid" >&2
    exit 1
fi

runtime_manifest_hash="$(shasum -a 256 "$runtime/SOURCES.json" | awk '{print $1}')"
source_index_hash="$({
    mkv_magic_tool_source_cache_entries "$runtime/SOURCES.json"
} | shasum -a 256 | awk '{print $1}')"
build_script_hash="$(
    shasum -a 256 "$repo_root/scripts/tools/build-runtime.sh" | awk '{print $1}'
)"
if [[ "$runtime_manifest_hash" != "$(jq -r '.runtimeManifestSHA256' "$metadata")" || \
      "$source_index_hash" != "$(jq -r '.sourceIndexSHA256' "$metadata")" || \
      "$build_script_hash" != "$(jq -r '.buildScriptSHA256' "$metadata")" ]]; then
    echo "CI runtime provenance does not match the release source" >&2
    exit 1
fi
"$repo_root/scripts/ci/check-tool-tree.sh" "$runtime"
mkv_magic_verify_tool_source_cache "$sources" "$runtime/SOURCES.json"

mkdir -p "$(dirname "$tool_destination")" "$(dirname "$cache_destination")"
mv "$runtime" "$tool_destination"
mv "$sources" "$cache_destination"
"$repo_root/scripts/tools/verify-runtime-source-cache.sh" \
    "$cache_destination" "$tool_destination"
echo "restored verified CI runtime from CI run $ci_run_id and CodeQL run $codeql_run_id"
