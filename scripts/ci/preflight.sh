#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
    echo "the complete MKV Magic gate requires macOS" >&2
    exit 1
fi
required_commands=(
    codesign
    ditto
    git
    hdiutil
    jq
    lipo
    plutil
    rg
    shasum
    shellcheck
    swift
    xcodebuild
    xcrun
)
for command_name in "${required_commands[@]}"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "missing required command: $command_name" >&2
        exit 1
    fi
done
macos_version="$(sw_vers -productVersion)"
macos_major="${macos_version%%.*}"
xcode_first="$(xcodebuild -version | head -n 1)"
xcode_number="${xcode_first#Xcode }"
xcode_major="${xcode_number%%.*}"
if [[ ! "$macos_major" =~ ^[0-9]+$ || "$macos_major" -lt 13 ]]; then
    echo "MKV Magic requires macOS 13 or newer; found $macos_version" >&2
    exit 1
fi
if [[ ! "$xcode_major" =~ ^[0-9]+$ || "$xcode_major" -lt 16 ]]; then
    echo "MKV Magic development requires Xcode 16 or newer; found $xcode_first" >&2
    exit 1
fi
echo "local gate environment: macOS $macos_version; $xcode_first"
