#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
    echo "usage: $0 <absolute-runtime-directory> <absolute-source-cache> <absolute-output.tar.gz> <owner/repository> <commit> <run-id> <run-attempt>" >&2
    exit 64
fi
tool_root="$1"
cache_root="$2"
archive="$3"
repository="$4"
commit="$5"
run_id="$6"
run_attempt="$7"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/ci/tool-source-cache.sh"

if [[ "$tool_root" != /* || "$cache_root" != /* || "$archive" != /* || \
      ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ || \
      ! "$commit" =~ ^[a-f0-9]{40}$ || \
      ! "$run_id" =~ ^[1-9][0-9]*$ || ! "$run_attempt" =~ ^[1-9][0-9]*$ ]]; then
    echo "invalid CI runtime artifact input" >&2
    exit 64
fi
if [[ -e "$archive" || -L "$archive" || ! -d "$(dirname "$archive")" || \
      -L "$(dirname "$archive")" ]]; then
    echo "CI runtime artifact output must be an absent file in a safe directory" >&2
    exit 1
fi
if [[ "$(git -C "$repo_root" rev-parse HEAD)" != "$commit" ]] || \
    ! git -C "$repo_root" diff --quiet -- . || \
    ! git -C "$repo_root" diff --cached --quiet -- .; then
    echo "CI runtime artifact checkout is not the exact clean source commit" >&2
    exit 1
fi

"$repo_root/scripts/ci/check-tool-tree.sh" "$tool_root"
mkv_magic_verify_tool_source_cache "$cache_root" "$tool_root/SOURCES.json"

work_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-ci-runtime-package.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$work_root"
}
trap cleanup EXIT
bundle_root="$work_root/mkv-magic-ci-runtime"
mkdir "$bundle_root"
ditto --norsrc --noextattr "$tool_root" "$bundle_root/runtime"
mkv_magic_copy_tool_source_cache \
    "$cache_root" "$tool_root/SOURCES.json" "$bundle_root/sources"

runtime_manifest_hash="$(
    shasum -a 256 "$bundle_root/runtime/SOURCES.json" | awk '{print $1}'
)"
source_index_hash="$({
    mkv_magic_tool_source_cache_entries "$bundle_root/runtime/SOURCES.json"
} | shasum -a 256 | awk '{print $1}')"
build_script_hash="$(
    shasum -a 256 "$repo_root/scripts/tools/build-runtime.sh" | awk '{print $1}'
)"
xcode_version="$(xcodebuild -version | head -1)"
jq -n \
    --arg repository "$repository" \
    --arg commit "$commit" \
    --argjson runID "$run_id" \
    --argjson runAttempt "$run_attempt" \
    --arg xcodeVersion "$xcode_version" \
    --arg runtimeManifestSHA256 "$runtime_manifest_hash" \
    --arg sourceIndexSHA256 "$source_index_hash" \
    --arg buildScriptSHA256 "$build_script_hash" \
    '{
      schema: "mkv-magic-ci-runtime-v1",
      repository: $repository,
      commit: $commit,
      workflow: ".github/workflows/ci.yml",
      runID: $runID,
      runAttempt: $runAttempt,
      runner: "github-hosted",
      xcodeVersion: $xcodeVersion,
      runtimeManifestSHA256: $runtimeManifestSHA256,
      sourceIndexSHA256: $sourceIndexSHA256,
      buildScriptSHA256: $buildScriptSHA256
    }' > "$bundle_root/metadata.json"
chmod 0644 "$bundle_root/metadata.json"

"$repo_root/scripts/ci/check-tool-tree.sh" "$bundle_root/runtime"
mkv_magic_verify_tool_source_cache \
    "$bundle_root/sources" "$bundle_root/runtime/SOURCES.json"
COPYFILE_DISABLE=1 tar -czf "$archive" -C "$work_root" mkv-magic-ci-runtime
chmod 0644 "$archive"
echo "$archive"
