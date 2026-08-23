#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
swift test --enable-code-coverage --disable-automatic-resolution
report_path="$(swift test --show-codecov-path)"
if [[ ! -f "$report_path" || -L "$report_path" ]]; then
    echo "Swift coverage report was not produced" >&2
    exit 1
fi
echo "$report_path"
