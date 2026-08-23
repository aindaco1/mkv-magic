#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "usage: $0 <app-or-dmg> <AuthKey.p8> <key-id> <issuer-id> <evidence.json>" >&2
    exit 64
fi
artifact="$1"
api_key="$2"
key_id="$3"
issuer_id="$4"
evidence_path="$5"
if [[ ! -e "$artifact" || ! -f "$api_key" || -L "$api_key" || \
      -e "$evidence_path" || "$evidence_path" != /* ]]; then
    echo "notarization paths are missing or unsafe" >&2
    exit 1
fi
if [[ ! "$key_id" =~ ^[A-Z0-9]{10}$ || \
      ! "$issuer_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    echo "notarization identifiers are invalid" >&2
    exit 64
fi

work_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-notary.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$work_root"
}
trap cleanup EXIT
submission="$artifact"
if [[ -d "$artifact" && "$artifact" == *.app ]]; then
    submission="$work_root/MKV-Magic-notarization.zip"
    COPYFILE_DISABLE=1 ditto --norsrc --noextattr -c -k --keepParent \
        "$artifact" "$submission"
fi
response="$work_root/notary-response.json"
xcrun notarytool submit "$submission" \
    --key "$api_key" --key-id "$key_id" --issuer "$issuer_id" \
    --wait --output-format json > "$response"
status="$(jq -r '.status' "$response")"
submission_id="$(jq -r '.id' "$response")"
if [[ "$status" != Accepted || ! "$submission_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    echo "Apple notarization was not accepted: $status" >&2
    exit 1
fi
install -m 0644 "$response" "$evidence_path"
xcrun stapler staple "$artifact"
xcrun stapler validate "$artifact"
if [[ -d "$artifact" ]]; then
    spctl --assess --type execute --verbose=2 "$artifact"
else
    spctl --assess --type open --context context:primary-signature \
        --verbose=2 "$artifact"
fi
