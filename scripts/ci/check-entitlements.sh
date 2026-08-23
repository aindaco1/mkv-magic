#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <entitlements.plist>" >&2
    exit 64
fi

entitlements="$1"
if [[ ! -f "$entitlements" || -L "$entitlements" ]]; then
    echo "missing or unsafe entitlements: $entitlements" >&2
    exit 1
fi
/usr/bin/plutil -lint "$entitlements" >/dev/null
entitlements_json="$(/usr/bin/plutil -convert json -o - "$entitlements")"

required_keys=(
    com.apple.security.app-sandbox
    com.apple.security.files.bookmarks.app-scope
    com.apple.security.files.user-selected.read-write
)
for key in "${required_keys[@]}"; do
    value="$(/usr/bin/jq -r --arg key "$key" '.[$key]' <<<"$entitlements_json")"
    if [[ "$value" != "true" ]]; then
        echo "required entitlement is not true: $key" >&2
        exit 1
    fi
done

for key in \
    com.apple.security.network.client \
    com.apple.security.network.server \
    com.apple.security.cs.allow-jit \
    com.apple.security.cs.allow-unsigned-executable-memory \
    com.apple.security.cs.disable-library-validation
do
    if /usr/bin/jq -e --arg key "$key" 'has($key)' <<<"$entitlements_json" >/dev/null; then
        echo "MKV Magic must not carry unapproved entitlement: $key" >&2
        exit 1
    fi
done

mach_services="$(
    /usr/bin/jq -r \
        '.["com.apple.security.temporary-exception.mach-lookup.global-name"][]' \
        <<<"$entitlements_json"
)"
expected_services=$'com.dustwave.mkvmagic-spks\ncom.dustwave.mkvmagic-spki'
if [[ "$mach_services" != "$expected_services" ]]; then
    echo "unexpected Sparkle Mach service exceptions" >&2
    exit 1
fi

actual_keys="$(/usr/bin/jq -r 'keys[]' <<<"$entitlements_json")"
expected_keys=$'com.apple.security.app-sandbox\ncom.apple.security.files.bookmarks.app-scope\ncom.apple.security.files.user-selected.read-write\ncom.apple.security.temporary-exception.mach-lookup.global-name'
if [[ "$actual_keys" != "$expected_keys" ]]; then
    echo "entitlement set differs from reviewed policy" >&2
    exit 1
fi
