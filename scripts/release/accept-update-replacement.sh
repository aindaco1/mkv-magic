#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "usage: $0 <absolute-downloaded-release-directory> <absolute-prior-MKV-Magic.app> <vMAJOR.MINOR.PATCH> <absolute-private-key-file>" >&2
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/release/downloaded-release-verification.sh"
download_root="$1"
prior_app="$2"
release_tag="$3"
private_key_file="$4"
"$repo_root/scripts/release/validate-tag-format.sh" "$release_tag"
version="${release_tag#v}"

validate_mkv_magic_downloaded_release "$download_root" "$version"
candidate_dmg="$download_root/MKV-Magic-$version-universal.dmg"
candidate_zip="$download_root/MKV-Magic-$version-universal.zip"
candidate_appcast="$download_root/appcast.xml"

host_architecture="$(uname -m)"
case "$host_architecture" in
    arm64|x86_64) ;;
    *) echo "unsupported updater acceptance architecture" >&2; exit 1 ;;
esac
MKV_MAGIC_REQUIRE_DISTRIBUTION=1 \
MKV_MAGIC_VERIFY_NATIVE_RELEASE=1 \
MKV_MAGIC_VERIFY_ARCHITECTURES="$host_architecture" \
    "$repo_root/scripts/release/verify-dmg.sh" "$candidate_dmg"
MKV_MAGIC_EXPECTED_APPCAST_PATH="$candidate_appcast" \
    "$repo_root/scripts/release/exercise-update-replacement.sh" \
        "$prior_app" "$candidate_zip" "$release_tag" "$private_key_file" 1

dmg_digest="$(shasum -a 256 "$candidate_dmg" | awk '{print $1}')"
printf 'Updater acceptance passed for %s on %s. Enter this exact candidate DMG SHA-256 in the publication workflow:\n%s\n' \
    "$release_tag" "$host_architecture" "$dmg_digest"
