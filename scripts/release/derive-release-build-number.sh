#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <vMAJOR.MINOR.PATCH> <exclusive-minimum-build>" >&2
    exit 64
fi

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tag="$1"
minimum_build="$2"
maximum_build=2147483647

exceeds_maximum_build() {
    local value="$1"
    if (( ${#value} > ${#maximum_build} )); then
        return 0
    fi
    if (( ${#value} < ${#maximum_build} )); then
        return 1
    fi
    (( 10#$value > maximum_build ))
}

"$script_root/scripts/release/validate-tag-format.sh" "$tag"
if [[ ! "$minimum_build" =~ ^[1-9][0-9]*$ ]]; then
    echo "minimum build must be a positive decimal integer without leading zeroes" >&2
    exit 64
fi
if exceeds_maximum_build "$minimum_build"; then
    echo "minimum build exceeds the supported signed 32-bit range" >&2
    exit 64
fi

checkout_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "release build number must be derived from a Git checkout" >&2
    exit 1
}
cd "$checkout_root"
object_type="$(git for-each-ref --format='%(objecttype)' "refs/tags/$tag")"
if [[ "$object_type" != tag ]]; then
    echo "release build number requires an existing annotated tag: $tag" >&2
    exit 1
fi

build_number="$(git for-each-ref --format='%(taggerdate:unix)' "refs/tags/$tag")"
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "annotated release tag has no valid positive tagger timestamp: $tag" >&2
    exit 1
fi
if exceeds_maximum_build "$build_number"; then
    echo "release tag timestamp exceeds the supported signed 32-bit range" >&2
    exit 1
fi
if (( 10#$build_number <= 10#$minimum_build )); then
    echo "release build $build_number must be newer than build $minimum_build" >&2
    exit 1
fi

printf '%s\n' "$build_number"
