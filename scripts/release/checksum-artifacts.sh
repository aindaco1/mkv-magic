#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_root="${MKV_MAGIC_RELEASE_ROOT:-$repo_root/.build/release-artifacts}"
output="$release_root/SHA256SUMS"
if [[ ! -d "$release_root" || -L "$release_root" ]]; then
    echo "missing or unsafe release root" >&2
    exit 1
fi
temporary="$(mktemp "${TMPDIR:-/tmp}/mkv-magic-checksums.XXXXXX")"
cleanup() {
    /bin/rm -f -- "$temporary"
}
trap cleanup EXIT

files=()
for name in \
    MKV-Magic-*.zip \
    MKV-Magic-*.dmg \
    appcast.xml \
    Package.resolved \
    THIRD-PARTY-NOTICES.md \
    SUPPORTED-SYSTEMS.md \
    TROUBLESHOOTING.md \
    BUILD-METADATA.txt \
    SBOM.cdx.json \
    ARTIFACT-SIZES.json \
    MKV-Magic-*-corresponding-source.zip \
    NOTARIZATION-APP.json \
    NOTARIZATION-DMG.json
do
    for candidate in "$release_root"/$name; do
        if [[ -f "$candidate" && ! -L "$candidate" ]]; then
            files+=("$candidate")
        fi
    done
done
if [[ "${#files[@]}" -lt 4 ]]; then
    echo "release does not contain enough checksum inputs" >&2
    exit 1
fi
for file_path in "${files[@]}"; do
    hash="$(shasum -a 256 "$file_path" | awk '{print $1}')"
    printf '%s  %s\n' "$hash" "$(basename "$file_path")" >> "$temporary"
done
sort -u "$temporary" > "$output"
chmod 0644 "$output"
