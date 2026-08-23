#!/usr/bin/env bash

set -euo pipefail

# Prompt for tracks to keep
read -p "Enter audio track IDs to keep (comma-separated, e.g., 1): " AUDIO_IDS
read -p "Enter subtitle track IDs to keep (comma-separated, e.g., 2,3): " SUB_IDS

# Define mkvmerge path (fallback to Homebrew if not in PATH)
MKVMERGE=$(command -v mkvmerge || echo "/usr/local/Cellar/mkvtoolnix/92.0/bin/mkvmerge")

# Function to move to macOS Trash without sound or collision
move_to_trash() {
    local filepath="$1"
    local trash_dir="${HOME}/.Trash"
    local filename="$(basename "$filepath")"
    local base="${filename%.*}"
    local ext="${filename##*.}"
    local counter=1
    local target="${trash_dir}/${filename}"

    while [[ -e "$target" ]]; do
        target="${trash_dir}/${base} ${counter}.${ext}"
        ((counter++))
    done

    mv "$filepath" "$target"
}

for f in *.mkv; do
    echo "Processing: $f"

    # Temp output file
    tmp_out="${f%.mkv}.cleaned.mkv"

    # Construct mkvmerge command
    "$MKVMERGE" -o "$tmp_out" \
        --no-global-tags \
        --no-attachments \
        --audio-tracks "$AUDIO_IDS" \
        --subtitle-tracks "$SUB_IDS" \
        "$f"

    # Replace original with cleaned version
    move_to_trash "$f"
    mv "$tmp_out" "$f"

    echo "Cleaned and replaced: $f"
done