#!/usr/bin/env bash

validate_mkv_magic_tool_source_manifest() {
    if [[ $# -ne 1 || "$1" != /* ]]; then
        echo "usage: validate_mkv_magic_tool_source_manifest <absolute-SOURCES.json>" >&2
        return 64
    fi
    local sources="$1"
    if [[ ! -s "$sources" || -L "$sources" ]] || ! jq -e '
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
        (.dav1d.url | startswith("https://download.videolan.org/pub/videolan/dav1d/")) and
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
          | all(type == "string" and test("^[0-9A-Za-z][0-9A-Za-z.-]*$")))
    ' "$sources" >/dev/null; then
        echo "invalid tool source manifest" >&2
        return 1
    fi
}
