# M5 native strict lossless join slice

This records engineering and rendered AppKit acceptance of the first complete
native hard-join path. It handles complete, gap-free Matroska sources already
classified as strict `losslessCandidate` inputs. It does not claim trim support,
manual ambiguity resolution, attachment selection, normalization/transcoding,
decode-boundary spot checks, physical Intel acceptance, or a public release.

## User flow

1. Inspect at least two Matroska files through normal file intake.
2. Choose **Join Files…** in Quick Actions.
3. MKV Magic extracts each exact nested chapter document without modifying it.
4. Include or exclude sources, put them in final order, and explicitly select one
   chapter edition whenever a source contains multiple editions.
5. Review every proposed video/audio/subtitle lane and every static compatibility
   issue. The app never guesses through an ambiguous track mapping.
6. Continue only when the review is a strict zero-encode candidate and every
   first-source output lane has a unique stable Matroska track UID.
7. Choose the deterministic `— Joined.mkv` destination and run an indeterminate,
   cancellable pre-commit job.
8. The app verifies the temporary result, disables cancellation for the final
   commit, reopens the saved result, and records every source in History.

The joined chapter output is one default nested edition. Each source becomes a
top-level **Part** whose timestamps are offset onto the final timeline. The
selected source edition remains nested beneath it; a chapterless part receives a
numbered child boundary.

## Safety and truthfulness

- Exact extracted chapters are revision-bound. Immediately before execution the
  app re-extracts each document, compares its canonical digest, and confirms that
  the chapter revision is the same filesystem revision captured by the join
  preview.
- The GUI cannot bypass the executor's Matroska, full-file, exhaustive mapping,
  stable UID, duration, attachment, or compatibility checks.
- Cancellation terminates the direct `mkvmerge` child process. The verified
  transaction removes its private temporary output and leaves every original
  unchanged. History records `cancelled`, not success.
- Once verification passes and commit begins, the Cancel button is disabled.
- History stores only display names and sanitized lifecycle text. A joined job
  records all input names and never stores source paths or media contents.
- The output is still re-inspected and its canonical nested chapter XML is still
  re-extracted both before commit and after reopen. The native review is not a
  substitute for authoritative bundled MKVToolNix behavior.

## Regression and real-tool evidence

Focused app tests cover deterministic joined output naming; strict ready-state
composition with nested Part chapters; normalization blocking; required explicit
multi-edition choice; and all native controls remaining visible at the 720 by 560
point minimum. A rendered local AppKit artifact confirms the source table, track
lane review, chapter summary, zero-encode status, and final action layout.

A bundled-tool application integration creates two independent AAC Matroska
files, inspects them through the real app model, extracts their chapters, builds
the same native review candidate, creates the revision-bound executor preview,
and saves the verified join. It observes one retained audio lane, two top-level
Part chapters, unchanged SHA-256 source digests, and a sanitized eight-state
History lifecycle containing both input display names.

The complete bundled-tool suite passes all 252 tests with zero skips. The
complete local gate also passes source validation, coverage collection,
AddressSanitizer, ThreadSanitizer, Universal `arm64`/`x86_64` compilation,
inside-out app signatures and entitlements, SBOM/checksums, appcast and ZIP
assembly, and verified sandboxed DMG packaging. A commit-boundary cancellation
regression proves that even a task cancelled after verification cannot commit
the private temporary output.

## Still pending in M5

- Manual lane editing for ambiguous-but-user-resolvable track sets.
- Explicit attachment retention/removal and confirmation-only metadata policies.
- Keyframe-aware fast trim and exact trim with truthful adjusted-boundary review.
- Decode spot checks and copied-stream fingerprints around every join boundary.
- Common-format proposals and one-generation normalization/transcoding.
- Private-library beta acceptance and physical Intel smoke testing.
