#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/mkv-magic-loopback-test.XXXXXX")"
server_pid=''
cleanup() {
    if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    /bin/rm -rf -- "$test_root"
}
trap cleanup EXIT

feed_root="$test_root/feed"
ready_file="$test_root/server.port"
mkdir -p "$feed_root"
printf '%s\n' 'loopback-ready' >"$feed_root/probe.txt"

python3 -u "$repo_root/scripts/release/serve-loopback.py" \
    "$feed_root" "$ready_file" >"$test_root/server.log" 2>&1 &
server_pid=$!

port=''
for ((attempt = 0; attempt < 600; attempt++)); do
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "loopback server stopped before publishing its port" >&2
        exit 1
    fi
    if [[ -f "$ready_file" && ! -L "$ready_file" ]]; then
        port="$(tr -d '\n' <"$ready_file")"
    fi
    if [[ "$port" =~ ^[1-9][0-9]*$ ]]; then
        break
    fi
    sleep 0.05
done

if [[ ! "$port" =~ ^[1-9][0-9]*$ || "$port" -gt 65535 ]]; then
    if [[ -s "$test_root/server.log" ]]; then
        tail -n 20 "$test_root/server.log" >&2
    fi
    echo "loopback server did not publish a valid port" >&2
    exit 1
fi
if [[ "$(stat -f '%Lp' "$ready_file")" != 600 ]]; then
    echo "loopback server port file is not private" >&2
    exit 1
fi
if [[ "$(curl --fail --silent --show-error "http://127.0.0.1:$port/probe.txt")" != \
      'loopback-ready' ]]; then
    echo "loopback server did not serve the expected file" >&2
    exit 1
fi
if ! grep -Fq 'scripts/release/serve-loopback.py' \
    "$repo_root/scripts/release/exercise-update-replacement.sh"; then
    echo "updater acceptance does not use the tested loopback server" >&2
    exit 1
fi

echo "loopback server tests passed"
