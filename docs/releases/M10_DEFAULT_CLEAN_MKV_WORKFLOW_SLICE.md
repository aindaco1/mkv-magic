# M10 default Clean MKV workflow

This slice turns the intent of the legacy `clean_mkv.py` utility into a native,
editable, deterministic MKV Magic workflow. It does not claim publication or
physical Intel and Apple Silicon acceptance.

## First-run contract

When no workflow library exists, Workflows presents one **Clean MKV** recipe.
The recipe uses stable workflow and card identifiers, but it is otherwise an
ordinary user-owned workflow: it can be edited, duplicated, exported, or
deleted. Creating a workflow clones the same cards with fresh identifiers. Once
the user saves a library—even an empty one—the app does not recreate the preset.

The enabled cards remove explicitly non-English subtitles, remove redundant
English SDH subtitles, remove the segment title and all Matroska tags, remove
reviewed `image/*` attachments, mark and normalize recognized commentary
tracks, mark recognized forced and SDH subtitles, and offer conservative output
filename cleanup. Each input is reinspected and the exact applied/skipped result
is shown before the workflow can run.

## Legacy behavior and deliberate safety differences

The workflow preserves every video and audio track, all subtitle fonts, and
attachments whose MIME type is not known to be an image. It preserves unknown
subtitle languages and the sole useful English/unknown subtitle. It does not
globally disable subtitles when English audio exists, globally force subtitles
when English audio is absent, or erase arbitrary track names. Those broader
legacy mutations remain available only through explicit reviewed edits where
the app supports them.

No card in the preset requests transcoding. Applicable removals are fused into
one packet-copy `mkvmerge` pass; applicable title, tag, and track-role changes
use at most one `mkvpropedit` pass. The normal verified-output transaction keeps
the source intact, saves beside it by default, and allows opt-in Trash only after
the committed output passes reopened verification.

## Compiler correction

Role policies can recognize a subtitle that an earlier cleanup card will remove.
The compiler now computes the complete planned-removal UID set first and filters
commentary, forced, SDH, and audio-description edits against it. A single plan
therefore never addresses a track after removing it.

## Verification

Unit coverage fixes the preset's ordered cards, stable unique identifiers,
first-run loading, editable-empty-library behavior, and fresh IDs for new
workflows. Planning coverage exercises a tagged release-style MKV with HEVC,
commentary audio, English, French, English SDH, and forced subtitles plus image
and font attachments, and proves a zero-encode fused plan.

A bundled-tool integration creates and executes the same media shape through
the automatic queue. The real output retains its font, audio, video, English,
and forced subtitle streams; removes the French and redundant SDH subtitles,
image, title, and tags; applies the retained role edits; leaves the source digest
unchanged; and records zero audio and video encodes.
