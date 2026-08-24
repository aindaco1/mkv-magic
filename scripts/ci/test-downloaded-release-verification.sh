#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/release/downloaded-release-verification.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-release-verification-test.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT
version=1.2.3
source_commit=''
source_tree=''
source_template="$test_root/MKV-Magic-$version-corresponding-source.zip"

make_source_material() {
    local material="$test_root/source-material"
    local source_repo="$material/repository"
    local bundle_root="$material/MKV-Magic-$version-corresponding-source"
    local dependency_root="$bundle_root/dependencies"
    mkdir -p \
        "$source_repo/docs" \
        "$source_repo/scripts/tools" \
        "$source_repo/scripts/release" \
        "$source_repo/Sources/Fixture" \
        "$dependency_root"

    local ffmpeg="$dependency_root/ffmpeg-9.0.1.tar.xz"
    local nasm="$dependency_root/nasm-3.02.tar.xz"
    local svt="$dependency_root/SVT-AV1-v4.1.0.tar.gz"
    local dav1d="$dependency_root/dav1d-1.5.4.tar.bz2"
    local opus="$dependency_root/opus-1.6.1.tar.gz"
    local zimg="$dependency_root/zimg-release-3.0.6.tar.gz"
    local mkv="$dependency_root/mkvtoolnix-100.0.tar.xz"
    local qt="$dependency_root/qtbase-everywhere-src-6.11.1.tar.xz"
    local dependency
    for dependency in "$ffmpeg" "$nasm" "$svt" "$dav1d" "$opus" "$zimg" "$mkv" "$qt"; do
        printf 'source fixture for %s\n' "$(basename "$dependency")" > "$dependency"
    done
    local ffmpeg_hash
    local nasm_hash
    local svt_hash
    local dav1d_hash
    local opus_hash
    local zimg_hash
    local mkv_hash
    local qt_hash
    ffmpeg_hash="$(shasum -a 256 "$ffmpeg" | awk '{print $1}')"
    nasm_hash="$(shasum -a 256 "$nasm" | awk '{print $1}')"
    svt_hash="$(shasum -a 256 "$svt" | awk '{print $1}')"
    dav1d_hash="$(shasum -a 256 "$dav1d" | awk '{print $1}')"
    opus_hash="$(shasum -a 256 "$opus" | awk '{print $1}')"
    zimg_hash="$(shasum -a 256 "$zimg" | awk '{print $1}')"
    mkv_hash="$(shasum -a 256 "$mkv" | awk '{print $1}')"
    qt_hash="$(shasum -a 256 "$qt" | awk '{print $1}')"
    local mkv_binary_hash='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

    jq -n \
        --arg ffmpeg "$ffmpeg_hash" --arg nasm "$nasm_hash" \
        --arg svt "$svt_hash" --arg dav1d "$dav1d_hash" \
        --arg opus "$opus_hash" --arg zimg "$zimg_hash" \
        --arg mkv "$mkv_hash" --arg mkvBinary "$mkv_binary_hash" \
        --arg qt "$qt_hash" \
        '{
          schema: "mkv-magic-tool-sources-v2",
          minimumMacOS: "13.0",
          ffmpeg: {
            version: "9.0.1", url: "https://ffmpeg.org/releases/fixture",
            sha256: $ffmpeg, network: false, license: "GPL-3.0-or-later",
            configuration: [
              "--disable-autodetect", "--disable-avdevice", "--disable-network",
              "--disable-shared", "--enable-audiotoolbox", "--enable-gpl",
              "--enable-libdav1d", "--enable-libopus", "--enable-libsvtav1",
              "--enable-libzimg", "--enable-static", "--enable-version3",
              "--enable-videotoolbox"
            ]
          },
          nasm: {
            version: "3.02", url: "https://www.nasm.us/fixture", sha256: $nasm,
            buildOnly: true, license: "BSD-2-Clause"
          },
          svtav1: {
            version: "4.1.0", url: "https://gitlab.com/AOMediaCodec/SVT-AV1/fixture",
            sha256: $svt, linkedStatically: true,
            build: ["BUILD_APPS=OFF", "BUILD_SHARED_LIBS=OFF", "BUILD_TESTING=OFF",
              "EXCLUDE_HASH=ON", "NATIVE=OFF", "SVT_AV1_LTO=OFF"],
            license: "BSD-3-Clause-Clear",
            patentLicense: "Alliance for Open Media Patent License 1.0"
          },
          dav1d: {
            version: "1.5.4", url: "https://code.videolan.org/videolan/dav1d/fixture",
            sha256: $dav1d, linkedStatically: true,
            build: ["b_lto=false", "default_library=static", "enable_docs=false",
              "enable_examples=false", "enable_tests=false", "enable_tools=false"],
            license: "BSD-2-Clause"
          },
          opus: {
            version: "1.6.1", url: "https://downloads.xiph.org/releases/opus/fixture",
            sha256: $opus, linkedStatically: true,
            build: ["disable_doc=true", "disable_extra_programs=true",
              "disable_shared=true", "enable_static=true"], license: "BSD-3-Clause"
          },
          zimg: {
            version: "3.0.6", url: "https://github.com/sekrit-twc/zimg/fixture",
            sha256: $zimg, linkedStatically: true,
            build: ["disable_example=true", "disable_shared=true",
              "disable_testapp=true", "disable_unit_test=true", "enable_static=true"],
            license: "WTFPL"
          },
          mkvtoolnix: {
            version: "100.0", binaryURL: "https://mkvtoolnix.download/fixture",
            binarySha256: $mkvBinary, sourceURL: "https://mkvtoolnix.download/fixture",
            sourceSha256: $mkv, license: "GPL-2.0-or-later"
          },
          qtbase: {
            version: "6.11.1", url: "https://download.qt.io/fixture",
            sha256: $qt, license: "LGPL-3.0-only"
          }
        }' > "$bundle_root/SOURCES.json"

    printf 'GPL fixture\n' > "$source_repo/LICENSE"
    printf '// swift-tools-version: 6.0\n' > "$source_repo/Package.swift"
    printf '{"pins":[],"version":3}\n' > "$source_repo/Package.resolved"
    printf '# MKV Magic corresponding source\n' \
        > "$source_repo/docs/CORRESPONDING_SOURCE.md"
    printf '#!/usr/bin/env bash\nfixture\n' \
        > "$source_repo/scripts/release/bundle-corresponding-source.sh"
    {
        printf '#!/usr/bin/env bash\n'
        printf '%s\n' \
            9.0.1 "$ffmpeg_hash" 3.02 "$nasm_hash" 4.1.0 "$svt_hash" \
            1.5.4 "$dav1d_hash" 1.6.1 "$opus_hash" 3.0.6 "$zimg_hash" \
            100.0 "$mkv_binary_hash" "$mkv_hash" 6.11.1 "$qt_hash"
    } > "$source_repo/scripts/tools/build-runtime.sh"
    local index
    for index in {1..14}; do
        printf 'let fixture%s = %s\n' "$index" "$index" \
            > "$source_repo/Sources/Fixture/File$index.swift"
    done
    git -C "$source_repo" init -q
    git -C "$source_repo" add -- .
    git -C "$source_repo" -c user.name='MKV Magic Test' \
        -c user.email='test@example.invalid' commit -qm 'Fixture source'
    source_commit="$(git -C "$source_repo" rev-parse HEAD)"
    source_tree="$(git -C "$source_repo" rev-parse 'HEAD^{tree}')"
    git -C "$source_repo" archive --format=tar.gz \
        --prefix="mkv-magic-$version/" HEAD \
        > "$bundle_root/MKV-Magic-$version-source.tar.gz"
    install -m 0644 "$source_repo/docs/CORRESPONDING_SOURCE.md" \
        "$bundle_root/README.md"
    COPYFILE_DISABLE=1 ditto --norsrc --noextattr -c -k --keepParent \
        "$bundle_root" "$source_template"
}

