#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-coverage-gate.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

source_root="$test_root/Sources"
mkdir -p "$source_root/MKVMagic" "$source_root/MKVMagicCore"
valid_report="$test_root/valid.json"
checker="$repo_root/scripts/ci/check-coverage.swift"

jq -n \
    --arg ui "$source_root/MKVMagic/App.swift" \
    --arg core "$source_root/MKVMagicCore/Core.swift" \
    --arg external "$test_root/Dependency/Dependency.swift" \
    '{
        data: [{
            files: [
                {
                    filename: $ui,
                    summary: {
                        lines: {count: 100, covered: 50},
                        functions: {count: 60, covered: 50},
                        regions: {count: 70, covered: 50}
                    }
                },
                {
                    filename: $core,
                    summary: {
                        lines: {count: 100, covered: 90},
                        functions: {count: 100, covered: 90},
                        regions: {count: 100, covered: 80}
                    }
                },
                {
                    filename: $external,
                    summary: {
                        lines: {count: 1000, covered: 0},
                        functions: {count: 1000, covered: 0},
                        regions: {count: 1000, covered: 0}
                    }
                }
            ]
        }]
    }' > "$valid_report"

if ! valid_output="$(swift "$checker" "$valid_report" "$source_root")"; then
    echo "coverage gate rejected the valid aggregate" >&2
    exit 1
fi
if ! grep -Fq 'non-UI line coverage: 90.00%' <<< "$valid_output"; then
    echo "coverage gate did not report the non-UI aggregate" >&2
    exit 1
fi

expect_rejection() {
    local description="$1"
    local report_path="$2"
    if swift "$checker" "$report_path" "$source_root" >/dev/null 2>&1; then
        echo "coverage gate accepted $description" >&2
        exit 1
    fi
}

low_non_ui_report="$test_root/low-non-ui.json"
jq '(.data[0].files[] | select(.filename | contains("/MKVMagic/App.swift")) |
        .summary.lines.covered) = 70 |
    (.data[0].files[] | select(.filename | contains("/MKVMagicCore/Core.swift")) |
        .summary.lines.covered) = 79' \
    "$valid_report" > "$low_non_ui_report"
expect_rejection "79 percent non-UI line coverage" "$low_non_ui_report"

low_all_source_report="$test_root/low-all-source.json"
jq '(.data[0].files[] | select(.filename | contains("/MKVMagic/App.swift")) |
        .summary.lines.covered) = 0' \
    "$valid_report" > "$low_all_source_report"
expect_rejection "all-source coverage below its floor" "$low_all_source_report"

malformed_report="$test_root/malformed.json"
jq 'del(.data[0].files[1].summary.lines.covered)' \
    "$valid_report" > "$malformed_report"
expect_rejection "malformed production metrics" "$malformed_report"

missing_appkit_report="$test_root/missing-appkit.json"
jq '(.data[0].files[] | select(.filename | contains("/MKVMagic/App.swift")) |
        .filename) |= sub("/MKVMagic/"; "/MKVMagicRenamed/")' \
    "$valid_report" > "$missing_appkit_report"
expect_rejection "a report without the known AppKit target" "$missing_appkit_report"

echo "coverage gate tests passed"
