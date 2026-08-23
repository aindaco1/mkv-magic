#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_root="${MKV_MAGIC_RELEASE_ROOT:-$repo_root/.build/release-artifacts}"
app_path="$release_root/MKV Magic.app"
output="$release_root/BUILD-METADATA.txt"
if [[ ! -d "$app_path" || -L "$app_path" || -e "$output" ]]; then
    echo "build metadata inputs or output are unsafe" >&2
    exit 1
fi
version="$(plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist")"
build="$(plutil -extract CFBundleVersion raw -o - "$app_path/Contents/Info.plist")"
commit="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo uncommitted)"
tree="$(git -C "$repo_root" rev-parse 'HEAD^{tree}' 2>/dev/null || echo uncommitted)"
timestamp="$(git -C "$repo_root" show -s --format=%cI HEAD 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')"
swift_version="$(swift --version | head -n 1)"
xcode_version="$(xcodebuild -version | tr '\n' ' ')"
{
    printf 'Product: MKV Magic\n'
    printf 'Version: %s\n' "$version"
    printf 'Build: %s\n' "$build"
    printf 'Source commit: %s\n' "$commit"
    printf 'Source tree: %s\n' "$tree"
    printf 'Source timestamp: %s\n' "$timestamp"
    printf 'Minimum macOS: 13.0\n'
    printf 'Architectures: arm64 x86_64\n'
    printf 'Swift: %s\n' "$swift_version"
    printf 'Xcode: %s\n' "$xcode_version"
} > "$output"
chmod 0644 "$output"
if grep -q '/Users/' "$output"; then
    echo "build metadata contains a personal path" >&2
    exit 1
fi
