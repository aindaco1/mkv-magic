#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
required_formulae=(autoconf automake cmake libtool meson ninja pkgconf)
required_commands=(aclocal autoreconf glibtoolize cmake meson ninja pkg-config)

assert_runtime_dependencies() {
    local workflow="$1"
    local install_line
    install_line="$(
        awk '
            /- name: .*runtime-build dependencies/ {
                getline
                while ($0 ~ /run: >-/ || $0 ~ /\\$/ || $0 ~ /^          /) {
                    print
                    if (getline <= 0) {
                        break
                    }
                }
                print
                exit
            }
        ' "$workflow" | tr '\n' ' '
    )"
    if [[ "$install_line" != *"brew install "* ]]; then
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

required_command_line="$(
    grep '^for required_command in ' "$repo_root/scripts/tools/build-runtime.sh" | tr ';' ' '
)"
for command_name in "${required_commands[@]}"; do
    if [[ " $required_command_line " != *" $command_name "* ]]; then
        echo "build-runtime.sh does not fail fast for required command: $command_name" >&2
        exit 1
    fi
done

echo "runtime-build dependency tests passed"
