#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-MKV-Magic-version-universal.dmg>" >&2
    exit 64
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/release/dmg-layout.sh"
source "$repo_root/scripts/release/dmg-verification.sh"
dmg_path="$1"
if [[ ! "${dmg_path##*/}" =~ ^MKV-Magic-[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?-universal\.dmg$ || \
      ! -f "$dmg_path" || -L "$dmg_path" || ! -s "$dmg_path" ]]; then
    echo "DMG artifact is missing or unsafe" >&2
    exit 1
fi

verify_mkv_magic_dmg_checksum "$dmg_path"
if [[ "${MKV_MAGIC_REQUIRE_DISTRIBUTION:-0}" == 1 ]]; then
    codesign --verify --strict --verbose=2 "$dmg_path"
    xcrun stapler validate "$dmg_path"
    spctl --assess --type open --context context:primary-signature \
        --verbose=2 "$dmg_path"
fi

work_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-dmg-verify.XXXXXX")"
mount_point="$work_root/mount"
mkdir "$mount_point"
attached=0
cleanup() {
    local status=$?
    set +e
    if [[ "$attached" == 1 ]]; then
        hdiutil detach "$mount_point" -quiet 2>/dev/null || \
            hdiutil detach "$mount_point" -force -quiet 2>/dev/null
    fi
    /bin/rm -rf -- "$work_root"
    exit "$status"
}
trap cleanup EXIT

hdiutil attach "$dmg_path" -readonly -nobrowse -noautoopen \
    -mountpoint "$mount_point" -quiet
attached=1
validate_mkv_magic_dmg_layout "$mount_point"
mounted_app="$mount_point/$MKV_MAGIC_DMG_APP_NAME"
MKV_MAGIC_REQUIRE_TOOLS="${MKV_MAGIC_REQUIRE_TOOLS:-0}" \
    "$repo_root/scripts/ci/check-app-bundle.sh" "$mounted_app"
if [[ "${MKV_MAGIC_REQUIRE_DISTRIBUTION:-0}" == 1 ]]; then
    codesign --verify --deep --strict --verbose=2 "$mounted_app"
    "$repo_root/scripts/ci/check-signed-entitlements.sh" "$mounted_app"
    xcrun stapler validate "$mounted_app"
    spctl --assess --type execute --verbose=2 "$mounted_app"
fi
verification_architectures="$({
    mkv_magic_verification_architectures \
        "${MKV_MAGIC_VERIFY_ARCHITECTURES:-arm64 x86_64}"
})"
while IFS= read -r architecture; do
    if [[ "${MKV_MAGIC_VERIFY_BUNDLED_TOOLS:-0}" == 1 ]]; then
        /usr/bin/arch "-$architecture" "$mounted_app/Contents/MacOS/MKVMagic" \
            --verify-bundled-tools
    fi
    if [[ "${MKV_MAGIC_VERIFY_BUNDLED_FIXTURE:-0}" == 1 ]]; then
        /usr/bin/arch "-$architecture" "$mounted_app/Contents/MacOS/MKVMagic" \
            --run-bundled-fixture-smoke
    fi
    if [[ "${MKV_MAGIC_VERIFY_NATIVE_RELEASE:-0}" == 1 ]]; then
        /usr/bin/arch "-$architecture" "$mounted_app/Contents/MacOS/MKVMagic" \
            --run-native-release-verification
    fi
done <<< "$verification_architectures"
echo "verified MKV Magic DMG: $dmg_path"
