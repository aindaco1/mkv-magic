#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/release/dmg-layout.sh"
source "$repo_root/scripts/release/dmg-verification.sh"
release_root="${MKV_MAGIC_RELEASE_ROOT:-$repo_root/.build/release-artifacts}"
app_path="$release_root/MKV Magic.app"
if [[ ! -d "$app_path" || -L "$app_path" ]]; then
    echo "missing or unsafe assembled app" >&2
    exit 1
fi
version="$(plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "invalid packaged app version" >&2
    exit 1
fi
archive_path="$release_root/MKV-Magic-$version-universal.zip"
dmg_path="$release_root/MKV-Magic-$version-universal.dmg"
for output in \
    "$archive_path" "$dmg_path" \
    "$release_root/BUILD-METADATA.txt" "$release_root/SBOM.cdx.json"
do
    if [[ -e "$output" ]]; then
        echo "refusing to replace existing release output: $output" >&2
        exit 1
    fi
done
if [[ "${MKV_MAGIC_REQUIRE_STAPLED:-0}" == 1 ]]; then
    xcrun stapler validate "$app_path"
fi

staging="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-dmg-staging.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$staging"
}
trap cleanup EXIT
ditto --norsrc --noextattr "$app_path" "$staging/$MKV_MAGIC_DMG_APP_NAME"
ln -s "$MKV_MAGIC_DMG_APPLICATIONS_TARGET" \
    "$staging/$MKV_MAGIC_DMG_APPLICATIONS_NAME"
validate_mkv_magic_dmg_layout "$staging"

COPYFILE_DISABLE=1 ditto --norsrc --noextattr -c -k --keepParent \
    --zlibCompressionLevel 9 "$app_path" "$archive_path"
hdiutil create -quiet -volname "MKV Magic" -srcfolder "$staging" \
    -ov -format UDZO "$dmg_path"
verify_mkv_magic_dmg_checksum "$dmg_path"

"$repo_root/scripts/release/write-build-metadata.sh"
"$repo_root/scripts/release/generate-sbom.sh"
"$repo_root/scripts/release/checksum-artifacts.sh"
printf '%s\n%s\n' "$archive_path" "$dmg_path"
