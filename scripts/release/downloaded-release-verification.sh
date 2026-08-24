#!/usr/bin/env bash

downloaded_release_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$downloaded_release_repo_root/scripts/release/corresponding-source-verification.sh"

mkv_magic_release_asset_names() {
    local version="$1"
    printf '%s\n' \
        "MKV-Magic-$version-universal.zip" \
        "MKV-Magic-$version-universal.dmg" \
        "MKV-Magic-$version-corresponding-source.zip" \
        appcast.xml \
        SHA256SUMS \
        Package.resolved \
        THIRD-PARTY-NOTICES.md \
        SUPPORTED-SYSTEMS.md \
        TROUBLESHOOTING.md \
        BUILD-METADATA.txt \
        ARTIFACT-SIZES.json \
        SBOM.cdx.json \
        NOTARIZATION-APP.json \
        NOTARIZATION-DMG.json
}

mkv_magic_attested_release_asset_names() {
    local version="$1"
    printf '%s\n' \
        "MKV-Magic-$version-universal.zip" \
        "MKV-Magic-$version-universal.dmg" \
        "MKV-Magic-$version-corresponding-source.zip" \
        appcast.xml \
        SBOM.cdx.json
}

validate_mkv_magic_downloaded_release() {
    if [[ $# -ne 2 ]]; then
        echo "usage: validate_mkv_magic_downloaded_release <absolute-directory> <version>" >&2
        return 64
    fi
    local release_root="$1"
    local version="$2"
    if [[ "$release_root" != /* || ! -d "$release_root" || -L "$release_root" || \
          ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "downloaded release path or version is unsafe" >&2
        return 1
    fi

    local expected_names=()
    local name
    while IFS= read -r name; do
        expected_names+=("$name")
    done < <(mkv_magic_release_asset_names "$version")

    local actual_count=0
    local entry
    while IFS= read -r -d '' entry; do
        name="$(basename "$entry")"
        local allowed=0
        local expected
        for expected in "${expected_names[@]}"; do
            if [[ "$name" == "$expected" ]]; then
                allowed=1
                break
            fi
        done
        if [[ "$allowed" != 1 || ! -f "$entry" || -L "$entry" || ! -s "$entry" ]]; then
            echo "downloaded release contains an unexpected or unsafe asset: $name" >&2
            return 1
        fi
        actual_count=$((actual_count + 1))
    done < <(find "$release_root" -mindepth 1 -maxdepth 1 -print0)
    if [[ "$actual_count" -ne "${#expected_names[@]}" ]]; then
        echo "downloaded release asset count does not match the release contract" >&2
        return 1
    fi
    for name in "${expected_names[@]}"; do
        if [[ ! -f "$release_root/$name" || -L "$release_root/$name" || \
              ! -s "$release_root/$name" ]]; then
            echo "downloaded release is missing a required asset: $name" >&2
            return 1
        fi
    done

    local checksum_names=()
    local checksum_file="$release_root/SHA256SUMS"
    local checksum_line
    local checksum_pattern='^[0-9a-f]{64}  ([A-Za-z0-9._-]+)$'
    while IFS= read -r checksum_line || [[ -n "$checksum_line" ]]; do
        if [[ ! "$checksum_line" =~ $checksum_pattern ]]; then
            echo "SHA256SUMS contains a malformed or unsafe entry" >&2
            return 1
        fi
        checksum_names+=("${BASH_REMATCH[1]}")
    done < "$checksum_file"
    if [[ "${#checksum_names[@]}" -ne "$((${#expected_names[@]} - 1))" ]]; then
        echo "SHA256SUMS entry count does not match the release contract" >&2
        return 1
    fi
    for name in "${expected_names[@]}"; do
        if [[ "$name" == SHA256SUMS ]]; then
            continue
        fi
        local matches=0
        local checksum_name
        for checksum_name in "${checksum_names[@]}"; do
            if [[ "$checksum_name" == "$name" ]]; then
                matches=$((matches + 1))
            fi
        done
        if [[ "$matches" -ne 1 ]]; then
            echo "SHA256SUMS must contain exactly one entry for $name" >&2
            return 1
        fi
    done
    if ! (cd "$release_root" && shasum -a 256 -c SHA256SUMS); then
        echo "downloaded release checksum verification failed" >&2
        return 1
    fi

    local evidence
    for evidence in NOTARIZATION-APP.json NOTARIZATION-DMG.json; do
        if ! jq -e '
            .status == "Accepted" and
            (.id | type == "string") and
            (.id | test("^[0-9a-fA-F-]{36}$"))
        ' "$release_root/$evidence" >/dev/null; then
            echo "downloaded release contains invalid notarization evidence: $evidence" >&2
            return 1
        fi
    done

    local size_evidence="$release_root/ARTIFACT-SIZES.json"
    local sized_count
    sized_count="$((${#expected_names[@]} - 2))"
    if ! jq -e --argjson expected "$sized_count" '
        .schema == "mkv-magic-artifact-sizes-v1" and
        (.artifacts | type == "array") and
        (.artifacts | length == $expected)
    ' "$size_evidence" >/dev/null; then
        echo "artifact-size evidence does not match the release contract" >&2
        return 1
    fi
    for name in "${expected_names[@]}"; do
        if [[ "$name" == SHA256SUMS || "$name" == ARTIFACT-SIZES.json ]]; then
            continue
        fi
        local bytes
        local hash
        bytes="$(stat -f '%z' "$release_root/$name")"
        hash="$(shasum -a 256 "$release_root/$name" | awk '{print $1}')"
        if ! jq -e --arg name "$name" --argjson bytes "$bytes" --arg hash "$hash" '
            [.artifacts[] | select(
                .name == $name and .bytes == $bytes and .sha256 == $hash
            )] | length == 1
        ' "$size_evidence" >/dev/null; then
            echo "artifact-size evidence is missing or incorrect for $name" >&2
            return 1
        fi
    done

    validate_mkv_magic_corresponding_source \
        "$release_root/MKV-Magic-$version-corresponding-source.zip" \
        "$version" "$release_root/BUILD-METADATA.txt"
}
