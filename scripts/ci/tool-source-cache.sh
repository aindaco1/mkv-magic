#!/usr/bin/env bash

mkv_magic_tool_source_cache_entries() {
    if [[ $# -ne 1 || "$1" != /* ]]; then
        echo "usage: mkv_magic_tool_source_cache_entries <absolute-SOURCES.json>" >&2
        return 64
    fi
    local sources="$1"
    if [[ ! -s "$sources" || -L "$sources" ]]; then
        echo "tool source manifest is missing or unsafe" >&2
        return 1
    fi

    local ffmpeg_version
    local nasm_version
    local svtav1_version
    local dav1d_version
    local opus_version
    local zimg_version
    local mkvtoolnix_version
    local qt_version
    ffmpeg_version="$(jq -r '.ffmpeg.version' "$sources")"
    nasm_version="$(jq -r '.nasm.version' "$sources")"
    svtav1_version="$(jq -r '.svtav1.version' "$sources")"
    dav1d_version="$(jq -r '.dav1d.version' "$sources")"
    opus_version="$(jq -r '.opus.version' "$sources")"
    zimg_version="$(jq -r '.zimg.version' "$sources")"
    mkvtoolnix_version="$(jq -r '.mkvtoolnix.version' "$sources")"
    qt_version="$(jq -r '.qtbase.version' "$sources")"

    printf '%s\t%s\n' \
        "ffmpeg-$ffmpeg_version/ffmpeg-$ffmpeg_version.tar.xz" \
        "$(jq -r '.ffmpeg.sha256' "$sources")"
    printf '%s\t%s\n' \
        "nasm-$nasm_version/nasm-$nasm_version.tar.xz" \
        "$(jq -r '.nasm.sha256' "$sources")"
    printf '%s\t%s\n' \
        "svt-av1-$svtav1_version/SVT-AV1-v$svtav1_version.tar.gz" \
        "$(jq -r '.svtav1.sha256' "$sources")"
    printf '%s\t%s\n' \
        "dav1d-$dav1d_version/dav1d-$dav1d_version.tar.xz" \
        "$(jq -r '.dav1d.sha256' "$sources")"
    printf '%s\t%s\n' \
        "opus-$opus_version/opus-$opus_version.tar.gz" \
        "$(jq -r '.opus.sha256' "$sources")"
    printf '%s\t%s\n' \
        "zimg-$zimg_version/zimg-release-$zimg_version.tar.gz" \
        "$(jq -r '.zimg.sha256' "$sources")"
    printf '%s\t%s\n' \
        "mkvtoolnix-$mkvtoolnix_version/mkvtoolnix-$mkvtoolnix_version.tar.xz" \
        "$(jq -r '.mkvtoolnix.sourceSha256' "$sources")"
    printf '%s\t%s\n' \
        "qtbase-$qt_version/qtbase-everywhere-src-$qt_version.tar.xz" \
        "$(jq -r '.qtbase.sha256' "$sources")"
}

mkv_magic_verify_tool_source_cache() {
    if [[ $# -ne 2 || "$1" != /* || "$2" != /* ]]; then
        echo "usage: mkv_magic_verify_tool_source_cache <absolute-cache-directory> <absolute-SOURCES.json>" >&2
        return 64
    fi
    local cache_root="$1"
    local sources="$2"
    if [[ ! -d "$cache_root" || -L "$cache_root" ]]; then
        echo "tool source cache is missing or unsafe" >&2
        return 1
    fi

    local relative_path
    local expected_hash
    local source_path
    local actual_hash
    while IFS=$'\t' read -r relative_path expected_hash; do
        if [[ -z "$relative_path" || "$relative_path" == /* || \
              "$relative_path" == *..* || \
              ! "$relative_path" =~ ^[A-Za-z0-9._+/-]+$ || \
              ! "$expected_hash" =~ ^[a-f0-9]{64}$ ]]; then
            echo "tool source cache entry is invalid" >&2
            return 1
        fi
        source_path="$cache_root/$relative_path"
        if [[ ! -f "$source_path" || -L "$source_path" ]]; then
            echo "tool source cache input is missing or unsafe: $relative_path" >&2
            return 1
        fi
        actual_hash="$(shasum -a 256 "$source_path" | awk '{print $1}')"
        if [[ "$actual_hash" != "$expected_hash" ]]; then
            echo "tool source cache checksum mismatch: $relative_path" >&2
            return 1
        fi
    done < <(mkv_magic_tool_source_cache_entries "$sources")
}

mkv_magic_copy_tool_source_cache() {
    if [[ $# -ne 3 || "$1" != /* || "$2" != /* || "$3" != /* ]]; then
        echo "usage: mkv_magic_copy_tool_source_cache <absolute-cache-directory> <absolute-SOURCES.json> <absolute-destination>" >&2
        return 64
    fi
    local cache_root="$1"
    local sources="$2"
    local destination="$3"
    if [[ -e "$destination" || -L "$destination" ]]; then
        echo "tool source cache destination must be absent" >&2
        return 1
    fi
    mkv_magic_verify_tool_source_cache "$cache_root" "$sources"
    mkdir "$destination"

    local relative_path
    local expected_hash
    while IFS=$'\t' read -r relative_path expected_hash; do
        mkdir -p "$destination/$(dirname "$relative_path")"
        install -m 0644 "$cache_root/$relative_path" \
            "$destination/$relative_path"
    done < <(mkv_magic_tool_source_cache_entries "$sources")
    mkv_magic_verify_tool_source_cache "$destination" "$sources"
}
