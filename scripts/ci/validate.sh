#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

./scripts/ci/check-local-only.sh
./scripts/ci/check-appkit-accessibility.sh
./scripts/ci/check-user-facing-errors.sh
./scripts/ci/scan-secrets.sh
./scripts/ci/verify-actions-pinning.sh
actionlint -color
./scripts/ci/test-dmg-verification.sh
./scripts/ci/test-downloaded-release-verification.sh
./scripts/ci/test-publication-acceptance.sh
./scripts/ci/test-tool-tree-layout.sh

shell_files=()
while IFS= read -r -d '' shell_file; do
    shell_files+=("$shell_file")
done < <(find scripts -type f -name '*.sh' -print0)
if [[ "${#shell_files[@]}" -gt 0 ]]; then
    shellcheck -x "${shell_files[@]}"
fi

swift format lint --strict --configuration .swift-format --recursive \
    Package.swift Sources Tests scripts/ci/check-coverage.swift

resolved_before="$(shasum -a 256 Package.resolved | awk '{print $1}')"
swift package resolve
resolved_after="$(shasum -a 256 Package.resolved | awk '{print $1}')"
if [[ "$resolved_before" != "$resolved_after" ]]; then
    echo "swift package resolve changed Package.resolved" >&2
    git diff -- Package.resolved >&2
    exit 1
fi

swift test --disable-automatic-resolution
swift build -c release --arch arm64 --arch x86_64 \
    --product MKVMagic --disable-automatic-resolution
binary_path="$(
    swift build -c release --arch arm64 --arch x86_64 \
        --product MKVMagic --disable-automatic-resolution --show-bin-path
)/MKVMagic"
architectures="$(lipo -archs "$binary_path")"
if [[ "$architectures" != "x86_64 arm64" && "$architectures" != "arm64 x86_64" ]]; then
    echo "expected Universal app executable, found: $architectures" >&2
    exit 1
fi
git diff --check
echo "source validation passed"
