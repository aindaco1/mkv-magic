#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="$repo_root/scripts/tools/extract-ci-runtime.py"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-runtime-extraction-test.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

fixture="$test_root/fixture/mkv-magic-ci-runtime"
mkdir -p "$fixture/runtime/arm64" "$fixture/sources/ffmpeg-9.0.1"
printf '{}\n' > "$fixture/metadata.json"
printf 'binary\n' > "$fixture/runtime/arm64/ffmpeg"
chmod 0755 "$fixture/runtime/arm64/ffmpeg"
printf 'source\n' > "$fixture/sources/ffmpeg-9.0.1/ffmpeg-9.0.1.tar.xz"
safe_archive="$test_root/safe.tar.gz"
COPYFILE_DISABLE=1 tar -czf "$safe_archive" -C "$test_root/fixture" \
    mkv-magic-ci-runtime
python3 "$extractor" "$safe_archive" "$test_root/extracted"
test -x "$test_root/extracted/mkv-magic-ci-runtime/runtime/arm64/ffmpeg"
test ! -x "$test_root/extracted/mkv-magic-ci-runtime/metadata.json"

python3 - "$test_root/traversal.tar.gz" "$test_root/link.tar.gz" <<'PY'
import io
import sys
import tarfile

traversal, link = sys.argv[1:]
with tarfile.open(traversal, "w:gz") as archive:
    payload = b"escape\n"
    member = tarfile.TarInfo("mkv-magic-ci-runtime/../../escape")
    member.size = len(payload)
    archive.addfile(member, io.BytesIO(payload))
with tarfile.open(link, "w:gz") as archive:
    member = tarfile.TarInfo("mkv-magic-ci-runtime/runtime-link")
    member.type = tarfile.SYMTYPE
    member.linkname = "/tmp"
    archive.addfile(member)
PY
if python3 "$extractor" "$test_root/traversal.tar.gz" \
    "$test_root/traversal-output" >/dev/null 2>&1; then
    echo "runtime artifact extractor accepted path traversal" >&2
    exit 1
fi
if python3 "$extractor" "$test_root/link.tar.gz" \
    "$test_root/link-output" >/dev/null 2>&1; then
    echo "runtime artifact extractor accepted a symbolic link" >&2
    exit 1
fi
test ! -e "$test_root/escape"
echo "runtime artifact extraction tests passed"
