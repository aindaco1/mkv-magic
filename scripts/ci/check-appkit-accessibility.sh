#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

failure=0
while IFS= read -r controller; do
    if ! rg -q 'configureMKVMagicKeyboardNavigation' "$controller"; then
        echo "window controller lacks the shared keyboard navigation policy: $controller" >&2
        failure=1
    fi
    if ! rg -q 'setAccessibility(Label|Help)|accessibilityDescription' "$controller"; then
        echo "window controller lacks explicit accessibility semantics: $controller" >&2
        failure=1
    fi
done < <(find Sources/MKVMagic -maxdepth 1 -type f -name '*WindowController.swift' | sort)

if ! rg -q 'configureMKVMagicKeyboardNavigation' Sources/MKVMagic/AppDelegate.swift; then
    echo "main window lacks the shared keyboard navigation policy" >&2
    failure=1
fi

custom_motion_pattern='NSAnimationContext|\.animator\(\)|CABasicAnimation|CAKeyframeAnimation|NSViewAnimation'
if rg -n "$custom_motion_pattern" Sources/MKVMagic --glob '*.swift' >&2; then
    echo "custom UI motion requires an explicit Reduce Motion policy and regression test" >&2
    failure=1
fi

if rg -n '\.(stringValue|string) = UserFacingErrorPresentation\.message' \
    Sources/MKVMagic --glob '*.swift' >&2; then
    echo "user-facing AppKit failures must use AccessibleStatusPresentation" >&2
    failure=1
fi

if rg -n 'NSAccessibility\.post' Sources/MKVMagic --glob '*.swift' \
    --glob '!AccessibleStatusPresentation.swift' >&2; then
    echo "accessibility status notifications must use the shared presenter" >&2
    failure=1
fi

if rg -n 'NSColor\.[A-Za-z0-9_]+Color\.cgColor' Sources/MKVMagic --glob '*.swift' \
    --glob '!AppearanceAwareBorderStackView.swift' >&2; then
    echo "layer borders must use the shared appearance-aware semantic view" >&2
    failure=1
fi

if [[ "$failure" -ne 0 ]]; then
    exit 1
fi

echo "AppKit accessibility source contract passed"
