#!/usr/bin/env python3
import argparse
import subprocess
import json
import shutil
import os
import sys
import re

def run(cmd, check=True):
    """Run a command and return the CompletedProcess; raise on error if check=True."""
    print("+", " ".join(cmd))
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(cmd)}\n"
            f"STDOUT:\n{result.stdout}\n"
            f"STDERR:\n{result.stderr}"
        )
    return result

def identify(path):
    """Return mkvmerge -J JSON for a file."""
    result = run(["mkvmerge", "-J", path])
    return json.loads(result.stdout)

def norm_lang(lang):
    if not lang:
        return None
    return lang.replace("_", "-").lower()

# --------------------------------------------------------------------
# 1. Decide which tracks to keep (based on the ORIGINAL file)
# --------------------------------------------------------------------

def decide_track_selection(info):
    """
    Decide which tracks to keep based on your selection rules only
    (no names/flags here, we do that later via mkvpropedit on the final file).

    Rules:
      - keep all video & audio tracks
      - keep only subtitle tracks whose language is English or und
      - if a subtitle is English and has SDH in the name:
          * drop it if there is more than one English/und subtitle
          * if it's the ONLY English/und subtitle, keep it
    """
    keep_video_ids = []
    keep_audio_ids = []
    keep_sub_ids = []

    english_langs = {"en", "eng", "en-us"}
    allowed_sub_langs_norm = english_langs | {None, "und"}

    tracks = info.get("tracks", [])

    # First pass: collect subtitle language meta to compute English/und counts
    subtitle_meta = {}
    english_or_und_sub_ids = []

    for t in tracks:
        if t["type"] != "subtitles":
            continue
        tid = t["id"]
        props = t.get("properties", {})
        lang_norm = norm_lang(props.get("language"))
        name = props.get("track_name") or ""
        lname = name.lower()

        is_english = lang_norm in english_langs
        is_und = (lang_norm is None) or (lang_norm == "und")
        is_sdh = "sdh" in lname

        subtitle_meta[tid] = {
            "lang_norm": lang_norm,
            "is_english": is_english,
            "is_und": is_und,
            "is_sdh": is_sdh,
        }

        if is_english or is_und:
            english_or_und_sub_ids.append(tid)

    english_or_und_sub_count = len(english_or_und_sub_ids)

    # Second pass: decide what to keep
    for t in tracks:
        tid = t["id"]
        ttype = t["type"]

        if ttype == "video":
            keep_video_ids.append(tid)

        elif ttype == "audio":
            keep_audio_ids.append(tid)

        elif ttype == "subtitles":
            meta = subtitle_meta.get(tid)
            if not meta:
                continue

            lang_norm = meta["lang_norm"]
            is_english = meta["is_english"]
            is_und = meta["is_und"]
            is_sdh = meta["is_sdh"]

            allowed_lang = lang_norm in allowed_sub_langs_norm
            keep = allowed_lang

            # SDH rule: if English + SDH
            if keep and is_english and is_sdh:
                if english_or_und_sub_count > 1:
                    # more than one English/und subtitle -> drop this SDH track
                    keep = False
                else:
                    # only English/und subtitle → keep (we'll scrub its name later)
                    keep = True

            if keep:
                keep_sub_ids.append(tid)

    return {
        "keep_video_ids": keep_video_ids,
        "keep_audio_ids": keep_audio_ids,
        "keep_sub_ids": keep_sub_ids,
    }

def build_mkvmerge_cmd(src, dst, selection):
    """
    Build mkvmerge command that only filters tracks.
    All metadata edits (names, languages, flags) are done later via mkvpropedit.
    """
    cmd = ["mkvmerge", "-o", dst]

    if selection["keep_video_ids"]:
        cmd.extend(["--video-tracks", ",".join(str(i) for i in selection["keep_video_ids"])])
    else:
        cmd.append("--no-video")

    if selection["keep_audio_ids"]:
        cmd.extend(["--audio-tracks", ",".join(str(i) for i in selection["keep_audio_ids"])])
    else:
        cmd.append("--no-audio")

    if selection["keep_sub_ids"]:
        cmd.extend(["--subtitle-tracks", ",".join(str(i) for i in selection["keep_sub_ids"])])
    else:
        cmd.append("--no-subtitles")

    cmd.append(src)
    return cmd

# --------------------------------------------------------------------
# 2. Attachments & tags helpers
# --------------------------------------------------------------------

FONT_MIME_PREFIXES = ("font/",)
FONT_MIME_EXACT = {
    "application/x-truetype-font",
    "application/x-font-ttf",
    "application/x-font-type1",
    "application/vnd.ms-opentype",
}
FONT_EXTS = {".ttf", ".otf", ".ttc", ".pfa", ".pfb"}

