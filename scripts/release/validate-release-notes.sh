#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: $0 <MAJOR.MINOR.PATCH>" >&2
    exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="$1"
notes_path="${MKV_MAGIC_RELEASE_NOTES_PATH:-$repo_root/docs/releases/$version.md}"

if [[ "$version" == 0.0.0 ]]; then
    echo "version 0.0.0 is reserved for the disposable package fixture" >&2
    exit 1
fi
if [[ "$notes_path" != /* || ! -f "$notes_path" || -L "$notes_path" ]]; then
    echo "release notes are missing or unsafe: $notes_path" >&2
    exit 1
fi
notes_size="$(stat -f %z "$notes_path")"
if [[ ! "$notes_size" =~ ^[0-9]+$ || "$notes_size" -lt 512 || "$notes_size" -gt 65536 ]]; then
    echo "release notes must be between 512 bytes and 64 KiB" >&2
    exit 1
fi

first_line="$(sed -n '1p' "$notes_path")"
if [[ "$first_line" != "# MKV Magic $version beta" ]]; then
    echo "release notes heading does not match version $version" >&2
    exit 1
fi
for required_heading in \
    '## Highlights' \
    '## Encoding and compatibility' \
    '## Safety and privacy' \
    '## Current limitations' \
    '## Requirements'; do
    if [[ "$(grep -Fxc "$required_heading" "$notes_path")" -ne 1 ]]; then
        echo "release notes require exactly one $required_heading section" >&2
        exit 1
    fi
done

if rg -qi '\b(TBD|TODO|FIXME|placeholder)\b|development package|package-gate fixture' \
    "$notes_path"; then
    echo "release notes still contain fixture or placeholder language" >&2
    exit 1
fi
for required_contract in \
    'macOS 13' \
    'Apple Silicon' \
    'Intel' \
    'Originals are never overwritten' \
    'runs locally' \
    'Image-subtitle OCR is not included'; do
    if ! grep -Fq "$required_contract" "$notes_path"; then
        echo "release notes do not disclose required contract: $required_contract" >&2
        exit 1
    fi
done

echo "release notes verified: $notes_path"
