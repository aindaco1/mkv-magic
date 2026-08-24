#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_root="${MKV_MAGIC_RELEASE_ROOT:-$repo_root/.build/release-artifacts}"
app_path="$release_root/MKV Magic.app"
output="$release_root/SBOM.cdx.json"
if [[ ! -d "$app_path" || -L "$app_path" || -e "$output" ]]; then
    echo "SBOM inputs or output are unsafe" >&2
    exit 1
fi
version="$(plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist")"
temporary="$(mktemp "${TMPDIR:-/tmp}/mkv-magic-sbom.XXXXXX")"
cleanup() {
    /bin/rm -f -- "$temporary"
    /bin/rm -f -- "$temporary.next"
}
trap cleanup EXIT

jq -n \
    --arg version "$version" \
    --arg sparkle 2.9.5 \
    '{
      bomFormat: "CycloneDX",
      specVersion: "1.6",
      serialNumber: "urn:uuid:00000000-0000-4000-8000-000000000000",
      version: 1,
      metadata: {
        component: {
          type: "application",
          name: "MKV Magic",
          version: $version,
          licenses: [{license: {id: "GPL-3.0-or-later"}}]
        }
      },
      components: [
        {
          type: "framework",
          name: "Sparkle",
          version: $sparkle,
          purl: ("pkg:github/sparkle-project/Sparkle@" + $sparkle),
          licenses: [{license: {id: "MIT"}}]
        }
      ]
    }' > "$temporary"

tool_root="$app_path/Contents/Resources/Tools"
if [[ -d "$tool_root" ]]; then
    for architecture in arm64 x86_64; do
        manifest="$tool_root/$architecture/manifest.json"
        while IFS= read -r component; do
            jq --argjson component "$component" \
                '.components += [$component]' "$temporary" > "$temporary.next"
            mv "$temporary.next" "$temporary"
        done < <(
            jq -c --arg architecture "$architecture" \
                '.tools[] | {
                  type: "application",
                  name: .name,
                  version: .version,
                  hashes: [{alg: "SHA-256", content: .sha256}],
                  licenses: [{license: {id: .license}}],
                  externalReferences: [{type: "distribution", url: .source}],
                  properties: [{name: "mkv-magic:architecture", value: $architecture}]
                }' "$manifest"
        )
        while IFS= read -r component; do
            jq --argjson component "$component" \
                '.components += [$component]' "$temporary" > "$temporary.next"
            mv "$temporary.next" "$temporary"
        done < <(
            jq -c --arg architecture "$architecture" \
                '.libraries[] | {
                  type: "library",
                  name: (.path | split("/") | last),
                  hashes: [{alg: "SHA-256", content: .sha256}],
                  licenses: [{license: {id: .license}}],
                  externalReferences: [{type: "distribution", url: .source}],
                  properties: [{name: "mkv-magic:architecture", value: $architecture}]
                }' "$manifest"
        )
    done
    sources="$tool_root/SOURCES.json"
    svt_component="$(
        jq -c '
          .svtav1 | {
            type: "library",
            name: "SVT-AV1",
            version: .version,
            purl: ("pkg:generic/SVT-AV1@" + .version),
            hashes: [{alg: "SHA-256", content: .sha256}],
            licenses: [{license: {id: .license}}],
            externalReferences: [{type: "distribution", url: .url}],
            properties: [
              {name: "mkv-magic:linkage", value: "static-in-ffmpeg"},
              {name: "mkv-magic:patent-license", value: .patentLicense}
            ]
          }
        ' "$sources"
    )"
    jq --argjson component "$svt_component" \
        '.components += [$component]' "$temporary" > "$temporary.next"
    mv "$temporary.next" "$temporary"
    dav1d_component="$(
        jq -c '
          .dav1d | {
            type: "library",
            name: "dav1d",
            version: .version,
            purl: ("pkg:generic/dav1d@" + .version),
            hashes: [{alg: "SHA-256", content: .sha256}],
            licenses: [{license: {id: .license}}],
            externalReferences: [{type: "distribution", url: .url}],
            properties: [
              {name: "mkv-magic:linkage", value: "static-in-ffmpeg"}
            ]
          }
        ' "$sources"
    )"
    jq --argjson component "$dav1d_component" \
        '.components += [$component]' "$temporary" > "$temporary.next"
    mv "$temporary.next" "$temporary"
    opus_component="$(
        jq -c '
          .opus | {
            type: "library",
            name: "libopus",
            version: .version,
            purl: ("pkg:generic/opus@" + .version),
            hashes: [{alg: "SHA-256", content: .sha256}],
            licenses: [{license: {id: .license}}],
            externalReferences: [{type: "distribution", url: .url}],
            properties: [
              {name: "mkv-magic:linkage", value: "static-in-ffmpeg"}
            ]
          }
        ' "$sources"
    )"
    jq --argjson component "$opus_component" \
        '.components += [$component]' "$temporary" > "$temporary.next"
    mv "$temporary.next" "$temporary"
    zimg_component="$(
        jq -c '
          .zimg | {
            type: "library",
            name: "zimg",
            version: .version,
            purl: ("pkg:github/sekrit-twc/zimg@release-" + .version),
            hashes: [{alg: "SHA-256", content: .sha256}],
            licenses: [{license: {id: .license}}],
            externalReferences: [{type: "distribution", url: .url}],
            properties: [
              {name: "mkv-magic:linkage", value: "static-in-ffmpeg"}
            ]
          }
        ' "$sources"
    )"
    jq --argjson component "$zimg_component" \
        '.components += [$component]' "$temporary" > "$temporary.next"
    mv "$temporary.next" "$temporary"
fi
jq -S . "$temporary" > "$output"
chmod 0644 "$output"
