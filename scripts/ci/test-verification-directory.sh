#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$repo_root/scripts/release/create-verification-directory.sh"
fixture_root="$(mktemp -d)"
local_directory=''
cleanup() {
    if [[ -n "$local_directory" ]]; then rmdir "$local_directory"; fi
    /bin/rm -rf -- "$fixture_root"
}
trap cleanup EXIT

local_directory="$(env -u RUNNER_TEMP TMPDIR="$fixture_root" "$helper" local-test)"
expected_parent="$(cd "$repo_root/.build/verification-tmp" && pwd -P)"
[[ "$(dirname "$local_directory")" == "$expected_parent" ]]
[[ -d "$local_directory" && ! -L "$local_directory" ]]
[[ "$(stat -f '%Lp' "$local_directory")" == 700 ]]

mkdir "$fixture_root/runner temp"
runner_directory="$(RUNNER_TEMP="$fixture_root/runner temp" "$helper" runner-test)"
runner_parent="$(cd "$fixture_root/runner temp" && pwd -P)"
[[ "$(dirname "$runner_directory")" == "$runner_parent" ]]
[[ -d "$runner_directory" && ! -L "$runner_directory" ]]

if RUNNER_TEMP=relative "$helper" invalid-parent >/dev/null 2>&1; then exit 1; fi
if "$helper" '../escape' >/dev/null 2>&1; then exit 1; fi
echo "verification directory tests passed"
