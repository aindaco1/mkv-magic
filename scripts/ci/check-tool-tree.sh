#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-Tools-directory>" >&2
    exit 64
fi
tool_root="$1"
if [[ ! -d "$tool_root" || -L "$tool_root" ]]; then
    echo "missing or unsafe tool root" >&2
    exit 1
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/ci/tool-tree-layout.sh"
validate_mkv_magic_tool_tree_layout "$tool_root"
sources="$tool_root/SOURCES.json"
required_license_files=(
    "$tool_root/Licenses/FFmpeg-GPLv3.txt"
    "$tool_root/Licenses/MKVToolNix-GPL.txt"
    "$tool_root/Licenses/SVT-AV1/LICENSE.md"
    "$tool_root/Licenses/SVT-AV1/PATENTS.md"
    "$tool_root/Licenses/dav1d/COPYING"
    "$tool_root/Licenses/Opus/COPYING"
    "$tool_root/Licenses/zimg/COPYING"
    "$tool_root/Licenses/Qt/LICENSES/LGPL-3.0-only.txt"
)
if [[ ! -f "$sources" || -L "$sources" ]]; then
    echo "missing or unsafe tool source manifest" >&2
    exit 1
fi
for license_file in "${required_license_files[@]}"; do
    if [[ ! -s "$license_file" || -L "$license_file" ]]; then
        echo "missing or unsafe runtime license: $license_file" >&2
        exit 1
    fi
done
if ! jq -e '
    (keys | sort) == ["dav1d", "ffmpeg", "minimumMacOS", "mkvtoolnix", "nasm", "opus", "qtbase", "schema", "svtav1", "zimg"] and
    .schema == "mkv-magic-tool-sources-v2" and
    .minimumMacOS == "13.0" and
    .ffmpeg.network == false and
    .ffmpeg.license == "GPL-3.0-or-later" and
    (.ffmpeg.url | startswith("https://ffmpeg.org/")) and
    (.ffmpeg.sha256 | test("^[a-f0-9]{64}$")) and
    (.ffmpeg.configuration | sort) == ([
      "--disable-autodetect", "--disable-avdevice", "--disable-network",
      "--disable-shared", "--enable-audiotoolbox", "--enable-gpl",
      "--enable-libdav1d", "--enable-libopus", "--enable-libsvtav1", "--enable-libzimg", "--enable-static", "--enable-version3",
      "--enable-videotoolbox"
    ] | sort) and
    .nasm.buildOnly == true and
    .nasm.license == "BSD-2-Clause" and
    (.nasm.url | startswith("https://www.nasm.us/")) and
    (.nasm.sha256 | test("^[a-f0-9]{64}$")) and
    .svtav1.linkedStatically == true and
    .svtav1.license == "BSD-3-Clause-Clear" and
    .svtav1.patentLicense == "Alliance for Open Media Patent License 1.0" and
    (.svtav1.url | startswith("https://gitlab.com/AOMediaCodec/SVT-AV1/")) and
    (.svtav1.sha256 | test("^[a-f0-9]{64}$")) and
    (.svtav1.build | sort) == ([
      "BUILD_APPS=OFF", "BUILD_SHARED_LIBS=OFF", "BUILD_TESTING=OFF",
      "EXCLUDE_HASH=ON", "NATIVE=OFF", "SVT_AV1_LTO=OFF"
    ] | sort) and
    .dav1d.linkedStatically == true and
    .dav1d.license == "BSD-2-Clause" and
    (.dav1d.url | startswith("https://code.videolan.org/videolan/dav1d/")) and
    (.dav1d.sha256 | test("^[a-f0-9]{64}$")) and
    (.dav1d.build | sort) == ([
      "b_lto=false", "default_library=static", "enable_docs=false",
      "enable_examples=false", "enable_tests=false", "enable_tools=false"
    ] | sort) and
    .opus.linkedStatically == true and
    .opus.license == "BSD-3-Clause" and
    (.opus.url | startswith("https://downloads.xiph.org/releases/opus/")) and
    (.opus.sha256 | test("^[a-f0-9]{64}$")) and
    (.opus.build | sort) == ([
      "disable_doc=true", "disable_extra_programs=true",
      "disable_shared=true", "enable_static=true"
    ] | sort) and
    .zimg.linkedStatically == true and
    .zimg.license == "WTFPL" and
    (.zimg.url | startswith("https://github.com/sekrit-twc/zimg/")) and
    (.zimg.sha256 | test("^[a-f0-9]{64}$")) and
    (.zimg.build | sort) == ([
      "disable_example=true", "disable_shared=true", "disable_testapp=true",
      "disable_unit_test=true", "enable_static=true"
    ] | sort) and
    .mkvtoolnix.license == "GPL-2.0-or-later" and
    (.mkvtoolnix.binaryURL | startswith("https://mkvtoolnix.download/")) and
    (.mkvtoolnix.sourceURL | startswith("https://mkvtoolnix.download/")) and
    (.mkvtoolnix.binarySha256 | test("^[a-f0-9]{64}$")) and
    (.mkvtoolnix.sourceSha256 | test("^[a-f0-9]{64}$")) and
    .qtbase.license == "LGPL-3.0-only" and
    (.qtbase.url | startswith("https://download.qt.io/")) and
    (.qtbase.sha256 | test("^[a-f0-9]{64}$")) and
    ([.ffmpeg.version, .nasm.version, .svtav1.version, .dav1d.version, .opus.version, .zimg.version,
      .mkvtoolnix.version, .qtbase.version]
      | all(type == "string" and length > 0))
