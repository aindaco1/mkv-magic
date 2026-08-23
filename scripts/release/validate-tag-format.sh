#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "release tag must be vMAJOR.MINOR.PATCH" >&2
    exit 64
fi
