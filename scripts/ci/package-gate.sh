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
MKV_MAGIC_BUILD_NUMBER=2 \
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
test_private_key_file="$gate_root/update-private-key"
rejection_private_key_file="$gate_root/rejection-private-key"
printf '%s' "$test_private_key" >"$test_private_key_file"
openssl genpkey -algorithm ED25519 -out "$gate_root/rejection-key.pem" 2>/dev/null
rejection_private_key="$({
    openssl pkey -in "$gate_root/rejection-key.pem" -outform DER 2>/dev/null \
        | tail -c 32 | base64 | tr -d '\n'
})"
printf '%s' "$rejection_private_key" >"$rejection_private_key_file"
chmod 0600 "$test_private_key_file" "$rejection_private_key_file"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $test_public_key" \
    "$app_path/Contents/Info.plist"

./scripts/release/sign-app.sh "$app_path" - none
prior_app="$gate_root/prior/MKV Magic.app"
mkdir -p "$(dirname "$prior_app")"
ditto --norsrc --noextattr "$app_path" "$prior_app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.0.0" \
    "$prior_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" \
    "$prior_app/Contents/Info.plist"
./scripts/release/sign-app.sh "$prior_app" - none
swift run -c release --disable-automatic-resolution MKVMagicAppBaselineProbe \
    --app-executable "$app_path/Contents/MacOS/MKVMagic" \
    --quick --enforce >/dev/null
MKV_MAGIC_RELEASE_ROOT="$release_root" ./scripts/release/package.sh >/dev/null
SPARKLE_ED25519_PRIVATE_KEY="$test_private_key" \
MKV_MAGIC_RELEASE_ROOT="$release_root" \
MKV_MAGIC_RELEASE_NOTES_PATH="$repo_root/docs/releases/0.0.0.md" \
    ./scripts/release/generate-appcast.sh v0.0.0 >/dev/null
MKV_MAGIC_EXPECTED_APPCAST_PATH="$release_root/appcast.xml" \
MKV_MAGIC_REJECTION_PRIVATE_KEY_FILE="$rejection_private_key_file" \
    ./scripts/release/exercise-update-replacement.sh \
        "$prior_app" \
        "$release_root/MKV-Magic-0.0.0-universal.zip" \
        v0.0.0 "$test_private_key_file" 0
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
    "$release_root/SBOM.cdx.json" \
    "$release_root/TROUBLESHOOTING.md"; then
    echo "release metadata contains a personal path" >&2
    exit 1
fi
if [[ ! -f "$release_root/TROUBLESHOOTING.md" || \
      -L "$release_root/TROUBLESHOOTING.md" ]] || \
    ! grep -q 'MKV Magic troubleshooting' "$release_root/TROUBLESHOOTING.md" || \
    ! cmp -s "$release_root/TROUBLESHOOTING.md" \
        "$app_path/Contents/Resources/TROUBLESHOOTING.md"; then
    echo "release troubleshooting guide is missing or unsafe" >&2
    exit 1
fi
echo "package gate passed"
