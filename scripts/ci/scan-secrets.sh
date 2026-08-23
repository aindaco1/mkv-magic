#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
patterns=(
    '-----BEGIN (RSA |EC |OPENSSH |)?PRIVATE KEY-----'
    '(^|[^A-Za-z0-9])(ghp|github_pat)_[A-Za-z0-9_]{20,}'
    '(^|[^A-Za-z0-9])sk_(live|test)_[A-Za-z0-9]{16,}'
    'AKIA[0-9A-Z]{16}'
    'SPARKLE_ED25519_PRIVATE_KEY[[:space:]]*=[[:space:]]*[A-Za-z0-9+/]{32,}'
    'APPLE_API_KEY_P8_BASE64[[:space:]]*=[[:space:]]*[A-Za-z0-9+/]{32,}'
)
failed=0
for pattern in "${patterns[@]}"; do
    set +e
    matches="$(
        rg -n --hidden \
            -g '!.git/**' -g '!.build/**' -g '!Package.resolved' \
            -- "$pattern" .
    )"
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        echo "potential committed secret:" >&2
        echo "$matches" >&2
        failed=1
    elif [[ "$status" -ne 1 ]]; then
        exit "$status"
    fi
done
exit "$failed"
