#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-tag-containment.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

test_repo="$test_root/repository"
mkdir "$test_repo"
git -C "$test_repo" init -q
git -C "$test_repo" config user.name "MKV Magic Test"
git -C "$test_repo" config user.email "mkv-magic-test@example.invalid"
printf 'reviewed release\n' > "$test_repo/fixture.txt"
git -C "$test_repo" add fixture.txt
git -C "$test_repo" commit -q -m 'reviewed release'
git -C "$test_repo" branch -M main
reviewed_commit="$(git -C "$test_repo" rev-parse HEAD)"
git -C "$test_repo" update-ref refs/remotes/origin/main "$reviewed_commit"
git -C "$test_repo" switch -q --detach "$reviewed_commit"
git -C "$test_repo" branch -D main >/dev/null

validator="$repo_root/scripts/release/verify-main-containment.sh"
(
    cd "$test_repo"
    "$validator" HEAD >/dev/null
)

printf 'unreviewed release\n' > "$test_repo/fixture.txt"
git -C "$test_repo" add fixture.txt
git -C "$test_repo" commit -q -m 'unreviewed release'
if (
    cd "$test_repo"
    "$validator" HEAD >/dev/null 2>&1
); then
    echo "main-containment validator accepted an unreviewed commit" >&2
    exit 1
fi

for workflow in \
    "$repo_root/.github/workflows/release.yml" \
    "$repo_root/.github/workflows/publish-release.yml"; do
    if ! grep -Fq \
        'refs/heads/main:refs/remotes/origin/main' "$workflow"; then
        echo "release workflow does not refresh origin/main: $workflow" >&2
        exit 1
    fi
done

echo "release tag containment tests passed"
