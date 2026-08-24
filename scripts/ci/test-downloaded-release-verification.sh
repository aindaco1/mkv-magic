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
            *)
                printf 'fixture for %s\n' "$name" > "$fixture/$name"
                ;;
        esac
    done < <(mkv_magic_release_asset_names "$version")

    local sizes="$fixture/ARTIFACT-SIZES.json"
    printf '{"schema":"mkv-magic-artifact-sizes-v1","artifacts":[]}\n' > "$sizes"
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

expect_rejection() {
    local fixture="$1"
    local description="$2"
    if validate_mkv_magic_downloaded_release "$fixture" "$version" >/dev/null 2>&1; then
        echo "release verifier accepted $description" >&2
        exit 1
    fi
}

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

echo "downloaded release verification tests passed"
