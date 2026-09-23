#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[a-z0-9-]+$ ]]; then
    echo "usage: $0 <lowercase-directory-prefix>" >&2
    exit 64
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Sandboxed app launches from macOS's private process TMPDIR can emit sandbox
# extension denials. Use the runner workspace or a local generated directory.
verification_parent="${RUNNER_TEMP:-$repo_root/.build/verification-tmp}"
if [[ "$verification_parent" != /* ]]; then
    echo "verification parent must be an absolute directory" >&2
    exit 64
fi
mkdir -p "$verification_parent"
verification_parent="$(cd "$verification_parent" && pwd -P)"
mktemp -d "$verification_parent/$1.XXXXXX"
