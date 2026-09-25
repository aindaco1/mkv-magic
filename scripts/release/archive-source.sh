#!/usr/bin/env bash
# Include the immutable Platform sources while retaining Git's commit header.
mkv_magic_archive_source() (
    set -euo pipefail
    local archive_repo="$1" archive_version="$2" archive_output="$3"
    if [[ ! "$archive_version" =~ ^[0-9A-Za-z][0-9A-Za-z.-]*$ || "$archive_output" != /* || -e "$archive_output" ]]; then
        echo "unsafe or existing source archive destination" >&2
        return 1
    fi
    local platform="$archive_repo/shared/dust-wave-platform" pin checkout
    pin="$(git -C "$archive_repo" rev-parse HEAD:shared/dust-wave-platform)"
    checkout="$(git -C "$platform" rev-parse HEAD)"
    if [[ "$checkout" != "$pin" ]]; then
        echo "Platform checkout differs from release gitlink" >&2
        return 1
    fi
    git -C "$platform" diff --quiet HEAD
    local archive_work prefix
    archive_work="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-source-archive.XXXXXX")"
    trap '/bin/rm -rf -- "$archive_work"' EXIT
    prefix="mkv-magic-$archive_version"
    git -C "$archive_repo" archive --format=tar --prefix="$prefix/" HEAD > "$archive_work/source.tar"
    mkdir "$archive_work/platform"
    git -C "$platform" archive --format=tar --prefix="$prefix/shared/dust-wave-platform/" "$pin" \
        | tar -xf - -C "$archive_work/platform"
    COPYFILE_DISABLE=1 tar -rf "$archive_work/source.tar" -C "$archive_work/platform" \
        "$prefix/shared/dust-wave-platform"
    gzip -c "$archive_work/source.tar" > "$archive_output"
)
