#!/usr/bin/env bash
set -euo pipefail
script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/release/archive-source.sh
source "$script_root/release/archive-source.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/mkv-source-fixture.XXXXXX")"
trap '/bin/rm -rf -- "$fixture"' EXIT
export GIT_AUTHOR_NAME="Source archive test" GIT_AUTHOR_EMAIL="test@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
git init -q "$fixture/platform"
printf 'MIT fixture\n' > "$fixture/platform/LICENSE"
git -C "$fixture/platform" add LICENSE
git -C "$fixture/platform" commit -qm "Platform fixture"
git init -q "$fixture/app"
git -C "$fixture/app" -c protocol.file.allow=always submodule add -q \
    "$fixture/platform" shared/dust-wave-platform
printf 'Application source\n' > "$fixture/app/Package.swift"
git -C "$fixture/app" add .
git -C "$fixture/app" commit -qm "App fixture"
mkv_magic_archive_source "$fixture/app" 1.2.3 "$fixture/source.tar.gz"
archive_commit="$(gzip -dc "$fixture/source.tar.gz" | git get-tar-commit-id)"
test "$archive_commit" = "$(git -C "$fixture/app" rev-parse HEAD)"
mkdir "$fixture/extracted"
tar -xzf "$fixture/source.tar.gz" -C "$fixture/extracted"
cmp "$fixture/platform/LICENSE" \
    "$fixture/extracted/mkv-magic-1.2.3/shared/dust-wave-platform/LICENSE"
cmp "$fixture/app/Package.swift" "$fixture/extracted/mkv-magic-1.2.3/Package.swift"
if mkv_magic_archive_source "$fixture/app" 1.2.3 "$fixture/source.tar.gz"; then
    echo "source archive overwrote existing output" >&2; exit 1
fi
git -C "$fixture/app/shared/dust-wave-platform" commit --allow-empty -qm "Drift"
if mkv_magic_archive_source "$fixture/app" 1.2.3 "$fixture/drift.tar.gz"; then
    echo "source archive accepted a different Platform commit" >&2; exit 1
fi
test ! -e "$fixture/drift.tar.gz"
echo "Pinned dependency source, provenance, overwrite and drift checks passed"
