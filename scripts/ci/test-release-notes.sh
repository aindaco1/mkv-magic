#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-release-notes.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

validator="$repo_root/scripts/release/validate-release-notes.sh"
notes="$repo_root/docs/releases/0.1.0.md"

"$validator" 0.1.0 >/dev/null

expect_rejection() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "release-notes validator accepted $description" >&2
        exit 1
    fi
}

wrong_version="$test_root/wrong-version.md"
sed '1s/0\.1\.0/0.2.0/' "$notes" > "$wrong_version"
expect_rejection "a mismatched heading" \
    env MKV_MAGIC_RELEASE_NOTES_PATH="$wrong_version" "$validator" 0.1.0

missing_limitations="$test_root/missing-limitations.md"
sed '/^## Current limitations$/d' "$notes" > "$missing_limitations"
expect_rejection "missing limitations" \
    env MKV_MAGIC_RELEASE_NOTES_PATH="$missing_limitations" "$validator" 0.1.0

placeholder_notes="$test_root/placeholder.md"
cp "$notes" "$placeholder_notes"
printf '\nTODO: finish this release.\n' >> "$placeholder_notes"
expect_rejection "placeholder language" \
    env MKV_MAGIC_RELEASE_NOTES_PATH="$placeholder_notes" "$validator" 0.1.0

linked_notes="$test_root/linked.md"
ln -s "$notes" "$linked_notes"
expect_rejection "symbolic-link notes" \
    env MKV_MAGIC_RELEASE_NOTES_PATH="$linked_notes" "$validator" 0.1.0

oversized_notes="$test_root/oversized.md"
dd if=/dev/zero of="$oversized_notes" bs=65537 count=1 2>/dev/null
expect_rejection "oversized notes" \
    env MKV_MAGIC_RELEASE_NOTES_PATH="$oversized_notes" "$validator" 0.1.0

expect_rejection "the disposable fixture version" "$validator" 0.0.0
expect_rejection "an absent version" "$validator" 9.9.9

echo "release notes tests passed"
