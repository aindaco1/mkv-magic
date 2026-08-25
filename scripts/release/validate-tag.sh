#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <vMAJOR.MINOR.PATCH>" >&2
    exit 64
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tag="$1"
"$repo_root/scripts/release/validate-tag-format.sh" "$tag"
cd "$repo_root"
if [[ "$(git rev-parse "$tag^{commit}")" != "$(git rev-parse HEAD)" ]]; then
    echo "release tag does not identify checked-out commit" >&2
    exit 1
fi
"$repo_root/scripts/release/verify-main-containment.sh" HEAD
verification="$(git tag -v "$tag" 2>&1)" || {
    echo "$verification" >&2
    exit 1
}
echo "$verification"