def is_font_attachment(att):
    ctype = (att.get("content_type") or "").lower()
    name = att.get("file_name") or ""
    ext = os.path.splitext(name)[1].lower()

    if ctype in FONT_MIME_EXACT:
        return True
    if any(ctype.startswith(p) for p in FONT_MIME_PREFIXES):
        return True
    if ext in FONT_EXTS:
        return True
    return False

# --------------------------------------------------------------------
# 3. Build metadata ops (names, languages, subtitle flags) for FINAL file
# --------------------------------------------------------------------

def build_metadata_ops_for_output(info):
    """
    Based on the final remuxed file, compute:
      - video language => und, scrub video names
      - audio commentary naming / scrub audio names
      - subtitle commentary naming / scrub subtitle names per rules
      - subtitle flags per audio-language/forced rules
    Returns:
      - video_lang_ops:   list of (selector, lang)
      - track_name_ops:   list of (selector, new_name)
      - sub_flag_ops:     list of (selector, default, enabled, forced)
    """

    tracks = info.get("tracks", [])

    english_langs = {"en", "eng", "en-us"}
    video_lang_ops = []
    track_name_ops = []
    sub_flag_ops = []

    # Build per-type lists with mkvpropedit selectors (track:v1, track:a1, track:s1)
    video_tracks = []
    audio_tracks = []
    sub_tracks = []

    video_idx = audio_idx = sub_idx = 0
    audio_lang_norms = []

    for t in tracks:
        ttype = t["type"]
        props = t.get("properties", {})
        name = props.get("track_name") or ""
        lang_norm = norm_lang(props.get("language"))

        if ttype == "video":
            video_idx += 1
            selector = f"track:v{video_idx}"
            video_tracks.append({
                "selector": selector,
                "props": props,
                "name": name,
            })

        elif ttype == "audio":
            audio_idx += 1
            selector = f"track:a{audio_idx}"
            audio_tracks.append({
                "selector": selector,
                "props": props,
                "name": name,
            })
            audio_lang_norms.append(lang_norm)

        elif ttype == "subtitles":
            sub_idx += 1
            selector = f"track:s{sub_idx}"
            sub_tracks.append({
                "selector": selector,
                "props": props,
                "name": name,
            })

    # Is there any English audio track?
    has_english_audio = any(
        (lang in english_langs) for lang in audio_lang_norms if lang is not None
    )

    # --- Video: language und + scrub names ---
    for v in video_tracks:
        video_lang_ops.append((v["selector"], "und"))
        if v["name"]:
            track_name_ops.append((v["selector"], ""))

    # --- Commentary naming (audio & subs) ---
    commentary_audio = [
        a for a in audio_tracks if "commentary" in a["name"].lower()
    ]
    commentary_subs = [
        s for s in sub_tracks if "commentary" in s["name"].lower()
    ]

    # Map selector -> new commentary name
    commentary_audio_name_map = {}
    for idx, a in enumerate(commentary_audio):
        if idx == 0:
            new_name = "Commentary"
        else:
            new_name = f"Commentary #{idx + 1}"
        commentary_audio_name_map[a["selector"]] = new_name

    commentary_sub_name_map = {}
    for idx, s in enumerate(commentary_subs):
        if idx == 0:
            new_name = "Commentary"
        else:
            new_name = f"Commentary #{idx + 1}"
        commentary_sub_name_map[s["selector"]] = new_name

    # --- Subtitle metadata & flags ---
    subtitle_meta = []
    english_or_und_subs = []

    for s in sub_tracks:
        props = s["props"]
        name = s["name"]
        lname = name.lower()

        lang_norm = norm_lang(props.get("language"))
        is_english = lang_norm in english_langs
        is_und = (lang_norm is None) or (lang_norm == "und")
        is_sdh = "sdh" in lname
        forced_flag = props.get("forced_track", False)
        is_forced = bool(forced_flag) or ("forced" in lname)

        subtitle_meta.append({
            "track": s,
            "lang_norm": lang_norm,
            "is_english": is_english,
            "is_und": is_und,
            "is_sdh": is_sdh,
            "is_forced": is_forced,
        })

        if is_english or is_und:
            english_or_und_subs.append(s)

    english_or_und_sub_count = len(english_or_und_subs)

    # Now apply naming + flags per subtitle
    for meta in subtitle_meta:
        s = meta["track"]
        sel = s["selector"]
        name = s["name"]
        lname = name.lower()

        is_english = meta["is_english"]
        is_und = meta["is_und"]
        is_sdh = meta["is_sdh"]
        is_forced = meta["is_forced"]
        english_or_und = is_english or is_und

        # ----- Name handling -----
        if sel in commentary_sub_name_map:
            track_name_ops.append((sel, commentary_sub_name_map[sel]))
        else:
            if english_or_und and is_sdh and english_or_und_sub_count == 1:
                track_name_ops.append((sel, ""))
            else:
                # scrub all subtitle names except forced ones
                if not is_forced and name:
                    track_name_ops.append((sel, ""))

        # ----- Flag handling -----
        if has_english_audio:
            if is_forced:
                f_default = False
                f_enabled = False
                f_forced = True
            else:
                f_default = False
                f_enabled = False
                f_forced = False
        else:
            f_default = True
            f_enabled = True
            f_forced = True

        sub_flag_ops.append(
            (sel, f_default, f_enabled, f_forced)
        )

    # --- Audio names: commentary normalized, others scrubbed ---
    for a in audio_tracks:
        sel = a["selector"]
        name = a["name"]
        if sel in commentary_audio_name_map:
            track_name_ops.append((sel, commentary_audio_name_map[sel]))
        else:
            if name:
                track_name_ops.append((sel, ""))

    return video_lang_ops, track_name_ops, sub_flag_ops

