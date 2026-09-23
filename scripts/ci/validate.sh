#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/ci/architecture.sh"
cd "$repo_root"

swift_arguments=(--disable-automatic-resolution)
if [[ -n "${MKV_MAGIC_SWIFT_SCRATCH_PATH:-}" ]]; then
    if [[ "$MKV_MAGIC_SWIFT_SCRATCH_PATH" != /* ]]; then
        echo "MKV_MAGIC_SWIFT_SCRATCH_PATH must be absolute" >&2
        exit 1
    fi
    swift_arguments+=(--scratch-path "$MKV_MAGIC_SWIFT_SCRATCH_PATH")
fi

./scripts/ci/source-contract-gate.sh

swift test "${swift_arguments[@]}"
swift build -c release --arch arm64 --arch x86_64 \
    "${swift_arguments[@]}" --product MKVMagic
binary_path="$(
    swift build -c release --arch arm64 --arch x86_64 \
        "${swift_arguments[@]}" --product MKVMagic --show-bin-path
)/MKVMagic"
architectures="$(lipo -archs "$binary_path")"
if ! mkv_magic_is_universal_architecture_set "$architectures"; then
    echo "expected Universal app executable, found: $architectures" >&2
    exit 1
fi
git diff --check
echo "source validation passed"
