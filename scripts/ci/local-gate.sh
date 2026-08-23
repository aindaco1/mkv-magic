#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
./scripts/ci/preflight.sh
git diff --check
./scripts/ci/validate.sh
./scripts/ci/coverage.sh
./scripts/ci/sanitizers.sh
./scripts/ci/package-gate.sh
git diff --check
echo "complete local gate passed"
