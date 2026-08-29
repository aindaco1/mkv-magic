#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/ci/architecture.sh"
cd "$repo_root"

./scripts/ci/source-contract-gate.sh

swift test --disable-automatic-resolution
swift build -c release --arch arm64 --arch x86_64 \
    --product MKVMagic --disable-automatic-resolution
binary_path="$(
    swift build -c release --arch arm64 --arch x86_64 \
        --product MKVMagic --disable-automatic-resolution --show-bin-path
)/MKVMagic"
architectures="$(lipo -archs "$binary_path")"
if ! mkv_magic_is_universal_architecture_set "$architectures"; then
    echo "expected Universal app executable, found: $architectures" >&2
    exit 1
fi
git diff --check
echo "source validation passed"
