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
    local architecture
    local tool
    mkdir -p "$fixture/arm64/libs" "$fixture/x86_64/libs"
    for architecture in arm64 x86_64; do
        for tool in ffmpeg ffprobe mkvmerge mkvpropedit mkvextract; do
            printf '%s-%s-before\n' "$architecture" "$tool" \
                > "$fixture/$architecture/$tool"
        done
        printf '%s-library-before\n' "$architecture" \
            > "$fixture/$architecture/libs/libQt6Core.6.dylib"
        jq -n \
            --arg architecture "$architecture" \
            --arg ffmpeg "$(shasum -a 256 "$fixture/$architecture/ffmpeg" | awk '{print $1}')" \
            --arg ffprobe "$(shasum -a 256 "$fixture/$architecture/ffprobe" | awk '{print $1}')" \
            --arg mkvmerge "$(shasum -a 256 "$fixture/$architecture/mkvmerge" | awk '{print $1}')" \
            --arg mkvpropedit "$(shasum -a 256 "$fixture/$architecture/mkvpropedit" | awk '{print $1}')" \
            --arg mkvextract "$(shasum -a 256 "$fixture/$architecture/mkvextract" | awk '{print $1}')" \
            --arg library "$(shasum -a 256 "$fixture/$architecture/libs/libQt6Core.6.dylib" | awk '{print $1}')" \
            '{
                schema: "mkv-magic-tool-manifest-v1",
                platform: "macos",
                architecture: $architecture,
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
            }' > "$fixture/$architecture/manifest.json"
    done
}

assert_manifest_hashes() {
    local fixture="$1"
    local architecture
    local relative_path
    local expected
    local actual
    for architecture in arm64 x86_64; do
        while IFS= read -r relative_path; do
            expected="$(
                jq -r --arg path "$relative_path" \
                    '(.tools[] | select(.path == $path) | .sha256) //
                     (.libraries[] | select(.path == $path) | .sha256)' \
                    "$fixture/$architecture/manifest.json"
            )"
            actual="$(shasum -a 256 "$fixture/$architecture/$relative_path" | awk '{print $1}')"
            if [[ "$expected" != "$actual" ]]; then
                echo "resealed manifest hash does not match $architecture/$relative_path" >&2
                exit 1
            fi
        done < <(
            jq -r '.tools[].path, .libraries[].path' \
                "$fixture/$architecture/manifest.json"
        )
    done
}

resignable="$test_root/resignable"
make_fixture "$resignable"
"$repo_root/scripts/release/reseal-tool-manifests.swift" "$resignable"
assert_manifest_hashes "$resignable"

arm_build_before="$(shasum -a 256 "$resignable/arm64/build-manifest.json" | awk '{print $1}')"
x86_build_before="$(shasum -a 256 "$resignable/x86_64/build-manifest.json" | awk '{print $1}')"
for architecture in arm64 x86_64; do
    printf '%s-ffmpeg-after-resigning\n' "$architecture" \
        > "$resignable/$architecture/ffmpeg"
    printf '%s-library-after-resigning\n' "$architecture" \
        > "$resignable/$architecture/libs/libQt6Core.6.dylib"
done
"$repo_root/scripts/release/reseal-tool-manifests.swift" "$resignable"
assert_manifest_hashes "$resignable"

if [[ "$arm_build_before" != "$(shasum -a 256 "$resignable/arm64/build-manifest.json" | awk '{print $1}')" || \
      "$x86_build_before" != "$(shasum -a 256 "$resignable/x86_64/build-manifest.json" | awk '{print $1}')" ]]; then
    echo "resealing replaced immutable build provenance" >&2
    exit 1
fi

invalid="$test_root/invalid"
make_fixture "$invalid"
printf '{}\n' > "$invalid/arm64/build-manifest.json"
if "$repo_root/scripts/release/reseal-tool-manifests.swift" "$invalid" \
    >/dev/null 2>&1; then
    echo "resealing accepted an invalid existing build manifest" >&2
    exit 1
fi

echo "tool manifest resealing tests passed"
