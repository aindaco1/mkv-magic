import sys
import os
import re
import subprocess

# Matches common YIFY/YTS promo blocks even when the domain is on the next line,
# e.g.:
#   Official YIFY movies site:
#   YTS.BZ
# or:
#   Downloaded from
#   YTS.BZ
YTS_BLOCK_PATTERNS = [
    re.compile(r"official\s+yify\s+movies\s+site\s*:\s*yts\.(?:mx|lt|bz)", re.IGNORECASE),
    re.compile(r"downloaded\s+from\s+yts\.(?:mx|lt|bz)", re.IGNORECASE),
]


def block_contains_phrase(block):
    text = " ".join(line.strip() for line in block if line.strip())
    text = re.sub(r"\s+", " ", text)
    return any(pattern.search(text) for pattern in YTS_BLOCK_PATTERNS)


def move_to_trash(filepath):
    # Use AppleScript to move to Trash (macOS)
    script = f'tell application "Finder" to move (POSIX file "{filepath}") to trash'
    subprocess.run(["osascript", "-e", script])


def clean_srt(filename):
    with open(filename, "r", encoding="utf-8") as fin:
        content = fin.read()

    blocks = re.split(r"\n\s*\n", content.strip())
    kept_blocks = []
    removed = False

    for block in blocks:
        lines = block.strip().split("\n")
        if not block_contains_phrase(lines):
            kept_blocks.append(lines)
        else:
            removed = True

    if removed:
        # Prepare cleaned file content and renumber subtitle blocks.
        cleaned_content = ""
        for idx, lines in enumerate(kept_blocks, 1):
            cleaned_content += f"{idx}\n"
            cleaned_content += "\n".join(lines[1:]) + "\n\n"

        # Move original file to Trash.
        move_to_trash(filename)

        # Save cleaned content under original name.
        with open(filename, "w", encoding="utf-8") as fout:
            fout.write(cleaned_content)

        print(f"Cleaned and replaced: {filename}")
    else:
        print(f"No phrases found in: {filename} (untouched)")


if __name__ == "__main__":
    for filename in sys.argv[1:]:
        if os.path.isfile(filename) and filename.lower().endswith(".srt"):
            clean_srt(filename)
