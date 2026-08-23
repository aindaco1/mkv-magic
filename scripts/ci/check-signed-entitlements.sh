#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-MKV-Magic.app>" >&2
    exit 64
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_app="$1"
if [[ ! -d "$source_app" || -L "$source_app" ]]; then
    echo "missing or unsafe signed app" >&2
    exit 1
fi

verification_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-signature.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$verification_root"
}
trap cleanup EXIT
app_path="$verification_root/MKV Magic.app"
ditto --norsrc --noextattr "$source_app" "$app_path"
xattr -cr "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

compare_entitlements() {
    local code_path="$1"
    local expected_plist="$2"
    local label="$3"
    local embedded="$verification_root/$label-embedded.plist"
    local embedded_json="$verification_root/$label-embedded.json"
    local expected_json="$verification_root/$label-expected.json"
    codesign --display --entitlements "$embedded" --xml "$code_path" >/dev/null
    plutil -convert json -o "$embedded_json" "$embedded"
    plutil -convert json -o "$expected_json" "$expected_plist"
    if [[ "$(jq -cS . "$embedded_json")" != "$(jq -cS . "$expected_json")" ]]; then
        echo "$label signed entitlements differ from reviewed policy" >&2
        exit 1
    fi
}

compare_entitlements \
    "$app_path" "$repo_root/Configuration/MKVMagic.entitlements" app

tool_root="$app_path/Contents/Resources/Tools"
if [[ -d "$tool_root" ]]; then
    for architecture in arm64 x86_64; do
        for tool in ffmpeg ffprobe mkvmerge mkvpropedit mkvextract; do
            code_path="$tool_root/$architecture/$tool"
            codesign --verify --strict "$code_path"
            compare_entitlements \
                "$code_path" "$repo_root/Configuration/Helper.entitlements" \
                "helper-$architecture-$tool"
        done
        while IFS= read -r library_path; do
            codesign --verify --strict "$tool_root/$architecture/$library_path"
        done < <(jq -r '.libraries[].path' "$tool_root/$architecture/manifest.json")
    done
fi

if [[ -n "${EXPECTED_TEAM_ID:-}" ]]; then
    details="$(codesign -d --verbose=4 "$app_path" 2>&1)"
    if ! grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID" <<<"$details"; then
        echo "signed app has an unexpected Team ID" >&2
        exit 1
    fi
fi
