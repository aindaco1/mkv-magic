#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || "$1" != /* || "$2" != /* ]]; then
    echo "usage: $0 <absolute-cache-directory> <absolute-runtime-directory>" >&2
    exit 64
fi
cache_root="$1"
tool_root="$2"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/ci/tool-source-cache.sh"
"$repo_root/scripts/ci/check-tool-tree.sh" "$tool_root"
mkv_magic_verify_tool_source_cache "$cache_root" "$tool_root/SOURCES.json"
echo "verified runtime source cache"
