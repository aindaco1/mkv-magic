#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
entitlements="$repo_root/Configuration/ReportService.entitlements"
[[ -f "$entitlements" && ! -L "$entitlements" ]]
actual="$(plutil -convert json -o - "$entitlements" | jq -cS .)"
expected='{"com.apple.security.app-sandbox":true,"com.apple.security.network.client":true}'
if [[ "$actual" != "$expected" ]]; then
    echo "report service must have sandbox and network client only" >&2
    exit 1
fi
cd "$repo_root"
swift package describe --type json | jq -e '
    .targets as $targets |
    def deps($name): [$targets[] | select(.name == $name) | .target_dependencies[]?];
    def closure($name): deps($name) as $names | [$names[], ($names[] | closure(.)[])];
    (closure("MKVMagic") | index("MKVMagicReportService")) == null
' >/dev/null
# Every actual save-panel presentation is centralized. Other panels are input
# pickers, whose behavior is deliberately unrelated to output defaults.
while IFS= read -r file; do
    [[ "$file" == */OutputSavePanel.swift ]] && continue
    rg -q 'OutputSavePanel.choose' "$file" || {
        echo "save flow bypasses shared destination preferences: $file" >&2; exit 1;
    }
done < <(rg -l 'let panel = NSSavePanel\(' Sources/MKVMagic)
echo "reporting and shared output boundaries passed"
