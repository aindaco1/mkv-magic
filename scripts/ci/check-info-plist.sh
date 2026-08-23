#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
plist="${1:-$repo_root/Sources/MKVMagic/Info.plist}"
expected_bundle_identifier="${MKV_MAGIC_BUNDLE_IDENTIFIER:-com.dustwave.mkvmagic}"
if [[ ! -f "$plist" || -L "$plist" ]]; then
    echo "missing or unsafe Info.plist" >&2
    exit 1
fi
/usr/bin/plutil -lint "$plist" >/dev/null

assert_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(/usr/bin/plutil -extract "$key" raw -o - "$plist")"
    if [[ "$actual" != "$expected" ]]; then
        echo "expected $key=$expected, found: $actual" >&2
        exit 1
    fi
}

assert_value CFBundleDisplayName "MKV Magic"
assert_value CFBundleExecutable MKVMagic
assert_value CFBundleIdentifier "$expected_bundle_identifier"
assert_value CFBundlePackageType APPL
assert_value LSMinimumSystemVersion 13.0
assert_value NSPrincipalClass NSApplication
assert_value SUFeedURL \
    https://github.com/aindaco1/mkv-magic/releases/latest/download/appcast.xml

for key in \
    SUEnableDownloaderService \
    SUEnableInstallerLauncherService \
    SURequireSignedFeed \
    SUVerifyUpdateBeforeExtraction
do
    assert_value "$key" true
done
for key in SUAllowsAutomaticUpdates SUEnableAutomaticChecks; do
    assert_value "$key" false
done

public_key="$(/usr/bin/plutil -extract SUPublicEDKey raw -o - "$plist")"
if [[ ! "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "Sparkle public key is missing or invalid" >&2
    exit 1
fi
