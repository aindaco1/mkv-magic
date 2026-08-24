#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <absolute-download-directory> <version> <owner/repository>" >&2
    exit 64
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/release/downloaded-release-verification.sh"
download_root="$1"
version="$2"
repository="$3"
if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "release repository is invalid" >&2
    exit 64
fi

validate_mkv_magic_downloaded_release "$download_root" "$version"

attestation_flags=(
    --repo "$repository"
    --deny-self-hosted-runners
    --signer-workflow "github.com/$repository/.github/workflows/release.yml"
    --source-ref "refs/tags/v$version"
)
if [[ -n "${MKV_MAGIC_EXPECTED_SOURCE_DIGEST:-}" ]]; then
    if [[ ! "$MKV_MAGIC_EXPECTED_SOURCE_DIGEST" =~ ^[0-9a-f]{40}$ ]]; then
        echo "expected release source digest is invalid" >&2
        exit 64
    fi
    attestation_flags+=(--source-digest "$MKV_MAGIC_EXPECTED_SOURCE_DIGEST")
fi

artifact=''
while IFS= read -r artifact; do
    gh attestation verify "$download_root/$artifact" "${attestation_flags[@]}"
done < <(mkv_magic_attested_release_asset_names "$version")

MKV_MAGIC_REQUIRE_DISTRIBUTION=1 \
MKV_MAGIC_VERIFY_BUNDLED_TOOLS=1 \
    "$repo_root/scripts/release/verify-dmg.sh" \
        "$download_root/MKV-Magic-$version-universal.dmg"

echo "verified downloaded MKV Magic $version release"
