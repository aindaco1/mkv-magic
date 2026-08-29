#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-reseal-test.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

make_fixture() {
    local fixture="$1"
    local tool
    mkdir -p "$fixture/universal/libs"
    for tool in ffmpeg ffprobe mkvmerge mkvpropedit mkvextract; do
        printf 'universal-%s-before\n' "$tool" > "$fixture/universal/$tool"
    done
    printf 'universal-library-before\n' \
        > "$fixture/universal/libs/libQt6Core.6.dylib"
    jq -n \
            --arg ffmpeg "$(shasum -a 256 "$fixture/universal/ffmpeg" | awk '{print $1}')" \
            --arg ffprobe "$(shasum -a 256 "$fixture/universal/ffprobe" | awk '{print $1}')" \
            --arg mkvmerge "$(shasum -a 256 "$fixture/universal/mkvmerge" | awk '{print $1}')" \
            --arg mkvpropedit "$(shasum -a 256 "$fixture/universal/mkvpropedit" | awk '{print $1}')" \
            --arg mkvextract "$(shasum -a 256 "$fixture/universal/mkvextract" | awk '{print $1}')" \
            --arg library "$(shasum -a 256 "$fixture/universal/libs/libQt6Core.6.dylib" | awk '{print $1}')" \
            '{
                schema: "mkv-magic-tool-manifest-v2",
                platform: "macos",
                architecture: "universal",
                tools: [
                    {name: "ffmpeg", path: "ffmpeg", sha256: $ffmpeg},
                    {name: "ffprobe", path: "ffprobe", sha256: $ffprobe},
                    {name: "mkvmerge", path: "mkvmerge", sha256: $mkvmerge},
                    {name: "mkvpropedit", path: "mkvpropedit", sha256: $mkvpropedit},
                    {name: "mkvextract", path: "mkvextract", sha256: $mkvextract}
                ],
                libraries: [
                    {path: "libs/libQt6Core.6.dylib", sha256: $library}
                ]
            }' > "$fixture/universal/manifest.json"
}

assert_manifest_hashes() {
    local fixture="$1"
    local relative_path
    local expected
    local actual
    while IFS= read -r relative_path; do
        expected="$(
            jq -r --arg path "$relative_path" \
                '(.tools[] | select(.path == $path) | .sha256) //
                 (.libraries[] | select(.path == $path) | .sha256)' \
                "$fixture/universal/manifest.json"
        )"
        actual="$(shasum -a 256 "$fixture/universal/$relative_path" | awk '{print $1}')"
        if [[ "$expected" != "$actual" ]]; then
            echo "resealed manifest hash does not match universal/$relative_path" >&2
            exit 1
        fi
    done < <(
        jq -r '.tools[].path, .libraries[].path' \
            "$fixture/universal/manifest.json"
    )
}

resignable="$test_root/resignable"
make_fixture "$resignable"
"$repo_root/scripts/release/reseal-tool-manifests.swift" "$resignable"
assert_manifest_hashes "$resignable"

build_before="$(shasum -a 256 "$resignable/universal/build-manifest.json" | awk '{print $1}')"
printf 'universal-ffmpeg-after-resigning\n' > "$resignable/universal/ffmpeg"
printf 'universal-library-after-resigning\n' \
    > "$resignable/universal/libs/libQt6Core.6.dylib"
"$repo_root/scripts/release/reseal-tool-manifests.swift" "$resignable"
assert_manifest_hashes "$resignable"

if [[ "$build_before" != "$(shasum -a 256 "$resignable/universal/build-manifest.json" | awk '{print $1}')" ]]; then
    echo "resealing replaced immutable build provenance" >&2
    exit 1
fi

invalid="$test_root/invalid"
make_fixture "$invalid"
printf '{}\n' > "$invalid/universal/build-manifest.json"
if "$repo_root/scripts/release/reseal-tool-manifests.swift" "$invalid" \
    >/dev/null 2>&1; then
    echo "resealing accepted an invalid existing build manifest" >&2
    exit 1
fi

echo "tool manifest resealing tests passed"
