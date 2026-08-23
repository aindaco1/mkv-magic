#!/usr/bin/env bash
set -euo pipefail

workflow_root="${1:-.github/workflows}"
if [[ ! -d "$workflow_root" ]]; then
    echo "missing workflow directory: $workflow_root" >&2
    exit 1
fi
failed=0
while IFS= read -r workflow; do
    while IFS= read -r use_line; do
        reference="${use_line#*@}"
        action="${use_line%%@*}"
        action="${action#*uses:}"
        action="$(tr -d "\"'[:space:]" <<<"$action")"
        reference="$(tr -d "\"'[:space:]" <<<"$reference")"
        if [[ "$action" == ./* || "$action" == docker://* ]]; then
            continue
        fi
        if [[ ! "$reference" =~ ^[a-f0-9]{40}$ ]]; then
            echo "workflow action is not pinned to a full commit: $workflow: $use_line" >&2
            failed=1
        fi
    done < <(grep -E '^[[:space:]]*-[[:space:]]+uses:' "$workflow" || true)
done < <(find "$workflow_root" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
exit "$failed"
