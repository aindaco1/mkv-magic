#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <helper-entitlements.plist>" >&2
    exit 64
fi
entitlements="$1"
if [[ ! -f "$entitlements" || -L "$entitlements" ]]; then
    echo "missing or unsafe helper entitlements" >&2
    exit 1
fi
/usr/bin/plutil -lint "$entitlements" >/dev/null
json="$(/usr/bin/plutil -convert json -o - "$entitlements")"
if [[ "$(/usr/bin/jq -cS . <<<"$json")" != \
      '{"com.apple.security.app-sandbox":true,"com.apple.security.inherit":true}' ]]; then
    echo "helper entitlements differ from reviewed inherit-only policy" >&2
    exit 1
fi
