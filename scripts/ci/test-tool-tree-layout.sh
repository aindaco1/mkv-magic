#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/ci/tool-tree-layout.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-tool-layout-test.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

make_fixture() {
    local fixture="$1"
    mkdir -p \
        "$fixture/arm64/libs" "$fixture/x86_64/libs" \
        "$fixture/Licenses/Opus" "$fixture/Licenses/Qt/LICENSES" \
        "$fixture/Licenses/SVT-AV1" "$fixture/Licenses/dav1d" \
        "$fixture/Licenses/zimg"
    printf '{}\n' > "$fixture/SOURCES.json"
    local architecture
    local name
    for architecture in arm64 x86_64; do
        for name in ffmpeg ffprobe manifest.json mkvextract mkvmerge mkvpropedit; do
            printf 'fixture\n' > "$fixture/$architecture/$name"
        done
        printf 'fixture\n' > "$fixture/$architecture/libs/libQt6Core.6.dylib"
    done
    for name in \
        FFmpeg-GPLv3.txt MKVToolNix-GPL.txt Opus/COPYING \
        SVT-AV1/LICENSE.md SVT-AV1/PATENTS.md dav1d/COPYING zimg/COPYING \
        Qt/LICENSES/LGPL-3.0-only.txt
    do
        printf 'license\n' > "$fixture/Licenses/$name"
    done
}

expect_rejection() {
    local fixture="$1"
    local description="$2"
    if validate_mkv_magic_tool_tree_layout "$fixture" >/dev/null 2>&1; then
        echo "tool layout validator accepted $description" >&2
        exit 1
    fi
}

valid="$test_root/valid"
make_fixture "$valid"
validate_mkv_magic_tool_tree_layout "$valid"

signed="$test_root/signed"
cp -R "$valid" "$signed"
cp "$signed/arm64/manifest.json" "$signed/arm64/build-manifest.json"
cp "$signed/x86_64/manifest.json" "$signed/x86_64/build-manifest.json"
validate_mkv_magic_tool_tree_layout "$signed"

unexpected_root="$test_root/unexpected-root"
cp -R "$valid" "$unexpected_root"
printf 'scratch\n' > "$unexpected_root/workspace-state.json"
expect_rejection "$unexpected_root" "an unexpected top-level file"

unexpected_architecture="$test_root/unexpected-architecture"
cp -R "$valid" "$unexpected_architecture"
printf 'tool\n' > "$unexpected_architecture/arm64/extra-tool"
expect_rejection "$unexpected_architecture" "an unexpected architecture file"

nested_license="$test_root/nested-license"
cp -R "$valid" "$nested_license"
mkdir "$nested_license/Licenses/Qt/LICENSES/nested"
printf 'license\n' > "$nested_license/Licenses/Qt/LICENSES/nested/file.txt"
expect_rejection "$nested_license" "a nested license directory"

executable_license="$test_root/executable-license"
cp -R "$valid" "$executable_license"
chmod 0755 "$executable_license/Licenses/FFmpeg-GPLv3.txt"
expect_rejection "$executable_license" "an executable license document"

linked_tool="$test_root/linked-tool"
cp -R "$valid" "$linked_tool"
/bin/rm -f "$linked_tool/x86_64/ffprobe"
ln -s ffmpeg "$linked_tool/x86_64/ffprobe"
expect_rejection "$linked_tool" "a symbolic-link tool"

echo "tool tree layout tests passed"
