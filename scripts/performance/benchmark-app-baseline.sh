#!/usr/bin/env bash
set -euo pipefail

for argument in "$@"; do
    case "$argument" in
        --quick|--enforce) ;;
        *)
            echo "Usage: $0 [--quick] [--enforce]" >&2
            exit 64
            ;;
    esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
probe_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-app-baseline.XXXXXX")"
cleanup() {
    /bin/rm -rf -- "$probe_root"
}
trap cleanup EXIT

release_root="$probe_root/artifacts"
build_log="$probe_root/build.log"
if ! MKV_MAGIC_RELEASE_ROOT="$release_root" \
    MKV_MAGIC_VERSION=0.0.0 \
    MKV_MAGIC_BUILD_NUMBER=1 \
    "$repo_root/scripts/release/build-app.sh" >"$build_log" 2>&1
then
    echo "App baseline build failed:" >&2
    tail -n 80 "$build_log" >&2
    exit 1
fi
sign_log="$probe_root/sign.log"
if ! "$repo_root/scripts/release/sign-app.sh" \
    "$release_root/MKV Magic.app" - none >"$sign_log" 2>&1
then
    echo "App baseline signing failed:" >&2
    tail -n 80 "$sign_log" >&2
    exit 1
fi

cd "$repo_root"
launcher_log="$probe_root/launcher-build.log"
if ! swift build -c release --disable-automatic-resolution \
    --product MKVMagicAppBaselineProbe >"$launcher_log" 2>&1
then
    echo "App baseline launcher build failed:" >&2
    tail -n 80 "$launcher_log" >&2
    exit 1
fi
launcher_root="$(
    swift build -c release --disable-automatic-resolution \
        --product MKVMagicAppBaselineProbe --show-bin-path
)"
"$launcher_root/MKVMagicAppBaselineProbe" \
    --app-executable "$release_root/MKV Magic.app/Contents/MacOS/MKVMagic" \
    "$@"