refresh_evidence() {
    local fixture="$1"
    local sizes="$fixture/ARTIFACT-SIZES.json"
    printf '{"schema":"mkv-magic-artifact-sizes-v1","artifacts":[]}\n' > "$sizes"
    local name
    while IFS= read -r name; do
        if [[ "$name" == SHA256SUMS || "$name" == ARTIFACT-SIZES.json ]]; then
            continue
        fi
        local bytes
        local hash
        bytes="$(stat -f '%z' "$fixture/$name")"
        hash="$(shasum -a 256 "$fixture/$name" | awk '{print $1}')"
        jq --arg name "$name" --argjson bytes "$bytes" --arg hash "$hash" \
            '.artifacts += [{name: $name, bytes: $bytes, sha256: $hash}]' \
            "$sizes" > "$sizes.next"
        mv "$sizes.next" "$sizes"
    done < <(mkv_magic_release_asset_names "$version")

    while IFS= read -r name; do
        if [[ "$name" != SHA256SUMS ]]; then
            shasum -a 256 "$fixture/$name"
        fi
    done < <(mkv_magic_release_asset_names "$version") \
        | sed "s#  $fixture/#  #" | sort > "$fixture/SHA256SUMS"
}

make_fixture() {
    local fixture="$1"
    mkdir "$fixture"
    local name
    while IFS= read -r name; do
        case "$name" in
            SHA256SUMS | ARTIFACT-SIZES.json)
                continue
                ;;
            NOTARIZATION-APP.json | NOTARIZATION-DMG.json)
                printf '{"id":"12345678-1234-1234-1234-123456789abc","status":"Accepted"}\n' \
                    > "$fixture/$name"
                ;;
            "MKV-Magic-$version-corresponding-source.zip")
                install -m 0644 "$source_template" "$fixture/$name"
                ;;
            BUILD-METADATA.txt)
                {
                    printf 'Product: MKV Magic\n'
                    printf 'Version: %s\n' "$version"
                    printf 'Build: 1\n'
                    printf 'Source commit: %s\n' "$source_commit"
                    printf 'Source tree: %s\n' "$source_tree"
                    printf 'Source timestamp: 2026-08-24T00:00:00Z\n'
                    printf 'Minimum macOS: 13.0\n'
                    printf 'Architectures: arm64 x86_64\n'
                    printf 'Swift: Apple Swift version fixture\n'
                    printf 'Xcode: Xcode fixture\n'
                } > "$fixture/$name"
                ;;
            *)
                printf 'fixture for %s\n' "$name" > "$fixture/$name"
                ;;
        esac
    done < <(mkv_magic_release_asset_names "$version")
    refresh_evidence "$fixture"
}

