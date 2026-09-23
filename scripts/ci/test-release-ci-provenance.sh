#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ci_workflow="$repo_root/.github/workflows/ci.yml"
release_workflow="$repo_root/.github/workflows/release.yml"
restore_script="$repo_root/scripts/release/restore-ci-runtime.sh"

for required_fragment in \
    'actions: read' \
    'Restore exact successful CI runtime and security evidence' \
    './scripts/release/restore-ci-runtime.sh' \
    './scripts/ci/release-source-gate.sh'; do
    if ! grep -Fq "$required_fragment" "$release_workflow"; then
        echo "release workflow is missing CI provenance control: $required_fragment" >&2
        exit 1
    fi
done

# CI signs a disposable package ad hoc; the reporter deliberately requires a
# production host and Team ID. Keep app/media execution in CI and require the
# complete reporting IPC check on the downloaded Developer ID-signed release.
for required_fragment in \
    '--app-baseline-probe' \
    'MKV_MAGIC_VERIFY_BUNDLED_TOOLS=1' \
    'MKV_MAGIC_VERIFY_BUNDLED_FIXTURE=1'; do
    if ! grep -Fq -- "$required_fragment" "$ci_workflow"; then
        echo "CI fixture is missing native app/media coverage: $required_fragment" >&2
        exit 1
    fi
done
if grep -Fq 'MKV_MAGIC_VERIFY_NATIVE_RELEASE=1' "$ci_workflow"; then
    echo "ad-hoc CI fixture cannot impersonate a production reporting host" >&2
    exit 1
fi
for required_fragment in \
    'MKV_MAGIC_REQUIRE_DISTRIBUTION=1' \
    'MKV_MAGIC_VERIFY_NATIVE_RELEASE=1'; do
    if ! grep -Fq "$required_fragment" \
        "$repo_root/scripts/release/verify-downloaded-release.sh"; then
        echo "downloaded release is missing production verification: $required_fragment" >&2
        exit 1
    fi
done
if ! grep -Fq 'try await ReportSubmissionClient().checkAvailability()' \
    "$repo_root/Sources/MKVMagic/NativeReleaseVerification.swift"; then
    echo "production native verification must check the reporting peer" >&2
    exit 1
fi
if rg -n 'xcodebuild -version[[:space:]]*\|[[:space:]]*head' \
    "$ci_workflow" "$release_workflow" \
    "$repo_root/scripts/tools/package-ci-runtime.sh"; then
    echo "Xcode version detection can terminate xcodebuild through a short pipe" >&2
    exit 1
fi
if ! grep -Fq './scripts/ci/source-contract-gate.sh' \
    "$repo_root/scripts/ci/release-source-gate.sh"; then
    echo "release source gate does not share the CI source contract" >&2
    exit 1
fi
if grep -Fq './scripts/tools/build-runtime.sh' "$release_workflow"; then
    echo "release workflow still rebuilds an already verified media runtime" >&2
    exit 1
fi

for required_fragment in \
    'actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9' \
    'actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8' \
    'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' \
    "github.event_name == 'push' && github.ref == 'refs/heads/main'" \
    './scripts/tools/package-ci-runtime.sh'; do
    if ! grep -Fq "$required_fragment" "$ci_workflow"; then
        echo "CI workflow is missing trusted runtime control: $required_fragment" >&2
        exit 1
    fi
done

for required_fragment in \
    "--workflow \"\$workflow\"" \
    "--commit \"\$commit\"" \
    '--branch main' \
    '--event push' \
    '--status success' \
    'required_run CI' \
    'required_run CodeQL' \
    "--signer-workflow \"github.com/\$repository/.github/workflows/ci.yml\"" \
    '--source-ref refs/heads/main' \
    "--source-digest \"\$commit\"" \
    '--deny-self-hosted-runners'; do
    if ! grep -Fq -- "$required_fragment" "$restore_script"; then
        echo "runtime restore is missing provenance policy: $required_fragment" >&2
        exit 1
    fi
done
echo "release CI provenance tests passed"
