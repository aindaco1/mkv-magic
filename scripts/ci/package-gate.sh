#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
gate_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-package-gate.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$gate_root"
}
trap cleanup EXIT
release_root="$gate_root/artifacts"
export MKV_MAGIC_BUNDLE_IDENTIFIER=com.dustwave.mkvmagic.package-gate

cd "$repo_root"
MKV_MAGIC_RELEASE_ROOT="$release_root" \
MKV_MAGIC_VERSION=0.0.0 \
MKV_MAGIC_BUILD_NUMBER=1 \
    ./scripts/release/build-app.sh >/dev/null
app_path="$release_root/MKV Magic.app"

# Use a disposable matching update key so the complete feed generator is
# tested without production key material.
test_key_pem="$gate_root/update-key.pem"
openssl genpkey -algorithm ED25519 -out "$test_key_pem" 2>/dev/null
test_private_key="$({
    openssl pkey -in "$test_key_pem" -outform DER 2>/dev/null \
        | tail -c 32 | base64 | tr -d '\n'
})"
test_public_key="$({
    openssl pkey -in "$test_key_pem" -pubout -outform DER 2>/dev/null \
        | tail -c 32 | base64 | tr -d '\n'
})"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $test_public_key" \
    "$app_path/Contents/Info.plist"

./scripts/release/sign-app.sh "$app_path" - none
MKV_MAGIC_RELEASE_ROOT="$release_root" ./scripts/release/package.sh >/dev/null
SPARKLE_ED25519_PRIVATE_KEY="$test_private_key" \
MKV_MAGIC_RELEASE_ROOT="$release_root" \
MKV_MAGIC_RELEASE_NOTES_PATH="$repo_root/docs/releases/0.0.0.md" \
    ./scripts/release/generate-appcast.sh v0.0.0 >/dev/null
MKV_MAGIC_RELEASE_ROOT="$release_root" ./scripts/release/checksum-artifacts.sh

(
    cd "$release_root"
    shasum -a 256 -c SHA256SUMS
)
dmg="$release_root/MKV-Magic-0.0.0-universal.dmg"
MKV_MAGIC_REQUIRE_DISTRIBUTION=0 \
    ./scripts/release/verify-dmg.sh "$dmg"
if unzip -Z1 "$release_root/MKV-Magic-0.0.0-universal.zip" \
    | grep -Eq '(^|/)\._|(^|/)\.DS_Store$'; then
    echo "update ZIP contains forbidden Finder metadata" >&2
    exit 1
fi
if grep -R -q '/Users/' \
    "$release_root/Package.resolved" \
    "$release_root/BUILD-METADATA.txt" \
    "$release_root/SBOM.cdx.json"; then
    echo "release metadata contains a personal path" >&2
    exit 1
fi
echo "package gate passed"
