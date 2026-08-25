#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
required_formulae=(autoconf cmake meson ninja pkgconf)

assert_runtime_dependencies() {
    local workflow="$1"
    local install_line
    install_line="$(
        awk '
            /- name: .*runtime-build dependencies/ {
                getline
                print
                exit
            }
        ' "$workflow"
    )"
    if [[ "$install_line" != *"run: brew install "* ]]; then
        echo "$workflow does not install runtime-build dependencies with Homebrew" >&2
        exit 1
    fi

    local formula
    for formula in "${required_formulae[@]}"; do
        if [[ " $install_line " != *" $formula "* ]]; then
            echo "$workflow does not install required formula: $formula" >&2
            exit 1
        fi
    done
}

assert_runtime_dependencies "$repo_root/.github/workflows/ci.yml"
assert_runtime_dependencies "$repo_root/.github/workflows/release.yml"

echo "runtime-build dependency tests passed"
