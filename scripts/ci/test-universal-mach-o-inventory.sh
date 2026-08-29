#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/ci/architecture.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-architecture-test.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

printf '%s\n' 'int main(void) { return 0; }' > "$test_root/main.c"
clang="$(xcrun --sdk macosx --find clang)"
sdk_root="$(xcrun --sdk macosx --show-sdk-path)"
for architecture in arm64 x86_64; do
    mkdir "$test_root/$architecture"
    "$clang" -arch "$architecture" -isysroot "$sdk_root" \
        -mmacosx-version-min=13.0 "$test_root/main.c" \
        -o "$test_root/$architecture/probe"
done

mkdir "$test_root/universal"
lipo -create "$test_root/arm64/probe" "$test_root/x86_64/probe" \
    -output "$test_root/universal/probe"
mkv_magic_require_universal_mach_o_inventory \
    "$test_root/universal" "Universal fixture"

if mkv_magic_require_universal_mach_o_inventory \
    "$test_root/arm64" "thin fixture" >/dev/null 2>&1; then
    echo "Mach-O inventory accepted an ARM64-only component" >&2
    exit 1
fi

mkdir "$test_root/empty"
printf 'not executable code\n' > "$test_root/empty/document.txt"
if mkv_magic_require_universal_mach_o_inventory \
    "$test_root/empty" "empty fixture" >/dev/null 2>&1; then
    echo "Mach-O inventory accepted a bundle without executable code" >&2
    exit 1
fi

echo "Universal Mach-O inventory tests passed"
