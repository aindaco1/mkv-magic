#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_root="$repo_root/Sources"
source_files=()
while IFS= read -r -d '' source_file; do
    source_files+=("$source_file")
done < <(find "$source_root" -type f -name '*.swift' -print0)

forbidden_patterns=(
    '^[[:space:]]*import[[:space:]]+(CFNetwork|FoundationNetworking|Network|NetworkExtension|WebKit)([[:space:]]|$)'
    'URLSession|NSURLSession|NW(Connection|Listener|Browser|PathMonitor)|CFSocket|SentrySDK|PostHogSDK|FirebaseAnalytics'
    'URL[[:space:]]*\([[:space:]]*string:[[:space:]]*"https?://'
    '/(usr/bin|usr/local/bin|opt/homebrew/bin)/(curl|wget|nc)'
    '(/bin/|/usr/bin/)(ba|z|c|fi|k)?sh(["[:space:]]|$)'
    '(^|[^[:alnum:]_])(system|popen)[[:space:]]*\('
)

failed=0
for pattern in "${forbidden_patterns[@]}"; do
    set +e
    matches="$(grep -EnH "$pattern" "${source_files[@]}")"
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        echo "local-only or shell boundary violation:" >&2
        echo "$matches" >&2
        failed=1
    elif [[ "$status" -ne 1 ]]; then
        exit "$status"
    fi
done

process_violations="$(
    grep -EnH '(^|[^[:alnum:]_])Process[[:space:]]*\(' "${source_files[@]}" \
        | grep -v '/Sources/MKVMagicSystem/' || true
)"
if [[ -n "$process_violations" ]]; then
    echo "Process launch escaped MKVMagicSystem:" >&2
    echo "$process_violations" >&2
    failed=1
fi

if [[ "$failed" -ne 0 ]]; then
    exit 1
fi
"$repo_root/scripts/ci/check-entitlements.sh" \
    "$repo_root/Configuration/MKVMagic.entitlements"
"$repo_root/scripts/ci/check-helper-entitlements.sh" \
    "$repo_root/Configuration/Helper.entitlements"
"$repo_root/scripts/ci/check-info-plist.sh"
