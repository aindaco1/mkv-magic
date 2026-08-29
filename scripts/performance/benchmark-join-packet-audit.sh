#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: benchmark-join-packet-audit.sh MEDIA STREAM_FAMILY TRACK_ID [TRACK_ID ...]

Compare the former per-track FFprobe packet scan with MKV Magic's current
single-pass, per-stream-family scan. MEDIA is never modified. STREAM_FAMILY is
one of v, a, s, d, or t. Set MKV_MAGIC_BENCHMARK_ITERATIONS to change the
default five measured passes.
EOF
}

if [[ "$#" -lt 3 ]]; then
    usage >&2
    exit 64
fi

media_path="$1"
stream_family="$2"
shift 2
track_ids=("$@")

case "$stream_family" in
    v | a | s | d | t) ;;
    *)
        echo "stream family must be one of: v, a, s, d, t" >&2
        exit 64
        ;;
esac

if [[ ! -f "$media_path" || -L "$media_path" ]]; then
    echo "media must be a regular, non-symbolic-link file" >&2
    exit 66
fi
media_directory="$(cd "$(dirname "$media_path")" && pwd -P)"
media_path="$media_directory/$(basename "$media_path")"
source_revision="$(stat -f '%d:%i:%z:%m:%c' "$media_path")"

for track_id in "${track_ids[@]}"; do
    if [[ ! "$track_id" =~ ^[0-9]+$ ]]; then
        echo "track IDs must be non-negative integers" >&2
        exit 64
    fi
done

iterations="${MKV_MAGIC_BENCHMARK_ITERATIONS:-5}"
if [[ ! "$iterations" =~ ^[1-9][0-9]*$ || "$iterations" -gt 100 ]]; then
    echo "MKV_MAGIC_BENCHMARK_ITERATIONS must be between 1 and 100" >&2
    exit 64
fi

architecture="$(uname -m)"
case "$architecture" in
    arm64 | x86_64) ;;
    *)
        echo "unsupported benchmark architecture: $architecture" >&2
        exit 69
        ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tool_root="${MKV_MAGIC_TOOL_ROOT:-$repo_root/.build/tool-runtime-m0-5}"
runtime_root="$tool_root/universal"
ffprobe="$runtime_root/ffprobe"
manifest="$runtime_root/manifest.json"
if [[ ! -d "$tool_root" || -L "$tool_root" || \
      ! -d "$runtime_root" || -L "$runtime_root" || \
      ! -f "$manifest" || -L "$manifest" || \
      ! -x "$ffprobe" || -L "$ffprobe" ]]; then
    echo "verified FFprobe was not found at the expected architecture path" >&2
    exit 69
fi
manifest_schema="$(jq -r '.schema' "$manifest")"
manifest_architecture="$(jq -r '.architecture' "$manifest")"
manifest_path="$(jq -r '.tools[] | select(.name == "ffprobe") | .path' "$manifest")"
expected_hash="$(jq -r '.tools[] | select(.name == "ffprobe") | .sha256' "$manifest")"
actual_hash="$(shasum -a 256 "$ffprobe" | awk '{print $1}')"
if [[ "$manifest_schema" != mkv-magic-tool-manifest-v2 || \
      "$manifest_architecture" != universal || \
      "$manifest_path" != ffprobe || \
      ! "$expected_hash" =~ ^[a-f0-9]{64}$ || \
      "$actual_hash" != "$expected_hash" ]]; then
    echo "FFprobe failed manifest identity or hash verification" >&2
    exit 69
fi

family_track_ids="$("$ffprobe" \
    -v error \
    -select_streams "$stream_family" \
    -show_entries stream=index \
    -of csv=p=0 \
    "$media_path")"
for track_id in "${track_ids[@]}"; do
    if ! grep -Fxq "$track_id" <<<"$family_track_ids"; then
        echo "track $track_id is not present in stream family $stream_family" >&2
        exit 65
    fi
done

# Warm both code paths before recording. Output is intentionally discarded;
# command failures remain fatal.
"$ffprobe" \
    -v error \
    -select_streams "${track_ids[0]}" \
    -show_packets \
    -show_entries packet=data_hash \
    -show_data_hash sha256 \
    -of csv=p=0 \
    "$media_path" >/dev/null
"$ffprobe" \
    -v error \
    -select_streams "$stream_family" \
    -show_packets \
    -show_entries packet=stream_index,data_hash \
    -show_data_hash sha256 \
    -of csv=p=0 \
    "$media_path" >/dev/null

baseline_launches=$((iterations * ${#track_ids[@]}))
optimized_launches="$iterations"
printf 'media path: withheld\narchitecture: %s\niterations: %s\nlanes: %s\n' \
    "$architecture" "$iterations" "${#track_ids[@]}"
printf 'baseline per-lane scans (%s FFprobe launches)\n' "$baseline_launches"
# The single-quoted program is evaluated by the measured child Bash process.
# shellcheck disable=SC2016
/usr/bin/time -p /bin/bash -c '
    ffprobe=$1
    media=$2
    iterations=$3
    shift 3
    for ((iteration = 0; iteration < iterations; iteration += 1)); do
        for track_id in "$@"; do
            "$ffprobe" -v error -select_streams "$track_id" -show_packets \
                -show_entries packet=data_hash -show_data_hash sha256 \
                -of csv=p=0 "$media" >/dev/null
        done
    done
' benchmark "$ffprobe" "$media_path" "$iterations" "${track_ids[@]}"

printf 'current family-demultiplexed scans (%s FFprobe launches)\n' "$optimized_launches"
# The single-quoted program is evaluated by the measured child Bash process.
# shellcheck disable=SC2016
/usr/bin/time -p /bin/bash -c '
    ffprobe=$1
    media=$2
    iterations=$3
    family=$4
    for ((iteration = 0; iteration < iterations; iteration += 1)); do
        "$ffprobe" -v error -select_streams "$family" -show_packets \
            -show_entries packet=stream_index,data_hash -show_data_hash sha256 \
            -of csv=p=0 "$media" >/dev/null
    done
' benchmark "$ffprobe" "$media_path" "$iterations" "$stream_family"

if [[ "$(stat -f '%d:%i:%z:%m:%c' "$media_path")" != "$source_revision" ]]; then
    echo "media changed while the benchmark was running; discard these measurements" >&2
    exit 74
fi
