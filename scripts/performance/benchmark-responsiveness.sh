#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: benchmark-responsiveness.sh [--quick] [--enforce]

Run MKV Magic's synthetic, path-free responsiveness probe. The standard probe
measures workflow compilation for a 200-track file and production-queue
scheduling for 5,000 jobs. --quick uses smaller development workloads.
--enforce exits nonzero when a p95 latency exceeds its documented budget.
EOF
}

arguments=()
for argument in "$@"; do
    case "$argument" in
        --quick | --enforce) arguments+=("$argument") ;;
        --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
swift run -c release --disable-automatic-resolution \
    MKVMagicPerformanceProbe "${arguments[@]}"
