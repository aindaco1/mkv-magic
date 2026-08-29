#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-MKV-Magic.app>" >&2
    exit 64
fi
app_path="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/ci/architecture.sh"
if [[ ! -d "$app_path" || -L "$app_path" ]]; then
    echo "missing or unsafe app bundle" >&2
    exit 1
fi

executable="$app_path/Contents/MacOS/MKVMagic"
framework="$app_path/Contents/Frameworks/Sparkle.framework"
required_files=(
    "$executable"
    "$app_path/Contents/Info.plist"
    "$app_path/Contents/Resources/MKVMagic.icns"
    "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
    "$app_path/Contents/Resources/SUPPORTED_SYSTEMS.md"
    "$app_path/Contents/Resources/TROUBLESHOOTING.md"
    "$app_path/Contents/Resources/Licenses/MKV-Magic-GPL-3.0.txt"
    "$app_path/Contents/Resources/Licenses/Sparkle-MIT.txt"
)
for file_path in "${required_files[@]}"; do
    if [[ ! -f "$file_path" || -L "$file_path" ]]; then
        echo "missing or unsafe app file: $file_path" >&2
        exit 1
    fi
done
if [[ ! -x "$executable" || ! -d "$framework" || -L "$framework" ]]; then
    echo "app executable or Sparkle framework is missing or unsafe" >&2
    exit 1
fi

"$repo_root/scripts/ci/check-info-plist.sh" "$app_path/Contents/Info.plist"
"$repo_root/scripts/ci/check-app-icon.sh" \
    "$app_path/Contents/Resources/MKVMagic.icns"
architectures="$(lipo -archs "$executable")"
if ! mkv_magic_is_universal_architecture_set "$architectures"; then
    echo "expected Universal app executable, found: $architectures" >&2
    exit 1
fi
sparkle_architectures="$(lipo -archs "$framework/Versions/Current/Sparkle")"
if ! mkv_magic_is_universal_architecture_set "$sparkle_architectures"; then
    echo "expected Universal Sparkle framework, found: $sparkle_architectures" >&2
    exit 1
fi

tool_root="$app_path/Contents/Resources/Tools"
if [[ -d "$tool_root" ]]; then
    "$repo_root/scripts/ci/check-tool-tree.sh" "$tool_root"
elif [[ "${MKV_MAGIC_REQUIRE_TOOLS:-0}" == 1 ]]; then
    echo "release app is missing bundled tools" >&2
    exit 1
fi

# macOS can warn about Intel support when any nested bundle component is thin,
# even if the main executable is Universal. Keep the whole app native on both
# supported processor families, including Sparkle and bundled media helpers.
mkv_magic_require_universal_mach_o_inventory "$app_path" "app bundle"

if find "$app_path" -name '.DS_Store' -o -name '._*' | grep -q .; then
    echo "app bundle contains forbidden Finder metadata" >&2
    exit 1
fi
