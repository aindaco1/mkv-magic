#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || "$1" != /* ]]; then
    echo "usage: $0 <absolute-MKV-Magic.dmg> <signing-identity>" >&2
    exit 64
fi
dmg_path="$1"
signing_identity="$2"
if [[ -n "${SIGNING_KEYCHAIN_PATH:-}" ]]; then
    if [[ "$SIGNING_KEYCHAIN_PATH" != /* || ! -f "$SIGNING_KEYCHAIN_PATH" || \
          -L "$SIGNING_KEYCHAIN_PATH" ]]; then
        echo "signing keychain is missing or unsafe" >&2
        exit 1
    fi
fi
if [[ ! -f "$dmg_path" || -L "$dmg_path" || ! -s "$dmg_path" ]]; then
    echo "missing or unsafe DMG" >&2
    exit 1
fi
signing_flags=(--force --timestamp --sign "$signing_identity")
if [[ -n "${SIGNING_KEYCHAIN_PATH:-}" ]]; then
    signing_flags+=(--keychain "$SIGNING_KEYCHAIN_PATH")
fi
codesign "${signing_flags[@]}" "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"
