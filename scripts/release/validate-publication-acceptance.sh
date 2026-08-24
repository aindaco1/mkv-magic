#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <absolute-MKV-Magic-version-universal.dmg> <vMAJOR.MINOR.PATCH>" >&2
    exit 64
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dmg_path="$1"
tag="$2"
"$repo_root/scripts/release/validate-tag-format.sh" "$tag"
version="${tag#v}"
expected_name="MKV-Magic-$version-universal.dmg"
if [[ "$dmg_path" != /* || "${dmg_path##*/}" != "$expected_name" || \
      ! -f "$dmg_path" || -L "$dmg_path" || ! -s "$dmg_path" ]]; then
    echo "publication candidate DMG is missing or unsafe" >&2
    exit 1
fi

actual_digest="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
acceptance_variables=(
    MKV_MAGIC_APPLE_SILICON_ACCEPTED_DMG_SHA256
    MKV_MAGIC_INTEL_ACCEPTED_DMG_SHA256
    MKV_MAGIC_UPDATE_ACCEPTED_DMG_SHA256
)
for variable_name in "${acceptance_variables[@]}"; do
    accepted_digest="${!variable_name:-}"
    if [[ ! "$accepted_digest" =~ ^[0-9a-f]{64}$ ]]; then
        echo "$variable_name must be an exact lowercase SHA-256 digest" >&2
        exit 1
    fi
    if [[ "$accepted_digest" != "$actual_digest" ]]; then
        echo "$variable_name does not identify the downloaded candidate DMG" >&2
        exit 1
    fi
done

if [[ "${MKV_MAGIC_PUBLICATION_CONFIRMATION:-}" != "publish-$tag" ]]; then
    echo "publication confirmation must be publish-$tag" >&2
    exit 1
fi

echo "publication acceptance is bound to downloaded candidate $tag ($actual_digest)"