expect_rejection() {
    local fixture="$1"
    local description="$2"
    if validate_mkv_magic_downloaded_release "$fixture" "$version" >/dev/null 2>&1; then
        echo "release verifier accepted $description" >&2
        exit 1
    fi
}

make_source_material
valid="$test_root/valid"
make_fixture "$valid"
validate_mkv_magic_downloaded_release "$valid" "$version" >/dev/null

unexpected="$test_root/unexpected"
cp -R "$valid" "$unexpected"
printf 'unexpected\n' > "$unexpected/extra.txt"
expect_rejection "$unexpected" "an unexpected asset"

unsafe="$test_root/unsafe"
cp -R "$valid" "$unsafe"
/bin/rm -f "$unsafe/TROUBLESHOOTING.md"
ln -s README.md "$unsafe/TROUBLESHOOTING.md"
expect_rejection "$unsafe" "a symbolic-link asset"

missing_checksum="$test_root/missing-checksum"
cp -R "$valid" "$missing_checksum"
sed '/TROUBLESHOOTING.md$/d' "$missing_checksum/SHA256SUMS" \
    > "$missing_checksum/SHA256SUMS.next"
mv "$missing_checksum/SHA256SUMS.next" "$missing_checksum/SHA256SUMS"
expect_rejection "$missing_checksum" "an incomplete checksum manifest"

rejected_notarization="$test_root/rejected-notarization"
cp -R "$valid" "$rejected_notarization"
printf '{"id":"12345678-1234-1234-1234-123456789abc","status":"Rejected"}\n' \
    > "$rejected_notarization/NOTARIZATION-APP.json"
expect_rejection "$rejected_notarization" "rejected notarization evidence"

wrong_size="$test_root/wrong-size"
cp -R "$valid" "$wrong_size"
jq '(.artifacts[] | select(.name == "appcast.xml").bytes) += 1' \
    "$wrong_size/ARTIFACT-SIZES.json" > "$wrong_size/ARTIFACT-SIZES.json.next"
mv "$wrong_size/ARTIFACT-SIZES.json.next" "$wrong_size/ARTIFACT-SIZES.json"
while IFS= read -r name; do
    if [[ "$name" != SHA256SUMS ]]; then
        shasum -a 256 "$wrong_size/$name"
    fi
done < <(mkv_magic_release_asset_names "$version") \
    | sed "s#  $wrong_size/#  #" | sort > "$wrong_size/SHA256SUMS"
expect_rejection "$wrong_size" "incorrect artifact-size evidence"

wrong_source_commit="$test_root/wrong-source-commit"
cp -R "$valid" "$wrong_source_commit"
sed 's/^Source commit: .*/Source commit: 0000000000000000000000000000000000000000/' \
    "$wrong_source_commit/BUILD-METADATA.txt" \
    > "$wrong_source_commit/BUILD-METADATA.txt.next"
mv "$wrong_source_commit/BUILD-METADATA.txt.next" \
    "$wrong_source_commit/BUILD-METADATA.txt"
refresh_evidence "$wrong_source_commit"
expect_rejection "$wrong_source_commit" "source that disagrees with build metadata"

tampered_dependency="$test_root/tampered-dependency"
cp -R "$valid" "$tampered_dependency"
tamper_root="$test_root/tamper-root"
mkdir "$tamper_root"
source_zip="$tampered_dependency/MKV-Magic-$version-corresponding-source.zip"
ditto -x -k --noextattr "$source_zip" "$tamper_root"
printf 'tampered\n' >> "$tamper_root/MKV-Magic-$version-corresponding-source/dependencies/ffmpeg-9.0.1.tar.xz"
/bin/rm -f "$source_zip"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr -c -k --keepParent \
    "$tamper_root/MKV-Magic-$version-corresponding-source" "$source_zip"
refresh_evidence "$tampered_dependency"
expect_rejection "$tampered_dependency" "tampered corresponding-source dependency"

echo "downloaded release verification tests passed"
