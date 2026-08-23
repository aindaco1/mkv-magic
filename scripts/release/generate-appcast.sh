#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <vMAJOR.MINOR.PATCH> [private-key-file]" >&2
    exit 64
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_tag="$1"
private_key_file="${2:-}"
"$repo_root/scripts/release/validate-tag-format.sh" "$release_tag"
version="${release_tag#v}"
release_root="${MKV_MAGIC_RELEASE_ROOT:-$repo_root/.build/release-artifacts}"
archive_path="$release_root/MKV-Magic-$version-universal.zip"
notes_path="${MKV_MAGIC_RELEASE_NOTES_PATH:-$repo_root/docs/releases/$version.md}"
appcast_path="$release_root/appcast.xml"
generate_appcast="$repo_root/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -f "$archive_path" || -L "$archive_path" || \
      ! -f "$notes_path" || -L "$notes_path" || \
      ! -x "$generate_appcast" || -e "$appcast_path" ]]; then
    echo "appcast inputs or output are missing or unsafe" >&2
    exit 1
fi
if [[ -n "$private_key_file" && \
      ( "$private_key_file" != /* || ! -f "$private_key_file" || -L "$private_key_file" ) ]]; then
    echo "Sparkle private key file is missing or unsafe" >&2
    exit 1
fi
if [[ -z "$private_key_file" && -z "${SPARKLE_ED25519_PRIVATE_KEY:-}" ]]; then
    echo "Sparkle private key input is required" >&2
    exit 1
fi

work_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-appcast.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$work_root"
}
trap cleanup EXIT
install -m 0644 "$archive_path" "$work_root/MKV-Magic-$version-universal.zip"
install -m 0644 "$notes_path" "$work_root/MKV-Magic-$version-universal.md"
if [[ -n "$private_key_file" ]]; then
    "$generate_appcast" \
        --ed-key-file "$private_key_file" \
        --download-url-prefix \
            "https://github.com/aindaco1/mkv-magic/releases/download/$release_tag/" \
        --embed-release-notes \
        --full-release-notes-url \
            "https://github.com/aindaco1/mkv-magic/blob/main/CHANGELOG.md" \
        --link "https://github.com/aindaco1/mkv-magic" \
        --maximum-deltas 0 \
        -o "$work_root/appcast.xml" "$work_root"
else
    printf '%s' "$SPARKLE_ED25519_PRIVATE_KEY" | "$generate_appcast" \
        --ed-key-file - \
        --download-url-prefix \
            "https://github.com/aindaco1/mkv-magic/releases/download/$release_tag/" \
        --embed-release-notes \
        --full-release-notes-url \
            "https://github.com/aindaco1/mkv-magic/blob/main/CHANGELOG.md" \
        --link "https://github.com/aindaco1/mkv-magic" \
        --maximum-deltas 0 \
        -o "$work_root/appcast.xml" "$work_root"
fi
for required in \
    "releases/download/$release_tag/MKV-Magic-$version-universal.zip" \
    "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" \
    'sparkle:edSignature=' \
    '<!-- sparkle-signatures:'
do
    if ! grep -Fq "$required" "$work_root/appcast.xml"; then
        echo "generated appcast is missing: $required" >&2
        exit 1
    fi
done
install -m 0644 "$work_root/appcast.xml" "$appcast_path"
echo "$appcast_path"
