# M5 native verified Fast and Exact Trim slice

This records engineering, real-tool, and rendered AppKit acceptance of the first
complete native Trim flow. It handles inspected Matroska MKVs with exactly one
video track under the already accepted Fast and Exact executor contracts. It
does not claim generic splitting, subtitle/data timing, multiple-video handling,
source-tag preservation for Exact Trim, ordered editions, HDR/Dolby Vision,
private-library beta acceptance, physical Intel acceptance, or a public release.

## User flow

1. Select one eligible inspected MKV and choose **Trim…**.
2. MKV Magic generates five bounded local thumbnails without changing the source.
3. Use **Set In** or **Set Out** on a thumbnail, or type exact
   `HH:MM:SS.mmm` values.
4. Keep the default **Fast (No Encoding)** mode or choose **Exact**.
5. Exact mode lists only video formats whose bundled encoder passed the active
   local probe. Audio packet copy is the default; verified AAC conversion remains
   explicit and preserves the reviewed layout.
6. Choose **Review Trim**. Fast mode reads exact keyframes and discloses the actual
   saved range; Exact mode binds the requested range, encoder, audio policy,
   streams, chapters, and source revision. Save cannot continue without this
   immutable review.
7. Choose a new deterministic `— Trimmed.mkv` destination. The original is never
   offered as the output path.
8. Follow cancellable progress through work and verification. Cancellation is
   disabled only for the atomic commit, after which the app reopens and selects
   the verified output.

## Truthful planning and execution

- Fast Trim says **0 video encodes** and shows the first-keyframe-at-or-after
  adjustment for both requested boundaries. It never describes that result as
  exact.
- Exact Trim says **1 video encode**, names the verified preset, and states whether
  every audio track will be packet-copied or encoded once to AAC.
- Editing a field, changing modes, or changing an Exact choice immediately
  invalidates the prior review and disables Save.
- The app model reconstructs the appropriate revision-bound executor from the
  immutable preview. The GUI cannot bypass the executor's stream, chapter,
  metadata, attachment, duration, tag, capability, or source-change checks.
- Fast and Exact share one small verified-output progress controller with Lossless
  Join. This keeps commit/cancellation behavior DRY and consistent.
- Successful output is added to the inspection list and receives a sanitized
  eight-state History record. History contains display names and bounded policy
  messages, never source paths or media content.

## Native and accessibility acceptance

Focused AppKit tests cover eligible-source policy, deterministic output naming,
five bounded overview times, five thumbnail cards, exact numeric fields, explicit
Fast/Exact controls, capability-filtered Exact presets, packet-copy audio default,
review-before-save gating, meaningful accessibility labels, and complete bounds
for every visible subview in both modes at the declared 700 by 570 point minimum.

Deterministic light-appearance render artifacts were inspected for both modes.
They confirm a single top-to-bottom decision path, aligned margins, readable
timestamps, visible thumbnail actions, unambiguous encode impact, and footer
actions that remain available without scrolling.

## Real-tool and suite evidence

A bundled-tool application integration creates a ten-second video MKV with
two-second GOPs and nested chapters, inspects it through the real app model,
reviews a requested 3–7 second Fast Trim as the disclosed 4–8 second keyframe
range, executes the production verified-output transaction, and observes the
exact sanitized History lifecycle. It verifies one retained nested chapter tree,
zero video encodes, a new output, and an unchanged source SHA-256.

The standard source gate passes all 332 tests with 21 intentional bundled-tool
skips and builds a Universal `arm64`/`x86_64` executable. The manifest-backed
bundled runtime runs all 332 tests with zero skips and zero failures.
The complete local gate also passes coverage, AddressSanitizer, ThreadSanitizer,
Universal compilation, inside-out app signatures and entitlements,
SBOM/checksums, ZIP/appcast assembly, and checksum-verified DMG packaging.

## Still pending in M5

- Native exact-choice execution for common-format joins and manual mapping for
  ambiguous join lanes.
- Join-boundary decode spot checks and copied-stream fingerprints.
- Source-tag preservation, subtitle/data timing, multiple-video policy, ordered
  editions, HDR10 preservation, and Dolby Vision policy for trimming.
- Split by chapter/range/duration/size, Chapter Studio keyframe snapping,
  private-library beta, physical Intel performance acceptance, and public release.