' "$sources" >/dev/null; then
    echo "invalid tool source manifest" >&2
    exit 1
fi
expected_tools=(ffmpeg ffprobe mkvmerge mkvpropedit mkvextract)
for architecture in arm64 x86_64; do
    architecture_root="$tool_root/$architecture"
    manifest="$architecture_root/manifest.json"
    if [[ ! -d "$architecture_root" || -L "$architecture_root" || \
          ! -f "$manifest" || -L "$manifest" ]]; then
        echo "missing or unsafe $architecture tool tree" >&2
        exit 1
    fi
    schema="$(jq -r '.schema' "$manifest")"
    manifest_architecture="$(jq -r '.architecture' "$manifest")"
    manifest_platform="$(jq -r '.platform' "$manifest")"
    keys="$(jq -r 'keys | sort | join(",")' "$manifest")"
    if [[ "$schema" != mkv-magic-tool-manifest-v1 || \
          "$manifest_architecture" != "$architecture" || \
          "$manifest_platform" != macos || \
          "$keys" != architecture,libraries,platform,schema,tools ]]; then
        echo "invalid $architecture tool manifest identity" >&2
        exit 1
    fi
    if [[ "$(jq '.tools | length' "$manifest")" -ne 5 ]]; then
        echo "$architecture tool manifest must contain exactly five tools" >&2
        exit 1
    fi
    build_manifest="$architecture_root/build-manifest.json"
    if [[ -e "$build_manifest" ]]; then
        if [[ ! -f "$build_manifest" || -L "$build_manifest" ]] || \
            ! jq -e --arg architecture "$architecture" '
                (keys | sort) == ["architecture", "libraries", "platform", "schema", "tools"] and
                .schema == "mkv-magic-tool-manifest-v1" and
                .platform == "macos" and
                .architecture == $architecture and
                (.tools | length == 5) and
                (.libraries | length == 1) and
                ([.tools[].sha256, .libraries[].sha256]
                  | all(type == "string" and test("^[a-f0-9]{64}$")))
            ' "$build_manifest" >/dev/null; then
            echo "invalid $architecture build manifest" >&2
            exit 1
        fi
        signed_structure="$(
            jq -S 'del(.tools[].sha256, .libraries[].sha256)' "$manifest"
        )"
        build_structure="$(
            jq -S 'del(.tools[].sha256, .libraries[].sha256)' "$build_manifest"
        )"
        if [[ "$signed_structure" != "$build_structure" ]]; then
            echo "$architecture build and signed manifests disagree" >&2
            exit 1
        fi
    fi
    for tool in "${expected_tools[@]}"; do
        tool_path="$architecture_root/$tool"
        if [[ ! -f "$tool_path" || -L "$tool_path" || ! -x "$tool_path" ]]; then
            echo "missing or unsafe $architecture tool: $tool" >&2
            exit 1
        fi
        manifest_path="$(jq -r --arg name "$tool" '.tools[] | select(.name == $name) | .path' "$manifest")"
        expected_hash="$(jq -r --arg name "$tool" '.tools[] | select(.name == $name) | .sha256' "$manifest")"
        if [[ "$manifest_path" != "$tool" || ! "$expected_hash" =~ ^[a-f0-9]{64}$ ]]; then
            echo "invalid manifest entry for $architecture/$tool" >&2
            exit 1
        fi
        actual_hash="$(shasum -a 256 "$tool_path" | awk '{print $1}')"
        if [[ "$actual_hash" != "$expected_hash" ]]; then
            echo "hash mismatch for $architecture/$tool" >&2
            exit 1
        fi
        tool_architectures="$(lipo -archs "$tool_path")"
        if [[ "$tool_architectures" != "$architecture" ]]; then
            echo "wrong architecture for $tool_path: $tool_architectures" >&2
            exit 1
        fi
        codesign --verify --strict "$tool_path"
    done
    while IFS= read -r library_path; do
        if [[ "$library_path" != libs/* || "$library_path" == *..* ]]; then
            echo "invalid library path in $architecture manifest" >&2
            exit 1
        fi
        library="$architecture_root/$library_path"
        expected_hash="$(
            jq -r --arg path "$library_path" \
                '.libraries[] | select(.path == $path) | .sha256' "$manifest"
        )"
        if [[ ! -f "$library" || -L "$library" || \
              ! "$expected_hash" =~ ^[a-f0-9]{64}$ ]]; then
            echo "missing or unsafe runtime library: $architecture/$library_path" >&2
            exit 1
        fi
        actual_hash="$(shasum -a 256 "$library" | awk '{print $1}')"
        library_architectures="$(lipo -archs "$library")"
        if [[ "$actual_hash" != "$expected_hash" || \
              "$library_architectures" != "$architecture" ]]; then
            echo "runtime library verification failed: $architecture/$library_path" >&2
            exit 1
        fi
    done < <(jq -r '.libraries[].path' "$manifest")

    for relative_binary in "${expected_tools[@]}" libs/libQt6Core.6.dylib; do
        binary="$architecture_root/$relative_binary"
        minimum_versions="$(
            otool -l "$binary" \
                | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; found=0}' \
                | sort -u
        )"
        if [[ "$minimum_versions" != 13.0 ]]; then
            echo "unexpected deployment target for $binary: $minimum_versions" >&2
            exit 1
        fi
        while IFS= read -r dependency; do
            case "$dependency" in
                /System/Library/*|/usr/lib/*) ;;
                @executable_path/libs/libQt6Core.6.dylib)
                    case "$relative_binary" in
                        mkvmerge|mkvpropedit|mkvextract) ;;
                        *) echo "unexpected Qt dependency for $binary" >&2; exit 1 ;;
                    esac
                    ;;
                @rpath/libQt6Core.6.dylib)
                    if [[ "$relative_binary" != libs/libQt6Core.6.dylib ]]; then
                        echo "unexpected Qt install name for $binary" >&2
                        exit 1
                    fi
                    ;;
                *)
                    echo "unpackaged dynamic dependency for $binary: $dependency" >&2
                    exit 1
                    ;;
            esac
        done < <(
            otool -L "$binary" | tail -n +2 \
                | sed -E 's/^[[:space:]]*//; s/[[:space:]]+\(compatibility.*$//'
        )
    done
done

while IFS= read -r -d '' link_path; do
    target="$(readlink "$link_path")"
    if [[ "$target" == /* ]]; then
        echo "tool tree contains an absolute symlink: $link_path" >&2
        exit 1
    fi
    if ! realpath "$link_path" >/dev/null 2>&1; then
        echo "tool tree contains a dangling symlink: $link_path" >&2
        exit 1
    fi
    resolved="$(realpath "$link_path")"
    case "$resolved" in
        "$tool_root"/*) ;;
        *) echo "tool tree contains an escaping symlink: $link_path" >&2; exit 1 ;;
    esac
done < <(find "$tool_root" -type l -print0)
