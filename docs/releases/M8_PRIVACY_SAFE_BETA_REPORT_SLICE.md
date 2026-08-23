# M8 privacy-safe beta report slice

This records engineering acceptance of the local, explicit History support
export and the safe fields captured for new jobs. It does not claim that a
private media corpus, Jellyfin or Plex playback, a physical Intel Mac, M6
transcoding, M7 production queues, or a public release has passed.

## Delivered contract

- Every newly executed job records a coarse `MediaJobInputFacts` value derived
  from already inspected media: container/codec families, size and duration
  buckets, track counts, maximum audio channels, HDR presence, and
  chapter/attachment/tag/warning counts.
- Every implemented executor records its reviewed video-generation and
  encoded-audio-track counts. Stable built-in workflow UUIDs are centralized in
  one catalog; unrecognized IDs export only as `savedOrUnknown`.
- Existing version-1 History JSON remains decodable. Older entries export with
  absent facts instead of guessing.
- History exposes one native **Export Privacy-Safe Report…** action and explains
  its inclusion and exclusion boundary before the save panel.
- Report creation re-verifies the exact manifest-backed bundled tool tree away
  from the main actor, includes at most the 500 newest jobs, and emits at most
  one megabyte.
- The writer accepts only an absolute JSON destination in an existing
  non-symlink directory, refuses a symlink or special-file destination, writes
  atomically, and applies mode `0600`.
- No report field receives display names, output names, raw messages, media or
  chapter objects, URLs, security bookmarks, or persistent job/input IDs.
- The app remains local-only. There is no upload action, telemetry, account, or
  new network entitlement.

## Privacy regression evidence

Adversarial serialization tests supply private paths, filenames, output names,
custom workflow names, track and chapter titles, failure text, UUIDs, exact
timestamps, tool source URLs, and license strings. The encoded report must omit
every sentinel while retaining the expected coarse AV1/AAC facts, plan, result,
and lifecycle.

Additional tests cover:

- safe backward decoding without the new optional fields;
- exact coarse-fact mapping and nested chapter counting;
- workflow classification without custom names;
- private file permissions;
- wrong-extension and symlink-destination refusal;
- the explanatory and enabled native export control; and
- a bundled-tool lossless join followed by a real AppModel report export whose
  JSON contains neither source name nor temporary fixture path.

## Current verification

On the Apple Silicon development Mac:

- `./scripts/ci/validate.sh` passed with 358 tests, 24 intentional missing-tool
  skips, zero failures, strict formatting/local-only/security checks, and a
  Universal `arm64` plus `x86_64` build.
- The exact manifest-backed bundled-tool suite passed all 358 tests with zero
  skips and zero failures, including the end-to-end report export.

The complete local gate also passed on this slice: coverage, AddressSanitizer,
ThreadSanitizer, Universal packaging, nested signature and entitlement checks,
SBOM/checksums, ZIP/appcast generation, and verified DMG assembly all completed
successfully. This is local engineering evidence, not Apple notarization or
downloaded-release acceptance.

## Remaining acceptance

- Execute the private matrix in `docs/beta/PRIVATE_LIBRARY_ACCEPTANCE.md` and
  turn each defect into an anonymized regression.
- Complete M6 transcoding/HDR defaults and M7 durable queue behavior before the
  full intended corpus/soak pass.
- Run physical Intel responsiveness, playback, and failure/recovery acceptance.
- Sign, notarize, publish, redownload, and install a later public beta before
  making any release claim.
