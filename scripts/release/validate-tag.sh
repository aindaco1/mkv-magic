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
if [[ "$(git branch --contains HEAD --format='%(refname:short)' | grep -x main || true)" != main ]]; then
    echo "release commit is not contained by main" >&2
    exit 1
fi
verification="$(git tag -v "$tag" 2>&1)" || {
    echo "$verification" >&2
    exit 1
}
echo "$verification"
