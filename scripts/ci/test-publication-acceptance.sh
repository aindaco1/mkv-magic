#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-publication-acceptance.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

tag=v1.2.3
dmg_path="$test_root/MKV-Magic-1.2.3-universal.dmg"
printf 'fixed candidate\n' > "$dmg_path"
digest="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
validator="$repo_root/scripts/release/validate-publication-acceptance.sh"
publication_workflow="$repo_root/.github/workflows/publish-release.yml"

run_valid() {
    MKV_MAGIC_APPLE_SILICON_ACCEPTED_DMG_SHA256="$digest" \
    MKV_MAGIC_INTEL_ACCEPTED_DMG_SHA256="$digest" \
    MKV_MAGIC_UPDATE_ACCEPTED_DMG_SHA256="$digest" \
    MKV_MAGIC_PUBLICATION_CONFIRMATION="publish-$tag" \
        "$validator" "$dmg_path" "$tag" >/dev/null
}

expect_rejection() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "publication validator accepted $description" >&2
        exit 1
    fi
}

run_valid

expect_rejection "a missing hardware acceptance" \
    env \
        MKV_MAGIC_APPLE_SILICON_ACCEPTED_DMG_SHA256="$digest" \
        MKV_MAGIC_UPDATE_ACCEPTED_DMG_SHA256="$digest" \
        MKV_MAGIC_PUBLICATION_CONFIRMATION="publish-$tag" \
        "$validator" "$dmg_path" "$tag"

wrong_digest="$(printf 'different candidate\n' | shasum -a 256 | awk '{print $1}')"
expect_rejection "a mismatched updater candidate" \
    env \
        MKV_MAGIC_APPLE_SILICON_ACCEPTED_DMG_SHA256="$digest" \
        MKV_MAGIC_INTEL_ACCEPTED_DMG_SHA256="$digest" \
        MKV_MAGIC_UPDATE_ACCEPTED_DMG_SHA256="$wrong_digest" \
        MKV_MAGIC_PUBLICATION_CONFIRMATION="publish-$tag" \
        "$validator" "$dmg_path" "$tag"

expect_rejection "an unconfirmed publication" \
    env \
        MKV_MAGIC_APPLE_SILICON_ACCEPTED_DMG_SHA256="$digest" \
        MKV_MAGIC_INTEL_ACCEPTED_DMG_SHA256="$digest" \
        MKV_MAGIC_UPDATE_ACCEPTED_DMG_SHA256="$digest" \
        MKV_MAGIC_PUBLICATION_CONFIRMATION="publish-v9.9.9" \
        "$validator" "$dmg_path" "$tag"

symlink_path="$test_root/symlink"
mkdir "$symlink_path"
ln -s "$dmg_path" "$symlink_path/MKV-Magic-1.2.3-universal.dmg"
expect_rejection "a symbolic-link candidate" \
    env \
        MKV_MAGIC_APPLE_SILICON_ACCEPTED_DMG_SHA256="$digest" \
        MKV_MAGIC_INTEL_ACCEPTED_DMG_SHA256="$digest" \
        MKV_MAGIC_UPDATE_ACCEPTED_DMG_SHA256="$digest" \
        MKV_MAGIC_PUBLICATION_CONFIRMATION="publish-$tag" \
        "$validator" "$symlink_path/MKV-Magic-1.2.3-universal.dmg" "$tag"

# These are intentionally literal workflow source fragments.
# shellcheck disable=SC2016
for immutable_readback_command in \
    'gh release verify "$RELEASE_TAG"' \
    'gh release verify-asset "$RELEASE_TAG"'; do
    if ! grep -Fq "$immutable_readback_command" "$publication_workflow"; then
        echo "publication workflow is missing immutable release readback" >&2
        exit 1
    fi
done
if grep -Fq -- '--draft=true' "$publication_workflow"; then
    echo "immutable publication workflow still attempts an impossible re-draft" >&2
    exit 1
fi

echo "publication acceptance tests passed"
