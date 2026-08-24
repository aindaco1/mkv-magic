#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <MKV Magic.app> <signing-identity> [timestamp|none]" >&2
    exit 64
fi
app_input="$1"
signing_identity="$2"
timestamp_mode="${3:-timestamp}"
signing_keychain="${SIGNING_KEYCHAIN_PATH:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ ! -d "$app_input" || -L "$app_input" ]]; then
    echo "missing or unsafe MKV Magic app" >&2
    exit 1
fi
app_path="$(cd "$(dirname "$app_input")" && pwd -P)/$(basename "$app_input")"
bundle_identifier="$(plutil -extract CFBundleIdentifier raw -o - \
    "$app_path/Contents/Info.plist")"
if [[ "$signing_identity" != - && "$bundle_identifier" != com.dustwave.mkvmagic ]]; then
    echo "Developer ID signing requires the production bundle identifier" >&2
    exit 1
fi
framework="$app_path/Contents/Frameworks/Sparkle.framework"
current="$framework/Versions/Current"
if [[ ! -d "$framework" || -L "$framework" ]]; then
    echo "app is missing Sparkle framework" >&2
    exit 1
fi
case "$timestamp_mode" in
    timestamp) timestamp_flag=(--timestamp) ;;
    none) timestamp_flag=(--timestamp=none) ;;
    *) echo "invalid timestamp mode: $timestamp_mode" >&2; exit 64 ;;
esac
if [[ -n "$signing_keychain" ]]; then
    if [[ "$signing_keychain" != /* || ! -f "$signing_keychain" || -L "$signing_keychain" ]]; then
        echo "signing keychain is missing or unsafe" >&2
        exit 1
    fi
fi

xattr -cr "$app_path"
common_flags=(
    --force
)
# Hardened runtime library validation requires a shared Developer ID Team ID.
# Disposable ad-hoc package-gate signatures have no Team ID, so they exercise
# bundle structure and entitlements without this production-only flag.
if [[ "$signing_identity" != - ]]; then
    common_flags+=(--options runtime)
fi
common_flags+=("${timestamp_flag[@]}" --sign "$signing_identity")
if [[ -n "$signing_keychain" ]]; then
    common_flags+=(--keychain "$signing_keychain")
fi

tool_root="$app_path/Contents/Resources/Tools"
if [[ -d "$tool_root" ]]; then
    # Prove the copied runtime inventory before codesign changes any bytes. This
    # also permits a previously signed release tree to be safely re-signed:
    # its build manifest remains the immutable pre-sign provenance record.
    "$repo_root/scripts/ci/check-tool-tree.sh" "$tool_root"
    for architecture in arm64 x86_64; do
        while IFS= read -r library_path; do
            codesign "${common_flags[@]}" \
                "$tool_root/$architecture/$library_path"
        done < <(jq -r '.libraries[].path' "$tool_root/$architecture/manifest.json")
        for tool in ffmpeg ffprobe mkvmerge mkvpropedit mkvextract; do
            codesign "${common_flags[@]}" \
                --entitlements "$repo_root/Configuration/Helper.entitlements" \
                "$tool_root/$architecture/$tool"
        done
    done
    "$repo_root/scripts/release/reseal-tool-manifests.swift" "$tool_root"
    "$repo_root/scripts/ci/check-tool-tree.sh" "$tool_root"
fi

# Sparkle's services are signed inside out. Downloader keeps its upstream
# network entitlement; the main app never receives one.
codesign "${common_flags[@]}" "$current/XPCServices/Installer.xpc"
codesign "${common_flags[@]}" --preserve-metadata=entitlements \
    "$current/XPCServices/Downloader.xpc"
codesign "${common_flags[@]}" "$current/Autoupdate"
codesign "${common_flags[@]}" "$current/Updater.app"
codesign "${common_flags[@]}" "$framework"

xattr -cr "$app_path"
codesign "${common_flags[@]}" \
    --entitlements "$repo_root/Configuration/MKVMagic.entitlements" \
    "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
"$repo_root/scripts/ci/check-signed-entitlements.sh" "$app_path"
