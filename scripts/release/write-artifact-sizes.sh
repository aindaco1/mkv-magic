#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_root="${MKV_MAGIC_RELEASE_ROOT:-$repo_root/.build/release-artifacts}"
output="$release_root/ARTIFACT-SIZES.json"
if [[ ! -d "$release_root" || -L "$release_root" || -e "$output" ]]; then
    echo "artifact size inputs or output are unsafe" >&2
    exit 1
fi
temporary="$(mktemp "${TMPDIR:-/tmp}/mkv-magic-sizes.XXXXXX")"
cleanup() {
    /bin/rm -f -- "$temporary" "$temporary.next"
}
trap cleanup EXIT
jq -n '{schema: "mkv-magic-artifact-sizes-v1", artifacts: []}' > "$temporary"

count=0
while IFS= read -r file_path; do
    name="$(basename "$file_path")"
    bytes="$(stat -f '%z' "$file_path")"
    hash="$(shasum -a 256 "$file_path" | awk '{print $1}')"
    jq --arg name "$name" --argjson bytes "$bytes" --arg hash "$hash" \
        '.artifacts += [{name: $name, bytes: $bytes, sha256: $hash}]' \
        "$temporary" > "$temporary.next"
    mv "$temporary.next" "$temporary"
    count=$((count + 1))
done < <(
    find "$release_root" -maxdepth 1 -type f ! -name 'SHA256SUMS' \
        ! -name 'ARTIFACT-SIZES.json' -print | sort
)
if [[ "$count" -lt 8 ]]; then
    echo "release does not contain enough artifacts for size evidence" >&2
    exit 1
fi
jq -S . "$temporary" > "$output"
chmod 0644 "$output"
