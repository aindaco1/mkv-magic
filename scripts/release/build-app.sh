#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_root="${MKV_MAGIC_RELEASE_ROOT:-$repo_root/.build/release-artifacts}"
app_path="$release_root/MKV Magic.app"
version="${MKV_MAGIC_VERSION:-0.0.0-dev}"
build_number="${MKV_MAGIC_BUILD_NUMBER:-1}"
bundle_identifier="${MKV_MAGIC_BUNDLE_IDENTIFIER:-com.dustwave.mkvmagic}"
tool_source_root="${MKV_MAGIC_TOOL_SOURCE_ROOT:-}"
require_tools="${MKV_MAGIC_REQUIRE_TOOLS:-0}"

if [[ "$release_root" != /* || "$release_root" == / || -L "$release_root" ]]; then
    echo "unsafe release root: $release_root" >&2
    exit 1
fi
case "$release_root" in
    */Library/Mobile\ Documents/*)
        echo "release root must be outside iCloud Drive: $release_root" >&2
        exit 1
        ;;
esac
if [[ -e "$release_root" ]]; then
    echo "refusing to replace existing release root: $release_root" >&2
    exit 1
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "invalid MKV Magic version: $version" >&2
    exit 64
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "invalid MKV Magic build number: $build_number" >&2
    exit 64
fi
case "$bundle_identifier" in
    com.dustwave.mkvmagic|com.dustwave.mkvmagic.package-gate) ;;
    *) echo "invalid MKV Magic bundle identifier: $bundle_identifier" >&2; exit 64 ;;
esac
if [[ "$require_tools" != 0 && "$require_tools" != 1 ]]; then
    echo "MKV_MAGIC_REQUIRE_TOOLS must be 0 or 1" >&2
    exit 64
fi

mkdir -p "$(dirname "$release_root")"
mkdir "$release_root"
mkdir -p \
    "$app_path/Contents/MacOS" \
    "$app_path/Contents/Resources/Licenses" \
    "$app_path/Contents/Frameworks"

cd "$repo_root"
swift build -c release --arch arm64 --arch x86_64 \
    --product MKVMagic --disable-automatic-resolution
binary_root="$(
    swift build -c release --arch arm64 --arch x86_64 \
        --product MKVMagic --disable-automatic-resolution --show-bin-path
)"
binary_path="$binary_root/MKVMagic"
sparkle_framework="$binary_root/Sparkle.framework"
if [[ ! -f "$binary_path" || -L "$binary_path" || ! -d "$sparkle_framework" ]]; then
    echo "missing Universal app executable or Sparkle framework" >&2
    exit 1
fi

install -m 0755 "$binary_path" "$app_path/Contents/MacOS/MKVMagic"
ditto --norsrc --noextattr "$sparkle_framework" \
    "$app_path/Contents/Frameworks/Sparkle.framework"
install -m 0644 Sources/MKVMagic/Info.plist "$app_path/Contents/Info.plist"
install -m 0644 THIRD_PARTY_NOTICES.md \
    "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
install -m 0644 docs/SUPPORTED_SYSTEMS.md \
    "$app_path/Contents/Resources/SUPPORTED_SYSTEMS.md"
install -m 0644 docs/TROUBLESHOOTING.md \
    "$app_path/Contents/Resources/TROUBLESHOOTING.md"
install -m 0644 LICENSE "$app_path/Contents/Resources/Licenses/MKV-Magic-GPL-3.0.txt"
install -m 0644 .build/checkouts/Sparkle/LICENSE \
    "$app_path/Contents/Resources/Licenses/Sparkle-MIT.txt"
install -m 0644 Package.resolved "$release_root/Package.resolved"
install -m 0644 THIRD_PARTY_NOTICES.md "$release_root/THIRD-PARTY-NOTICES.md"
install -m 0644 docs/SUPPORTED_SYSTEMS.md "$release_root/SUPPORTED-SYSTEMS.md"
install -m 0644 docs/TROUBLESHOOTING.md "$release_root/TROUBLESHOOTING.md"

if [[ -n "$tool_source_root" ]]; then
    if [[ "$tool_source_root" != /* || ! -d "$tool_source_root" || -L "$tool_source_root" ]]; then
        echo "unsafe MKV_MAGIC_TOOL_SOURCE_ROOT" >&2
        exit 1
    fi
    ditto --norsrc --noextattr "$tool_source_root" \
        "$app_path/Contents/Resources/Tools"
elif [[ "$require_tools" == 1 ]]; then
    echo "release requires an explicit verified tool source root" >&2
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" \
    "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" \
    "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_identifier" \
    "$app_path/Contents/Info.plist"

codesign --remove-signature "$app_path/Contents/MacOS/MKVMagic" 2>/dev/null || true
xattr -cr "$app_path"

architectures="$(lipo -archs "$app_path/Contents/MacOS/MKVMagic")"
if [[ "$architectures" != "x86_64 arm64" && "$architectures" != "arm64 x86_64" ]]; then
    echo "expected Universal app executable, found: $architectures" >&2
    exit 1
fi
"$repo_root/scripts/ci/check-app-bundle.sh" "$app_path"
echo "$app_path"
