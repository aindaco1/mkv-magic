#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <Developer-ID-identity> <keychain>" >&2
    exit 64
fi
identity="$1"
keychain="$2"
if [[ -z "$identity" || "$keychain" != /* || ! -f "$keychain" || -L "$keychain" ]]; then
    echo "signing certificate inputs are missing or unsafe" >&2
    exit 1
fi
if ! security find-identity -v -p codesigning "$keychain" | grep -Fq "\"$identity\""; then
    echo "expected Developer ID signing identity is unavailable" >&2
    exit 1
fi
certificate="$(mktemp "${TMPDIR:-/tmp}/mkv-magic-certificate.XXXXXX")"
cleanup() {
    /bin/rm -f -- "$certificate"
}
trap cleanup EXIT
security find-certificate -c "$identity" -p "$keychain" > "$certificate"
if ! openssl x509 -in "$certificate" -checkend 5184000 -noout; then
    echo "Developer ID certificate expires within 60 days" >&2
    exit 1
fi
openssl x509 -in "$certificate" -noout -enddate
