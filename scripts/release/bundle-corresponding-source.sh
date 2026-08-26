#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-verified-tool-runtime>" >&2
    exit 64
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/release/corresponding-source-verification.sh"
source "$repo_root/scripts/ci/tool-source-cache.sh"
tool_root="$1"
release_root="${MKV_MAGIC_RELEASE_ROOT:-$repo_root/.build/release-artifacts}"
cache_root="${MKV_MAGIC_TOOL_CACHE:-$repo_root/.build/tool-sources}"
app_path="$release_root/MKV Magic.app"
if [[ ! -d "$tool_root" || -L "$tool_root" || \
      ! -f "$tool_root/SOURCES.json" || -L "$tool_root/SOURCES.json" || \
      ! -d "$app_path" || -L "$app_path" || \
      ! -d "$cache_root" || -L "$cache_root" ]]; then
    echo "source bundle inputs are missing or unsafe" >&2
    exit 1
fi
"$repo_root/scripts/ci/check-tool-tree.sh" "$tool_root"
mkv_magic_verify_tool_source_cache "$cache_root" "$tool_root/SOURCES.json"

version="$(plutil -extract CFBundleShortVersionString raw -o - \
    "$app_path/Contents/Info.plist")"
metadata="$release_root/BUILD-METADATA.txt"
validate_mkv_magic_build_metadata "$metadata" "$version"
metadata_commit="$(mkv_magic_build_metadata_value "$metadata" 'Source commit')"
metadata_tree="$(mkv_magic_build_metadata_value "$metadata" 'Source tree')"
if [[ "$metadata_commit" != "$(git -C "$repo_root" rev-parse HEAD)" || \
      "$metadata_tree" != "$(git -C "$repo_root" rev-parse 'HEAD^{tree}')" ]]; then
    echo "corresponding source checkout does not match BUILD-METADATA.txt" >&2
    exit 1
fi
archive="$release_root/MKV-Magic-$version-corresponding-source.zip"
if [[ -e "$archive" ]]; then
    echo "refusing to replace source bundle: $archive" >&2
    exit 1
fi

work_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-source-bundle.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$work_root"
}
trap cleanup EXIT
bundle_root="$work_root/MKV-Magic-$version-corresponding-source"
mkdir -p "$bundle_root/dependencies"
install -m 0644 "$tool_root/SOURCES.json" "$bundle_root/SOURCES.json"

sources="$tool_root/SOURCES.json"
while IFS=$'\t' read -r relative_path expected_hash; do
    install -m 0644 "$cache_root/$relative_path" \
        "$bundle_root/dependencies/$(basename "$relative_path")"
done < <(mkv_magic_tool_source_cache_entries "$sources")

git -C "$repo_root" diff --quiet -- .
git -C "$repo_root" diff --cached --quiet -- .
git -C "$repo_root" archive --format=tar.gz \
    --prefix="mkv-magic-$version/" HEAD \
    > "$bundle_root/MKV-Magic-$version-source.tar.gz"
install -m 0644 "$repo_root/docs/CORRESPONDING_SOURCE.md" \
    "$bundle_root/README.md"

COPYFILE_DISABLE=1 ditto --norsrc --noextattr -c -k --keepParent \
    "$bundle_root" "$archive"
echo "$archive"