def apply_metadata_and_cleanup(path):
    """
    On the already-remuxed file:
      - delete non-font attachments
      - remove all tags
      - delete segment title
      - set video languages, track names, and subtitle flags
    """
    info = identify(path)

    # Which attachments to delete?
    attachments = info.get("attachments", [])
    delete_ids = []
    for att in attachments:
        if not is_font_attachment(att):
            delete_ids.append(att["id"])

    video_lang_ops, track_name_ops, sub_flag_ops = build_metadata_ops_for_output(info)

    cmd = ["mkvpropedit", path]

    # Delete non-font attachments
    for aid in delete_ids:
        cmd.extend(["--delete-attachment", str(aid)])

    # Remove all tags (global + per-track)
    cmd.extend(["--tags", "all:"])

    # Scrub segment title
    cmd.extend(["--edit", "info", "--delete", "title"])

    # Set video languages
    for selector, lang in video_lang_ops:
        cmd.extend(["--edit", selector, "--set", f"language={lang}"])

    # Set track names (mkvpropedit uses "name")
    for selector, new_name in track_name_ops:
        cmd.extend(["--edit", selector, "--set", f"name={new_name}"])

    # Set subtitle flags
    for selector, f_default, f_enabled, f_forced in sub_flag_ops:
        cmd.extend([
            "--edit", selector,
            "--set", f"flag-default={'1' if f_default else '0'}",
            "--set", f"flag-enabled={'1' if f_enabled else '0'}",
            "--set", f"flag-forced={'1' if f_forced else '0'}",
        ])

    run(cmd, check=True)

# --------------------------------------------------------------------
# 4. Filename normalization / Trash / hidden extension
# --------------------------------------------------------------------

def normalize_title(basename):
    """
    Normalize a release-style basename to 'Title (Year)'.
    Examples:
      'Eddington.2025.1080p.10bit.BluRay.8CH.X265.HEVC-PSA.clean' -> 'Eddington (2025)'
      '28 Years Later (2025) {tmdb-1100988}' -> '28 Years Later (2025)'
      'The Phoenician Scheme (2025) (1080p ...)' -> 'The Phoenician Scheme (2025)'
      'Plainclothes.2025.1080p.AMZN.WEB-DL.DDP5.1h265' -> 'Plainclothes (2025)'
    """
    # Strip trailing ".clean" if present
    if basename.lower().endswith(".clean"):
        basename = basename[:-6]

    original = basename

    # Pattern 1: Title (YYYY) ...
    m = re.match(r"^(.*?)\((\d{4})\)", basename)
    if m:
        title_raw, year = m.group(1), m.group(2)
        year_int = int(year)
        if 1900 <= year_int <= 2100:
            title = title_raw.strip(" .-_")
            title = re.sub(r"[._]+", " ", title)
            title = re.sub(r"\s+", " ", title).strip()
            return f"{title} ({year})"

    # Pattern 2: Title.YYYY...
    m = re.match(r"^(.*?)[.\s\-_]?(\d{4})(?:\D.*)?$", basename)
    if m:
        title_raw, year = m.group(1), m.group(2)
        year_int = int(year)
        if 1900 <= year_int <= 2100:
            title = title_raw.strip(" .-_")
            title = re.sub(r"[._]+", " ", title)
            title = re.sub(r"\s+", " ", title).strip()
            return f"{title} ({year})"

    # Fallback: just clean separators
    title = re.sub(r"[._]+", " ", original)
    title = re.sub(r"\s+", " ", title).strip()
    return title

