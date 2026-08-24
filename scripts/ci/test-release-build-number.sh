#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-release-build.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

test_repo="$test_root/repository"
mkdir "$test_repo"
git -C "$test_repo" init -q
git -C "$test_repo" config user.name "MKV Magic Test"
git -C "$test_repo" config user.email "mkv-magic-test@example.invalid"
printf 'fixture\n' > "$test_repo/fixture.txt"
git -C "$test_repo" add fixture.txt
GIT_AUTHOR_DATE='2001-01-01T00:00:00Z' \
GIT_COMMITTER_DATE='2001-01-01T00:00:00Z' \
    git -C "$test_repo" commit -q -m fixture
GIT_COMMITTER_DATE='2026-08-26T00:00:00Z' \
    git -C "$test_repo" tag -a v1.2.3 -m 'release fixture'
git -C "$test_repo" tag v1.2.4

deriver="$repo_root/scripts/release/derive-release-build-number.sh"

run_deriver() {
    (
        cd "$test_repo"
        "$deriver" "$@"
    )
}

expect_rejection() {
    local description="$1"
    shift
    if run_deriver "$@" >/dev/null 2>&1; then
        echo "release build deriver accepted $description" >&2
        exit 1
    fi
}

derived="$(run_deriver v1.2.3 20260825)"
if [[ "$derived" != 1787702400 ]]; then
    echo "expected signed tag timestamp 1787702400, found: $derived" >&2
    exit 1
fi

expect_rejection "the prior build as an equal lower bound" \
    v1.2.3 1787702400
expect_rejection "a build outside the signed 32-bit range" \
    v1.2.3 2147483648
expect_rejection "an integer too large for shell arithmetic" \
    v1.2.3 999999999999999999999999999999
expect_rejection "a lightweight tag" \
    v1.2.4 20260825
expect_rejection "an absent tag" \
    v1.2.5 20260825
expect_rejection "a malformed tag" \
    release-1.2.3 20260825
expect_rejection "a leading-zero minimum" \
    v1.2.3 020260825

echo "release build number tests passed"
