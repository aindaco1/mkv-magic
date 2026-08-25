#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runtime_script="$repo_root/scripts/tools/build-runtime.sh"

assert_assignment() {
    local name="$1"
    local expected="$2"
    local actual
    actual="$(sed -n "s/^${name}=//p" "$runtime_script")"
    if [[ "$actual" != "$expected" ]]; then
        echo "unexpected $name pin: $actual" >&2
        exit 1
    fi
}

assert_assignment mkvtoolnix_version 101.0
assert_assignment \
    mkvtoolnix_dmg_sha256 \
    2fc66191411dca98b6239a623f5de376eac9c2ddd176aa87d13723737c5f795f
assert_assignment \
    mkvtoolnix_source_sha256 \
    f638b299e49cdd4efc4ab3c68dbb593ed6a61bd01bf8862da74ef7fb4d181ce8

grep -Fq \
    "MKVToolNix-\$mkvtoolnix_version-1-universal.dmg" \
    "$runtime_script"
grep -Fq \
    "mkvtoolnix-\$mkvtoolnix_version.tar.xz" \
    "$runtime_script"

echo "runtime version pin tests passed"