def ensure_unique_path(directory, base_name, ext):
    """
    Ensure we don't overwrite an existing file.
    Returns a path like:
      dir/base_name.ext
      dir/base_name (2).ext
      dir/base_name (3).ext
    """
    candidate = os.path.join(directory, base_name + ext)
    if not os.path.exists(candidate):
        return candidate
    i = 2
    while True:
        cand = os.path.join(directory, f"{base_name} ({i}){ext}")
        if not os.path.exists(cand):
            return cand
        i += 1

def move_to_trash(path):
    """
    Move the original file to the user's Trash (~/.Trash) on macOS.
    """
    trash_dir = os.path.expanduser("~/.Trash")
    os.makedirs(trash_dir, exist_ok=True)
    base = os.path.basename(path)
    dest = os.path.join(trash_dir, base)
    if os.path.exists(dest):
        # avoid clobbering something already in the Trash
        name, ext = os.path.splitext(base)
        dest = ensure_unique_path(trash_dir, name, ext)
    shutil.move(path, dest)
    print(f"  Original moved to Trash: {dest}")

def hide_extension(path):
    """
    Hide a file's extension in Finder (macOS only).
    Uses osascript with argv so paths with spaces/() etc. are safe.
    """
    script = r'''
on run argv
  tell application "Finder"
    set theFile to (POSIX file (item 1 of argv)) as alias
    set extension hidden of theFile to true
  end tell
end run
'''

    try:
        print("+ osascript (hide extension)")
        result = subprocess.run(
            ["osascript", "-e", script, "--", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            print("  osascript exit code:", result.returncode, file=sys.stderr)
        if result.stderr.strip():
            print("  osascript stderr:", result.stderr.strip(), file=sys.stderr)
    except Exception as e:
        print(f"  Warning: could not hide extension for {path}: {e}", file=sys.stderr)

# --------------------------------------------------------------------
# 5. Per-file workflow
# --------------------------------------------------------------------

def clean_file(path, inplace=False, dry_run=False):
    base, ext = os.path.splitext(path)
    directory = os.path.dirname(path)
    orig_stem = os.path.basename(base)
    normalized_title = normalize_title(orig_stem)

    tmp_out = base + ".clean.tmp.mkv"

    info = identify(path)
    selection = decide_track_selection(info)
    cmd = build_mkvmerge_cmd(path, tmp_out, selection)

    # Determine final target path (normalized name)
    final_target = ensure_unique_path(directory, normalized_title, ext)

    if dry_run:
        print("Dry run for", path)
        print("  mkvmerge:", " ".join(cmd))
        print("  then mkvpropedit to:")
        print("    - remove non-font attachments")
        print("    - clear tags & segment title")
        print("    - set video language=und & scrub video names")
        print("    - normalize commentary names (audio+subs)")
        print("    - scrub subtitle names (per SDH/forced rules)")
        print("    - set subtitle flags (Default/Enabled/Forced) per audio-lang/forced rules")
        print(f"  Final cleaned file name: {final_target}")
        if inplace:
            print("  Original file would be moved to Trash.")
        else:
            print("  Original file would be kept.")
        return

    # 1) Remux with mkvmerge to drop unwanted tracks
    run(cmd, check=True)

    # 2) Clean attachments/tags and apply metadata on the *output* file
    apply_metadata_and_cleanup(tmp_out)

    # 3) Move original & final file into place
    if inplace:
        move_to_trash(path)

    os.replace(tmp_out, final_target)
    hide_extension(final_target)

    print(f"✓ Cleaned file written to: {final_target}")
    if not inplace:
        print("  Original file kept.")

# --------------------------------------------------------------------
# 6. CLI
# --------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Clean MKV files using mkvmerge/mkvpropedit with custom rules."
    )
    parser.add_argument(
        "paths",
        nargs="+",
        help="MKV files or directories to process (directories are scanned recursively)",
    )
    parser.add_argument(
        "-n", "--dry-run",
        action="store_true",
        help="Show what would be done, but don't modify anything",
    )
    parser.add_argument(
        "-i", "--in-place",
        action="store_true",
        help="Replace original MKV (move original to Trash, keep only cleaned+normalized file)",
    )

    args = parser.parse_args()

    to_process = []
    for path in args.paths:
        if os.path.isdir(path):
            for root, _, files in os.walk(path):
                for fname in files:
                    if fname.lower().endswith(".mkv"):
                        to_process.append(os.path.join(root, fname))
        else:
            to_process.append(path)

    if not to_process:
        print("No MKV files found.")
        return

    for f in to_process:
        print("=" * 60)
        print("Processing", f)
        try:
            clean_file(f, inplace=args.in_place, dry_run=args.dry_run)
        except Exception as e:
            print(f"ERROR processing {f}: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()