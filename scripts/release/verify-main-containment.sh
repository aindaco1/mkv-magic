#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <commit>" >&2
    exit 64
fi

commit="$1"
if ! git rev-parse --verify --quiet "$commit^{commit}" >/dev/null; then
    echo "release commit does not exist" >&2
    exit 1
fi

main_ref=""
if git show-ref --verify --quiet refs/remotes/origin/main; then
    main_ref="refs/remotes/origin/main"
elif git show-ref --verify --quiet refs/heads/main; then
    main_ref="refs/heads/main"
else
    echo "main containment cannot be verified without origin/main or main" >&2
    exit 1
fi

if ! git merge-base --is-ancestor "$commit" "$main_ref"; then
    echo "release commit is not contained by main" >&2
    exit 1
fi

echo "release commit is contained by $main_ref"
