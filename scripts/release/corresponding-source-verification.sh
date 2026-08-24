#!/usr/bin/env bash

corresponding_source_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$corresponding_source_repo_root/scripts/ci/tool-source-manifest.sh"
source "$corresponding_source_repo_root/scripts/ci/tool-tree-layout.sh"

mkv_magic_build_metadata_value() {
    if [[ $# -ne 2 || "$1" != /* || ! -f "$1" || -L "$1" ]]; then
        echo "build metadata lookup inputs are unsafe" >&2
        return 64
    fi
    local metadata="$1"
    local label="$2"
    local count
    count="$(grep -c "^$label: " "$metadata" || true)"
    if [[ "$count" -ne 1 ]]; then
        echo "build metadata must contain exactly one $label value" >&2
        return 1
    fi
    sed -n "s/^$label: //p" "$metadata"
}

validate_mkv_magic_build_metadata() {
    if [[ $# -ne 2 || "$1" != /* || ! -s "$1" || -L "$1" || \
          ! "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "build metadata validation inputs are unsafe" >&2
        return 64
    fi
    local metadata="$1"
    local version="$2"
    local labels
    labels="$(sed -n 's/^\([^:]*\): .*/\1/p' "$metadata" | LC_ALL=C sort)"
    local expected_labels
    expected_labels="$(printf '%s\n' \
        Architectures Build 'Minimum macOS' Product 'Source commit' \
        'Source timestamp' 'Source tree' Swift Version Xcode | LC_ALL=C sort)"
    if [[ "$labels" != "$expected_labels" || \
          "$(wc -l < "$metadata" | tr -d ' ')" -ne 10 || \
          "$(mkv_magic_build_metadata_value "$metadata" Product)" != "MKV Magic" || \
          "$(mkv_magic_build_metadata_value "$metadata" Version)" != "$version" || \
          ! "$(mkv_magic_build_metadata_value "$metadata" Build)" =~ ^[1-9][0-9]*$ || \
          ! "$(mkv_magic_build_metadata_value "$metadata" 'Source commit')" =~ ^[0-9a-f]{40}$ || \
          ! "$(mkv_magic_build_metadata_value "$metadata" 'Source tree')" =~ ^[0-9a-f]{40}$ || \
          ! "$(mkv_magic_build_metadata_value "$metadata" 'Source timestamp')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T || \
          "$(mkv_magic_build_metadata_value "$metadata" 'Minimum macOS')" != 13.0 || \
          "$(mkv_magic_build_metadata_value "$metadata" Architectures)" != "arm64 x86_64" || \
          "$(mkv_magic_build_metadata_value "$metadata" Swift)" != "Apple Swift version "* || \
          "$(mkv_magic_build_metadata_value "$metadata" Xcode)" != "Xcode "* ]]; then
        echo "build metadata does not match the release contract" >&2
        return 1
    fi
}

validate_mkv_magic_corresponding_source() (
    set -euo pipefail
    if [[ $# -ne 3 || "$1" != /* || ! -s "$1" || -L "$1" || \
          ! "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || \
          "$3" != /* || ! -s "$3" || -L "$3" ]]; then
        echo "corresponding-source validation inputs are unsafe" >&2
        return 64
    fi
    local archive="$1"
    local version="$2"
    local metadata="$3"
    local expected_archive_name="MKV-Magic-$version-corresponding-source.zip"
    if [[ "${archive##*/}" != "$expected_archive_name" || \
          "$(stat -f '%z' "$archive")" -gt 1073741824 ]]; then
        echo "corresponding-source archive name or size is invalid" >&2
        return 1
    fi
    validate_mkv_magic_build_metadata "$metadata" "$version"
    local expected_commit
    expected_commit="$(mkv_magic_build_metadata_value "$metadata" 'Source commit')"

    local entry_count=0
    local entry
    while IFS= read -r entry; do
        entry_count=$((entry_count + 1))
        case "$entry" in
            /* | ../* | */../* | */.. | *\\* | __MACOSX/* | \
                */__MACOSX/* | .DS_Store | */.DS_Store | ._* | */._*)
                echo "corresponding-source ZIP contains an unsafe path" >&2
                return 1
                ;;
        esac
    done < <(unzip -Z1 "$archive")
    if [[ "$entry_count" -lt 11 || "$entry_count" -gt 64 ]]; then
        echo "corresponding-source ZIP entry count is invalid" >&2
        return 1
    fi
    local zip_totals
    zip_totals="$(LC_ALL=C zipinfo -t "$archive")"
    if [[ ! "$zip_totals" =~ ([0-9]+)[[:space:]]bytes[[:space:]]uncompressed ]] || \
        [[ "${BASH_REMATCH[1]}" -gt 1073741824 ]]; then
        echo "corresponding-source expanded size is invalid" >&2
        return 1
    fi

    # This function runs in its own subshell. Keep the cleanup path in subshell
    # scope because Bash releases function-local variables before the EXIT trap.
    work_root=''
    work_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-source-verify.XXXXXX")"
    # Invoked by the EXIT trap in this subshell.
    # shellcheck disable=SC2329
    cleanup_corresponding_source() {
        /bin/rm -rf -- "$work_root"
    }
    trap cleanup_corresponding_source EXIT
    local extracted="$work_root/extracted"
    mkdir "$extracted"
    ditto -x -k --noextattr "$archive" "$extracted"
    local bundle_name="MKV-Magic-$version-corresponding-source"
    local bundle_root="$extracted/$bundle_name"
    mkv_magic_require_exact_children "$extracted" "corresponding-source root" \
        "$bundle_name"
    mkv_magic_require_exact_children "$bundle_root" "corresponding-source bundle" \
        "MKV-Magic-$version-source.tar.gz" README.md SOURCES.json dependencies
    if find "$extracted" -mindepth 1 ! -type d ! -type f -print -quit | grep -q .; then
        echo "corresponding-source ZIP contains a link or special file" >&2
        return 1
    fi

    local sources="$bundle_root/SOURCES.json"
    validate_mkv_magic_tool_source_manifest "$sources"
    local dependency_root="$bundle_root/dependencies"
    local dependency_names=(
        "ffmpeg-$(jq -r '.ffmpeg.version' "$sources").tar.xz"
        "nasm-$(jq -r '.nasm.version' "$sources").tar.xz"
        "SVT-AV1-v$(jq -r '.svtav1.version' "$sources").tar.gz"
        "dav1d-$(jq -r '.dav1d.version' "$sources").tar.bz2"
        "opus-$(jq -r '.opus.version' "$sources").tar.gz"
        "zimg-release-$(jq -r '.zimg.version' "$sources").tar.gz"
        "mkvtoolnix-$(jq -r '.mkvtoolnix.version' "$sources").tar.xz"
        "qtbase-everywhere-src-$(jq -r '.qtbase.version' "$sources").tar.xz"
    )
    local dependency_hashes=(
        "$(jq -r '.ffmpeg.sha256' "$sources")"
        "$(jq -r '.nasm.sha256' "$sources")"
        "$(jq -r '.svtav1.sha256' "$sources")"
        "$(jq -r '.dav1d.sha256' "$sources")"
        "$(jq -r '.opus.sha256' "$sources")"
        "$(jq -r '.zimg.sha256' "$sources")"
        "$(jq -r '.mkvtoolnix.sourceSha256' "$sources")"
        "$(jq -r '.qtbase.sha256' "$sources")"
    )
    mkv_magic_require_exact_children "$dependency_root" \
        "corresponding-source dependencies" "${dependency_names[@]}"
    local index
    for index in "${!dependency_names[@]}"; do
        local dependency="$dependency_root/${dependency_names[$index]}"
        local actual_hash
        actual_hash="$(shasum -a 256 "$dependency" | awk '{print $1}')"
        if [[ ! -s "$dependency" || -L "$dependency" || \
              "$actual_hash" != "${dependency_hashes[$index]}" ]]; then
            echo "corresponding source does not match ${dependency_names[$index]}" >&2
            return 1
        fi
    done

    local source_archive="$bundle_root/MKV-Magic-$version-source.tar.gz"
    local source_archive_bytes
    source_archive_bytes="$(stat -f '%z' "$source_archive")"
    if [[ ! -s "$source_archive" || -L "$source_archive" || \
          "$source_archive_bytes" -gt 268435456 ]] || ! gzip -t "$source_archive"; then
        echo "MKV Magic source archive is invalid" >&2
        return 1
    fi
    local source_entry_count=0
    local source_prefix="mkv-magic-$version/"
    while IFS= read -r entry; do
        source_entry_count=$((source_entry_count + 1))
        case "$entry" in
            "$source_prefix"*) ;;
            *) echo "MKV Magic source archive has the wrong root" >&2; return 1 ;;
        esac
        case "$entry" in
            /* | ../* | */../* | */.. | *\\* | */.DS_Store | */._*)
                echo "MKV Magic source archive contains an unsafe path" >&2
                return 1
                ;;
        esac
    done < <(tar -tzf "$source_archive")
    if [[ "$source_entry_count" -lt 20 || "$source_entry_count" -gt 10000 ]]; then
        echo "MKV Magic source archive entry count is invalid" >&2
        return 1
    fi
    local embedded_commit
    embedded_commit="$(
        set +o pipefail
        gzip -dc "$source_archive" | git get-tar-commit-id
    )"
    if [[ "$embedded_commit" != "$expected_commit" ]]; then
        echo "MKV Magic source archive does not match BUILD-METADATA.txt" >&2
        return 1
    fi

    local source_extract="$work_root/source"
    mkdir "$source_extract"
    tar -xzf "$source_archive" -C "$source_extract"
    local source_root="$source_extract/mkv-magic-$version"
    mkv_magic_require_exact_children "$source_extract" "MKV Magic source root" \
        "mkv-magic-$version"
    if find "$source_root" -mindepth 1 ! -type d ! -type f -print -quit | grep -q . || \
        find "$source_root" -mindepth 1 \( -name .git -o -name .build \) \
            -print -quit | grep -q .; then
        echo "MKV Magic source tree contains an unsafe entry" >&2
        return 1
    fi
    local required_source
    for required_source in \
        LICENSE Package.swift Package.resolved \
        docs/CORRESPONDING_SOURCE.md \
        scripts/tools/build-runtime.sh \
        scripts/release/bundle-corresponding-source.sh
    do
        if [[ ! -s "$source_root/$required_source" || \
              -L "$source_root/$required_source" ]]; then
            echo "MKV Magic source archive is missing $required_source" >&2
            return 1
        fi
    done
    if ! cmp -s "$bundle_root/README.md" \
        "$source_root/docs/CORRESPONDING_SOURCE.md"; then
        echo "corresponding-source README does not match the archived source" >&2
        return 1
    fi
    local build_script="$source_root/scripts/tools/build-runtime.sh"
    local pinned_value
    while IFS= read -r pinned_value; do
        if [[ ! "$pinned_value" =~ ^[0-9A-Za-z][0-9A-Za-z.-]*$ && \
              ! "$pinned_value" =~ ^[a-f0-9]{64}$ ]] || \
            ! grep -Fq "$pinned_value" "$build_script"; then
            echo "corresponding source does not match the runtime build pins" >&2
            return 1
        fi
    done < <(jq -r '
        .ffmpeg.version, .ffmpeg.sha256,
        .nasm.version, .nasm.sha256,
        .svtav1.version, .svtav1.sha256,
        .dav1d.version, .dav1d.sha256,
        .opus.version, .opus.sha256,
        .zimg.version, .zimg.sha256,
        .mkvtoolnix.version, .mkvtoolnix.binarySha256, .mkvtoolnix.sourceSha256,
        .qtbase.version, .qtbase.sha256
    ' "$sources")
)
