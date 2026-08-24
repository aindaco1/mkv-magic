# M9 private Sparkle replacement rehearsal

This records a private production-pipeline rehearsal. It is not a public MKV
Magic release, final-version acceptance, clean-account acceptance, or physical
Intel hardware acceptance.

## Runtime re-signing defect and regression

The first attempt stopped before any Apple submission. The verified runtime
source was copied from an earlier signed rehearsal, so it correctly contained
the immutable `build-manifest.json` provenance files. The app signer could
reseal only a never-signed runtime and refused those existing manifests.

Commit `7a1fd826a3810f9d01a0120825653b28b363fbdb` closes that release-path gap.
The signer now validates the complete copied tool tree before changing bytes,
preserves a valid existing build manifest, and reseals only the current signed
hashes. A focused regression proves both first signing and repeated signing,
proves the build provenance remains byte-for-byte unchanged, and rejects an
invalid existing manifest. The failed candidate was quarantined locally and
was never submitted to Apple.

The full source validation gate then passed 513 tests with 33 intentional
source-only bundled-runtime skips and zero failures. The Universal release
build also passed. GitHub verifies the commit signature, but hosted CI and
CodeQL did not execute: runs `32735860162` and `32735860028` were rejected at
job startup by the repository owner's GitHub billing or spending-limit state
and produced no test logs. Their red status is not represented as test
execution.

## Exact private candidate

The successful candidate was built from the clean, signed source commit above
with version `0.0.0`, build `20260825`, production bundle identifier, fixed
public update feed, production update public key, and the previously verified
Universal bundled runtime. `BUILD-METADATA.txt` binds it to source tree
`750f1b315a0b6e05a41524cd3983694c946747b3`.

The app and DMG were signed with Developer ID. Apple independently returned
`Accepted` for each notarization submission, each artifact received and
validated a stapled ticket, and Gatekeeper accepted both as notarized Developer
ID software. The final distribution verifier then passed the mounted app,
strict nested signatures, reviewed entitlements, exact runtime inventory, and
fixture processing under native ARM64 and Rosetta x86_64 selection. Both paths
created, inspected, edited, verified, preserved, and extracted the fixed local
Matroska fixture.

The production-key appcast and finished artifacts passed their complete local
checksum set. The update archive and DMG digests are:

- `MKV-Magic-0.0.0-universal.zip`:
  `9732590e09d961ac85845ab4567335d3b776ac14d0f1d8927ee332cdbc00a35a`
- `MKV-Magic-0.0.0-universal.dmg`:
  `17d8aea3dcd09198ad8fc445205894fb321fb3ed40fcd0524d563b44a07f7daf`

The production Sparkle key was selected by deriving and matching its public
key to the value shipped in the app. Credential values and source filenames
were not logged or copied into the repository. The two owner-only temporary
credential copies were overwritten and unlinked at completion; a follow-up
check found no remaining rehearsal credential directory.

## Observed replacement

The pinned Sparkle 2.9.5 external updater revalidated the notarized prior app
and candidate, compared the candidate archive signature with the production
appcast signature, and used a loopback-only acceptance feed. It replaced a
disposable copy of private build `20260824` with exact build `20260825` on the
physical Apple Silicon host. The replaced copy retained a strict valid
signature, stapled ticket, Gatekeeper acceptance, and a successful native
fixture result. The installed prior app was never modified.

## Deliberately still open

- No tag, GitHub draft, public release, appcast publication, or installation
  occurred.
- The exact candidate was not downloaded back from GitHub, so published-asset
  readback is untested.
- Rosetta verifies the Intel slice on Apple Silicon, but this is not a physical
  Intel Mac run or a clean-account result.
- The private rehearsal set intentionally has no corresponding-source archive
  and is not a publishable GPL release set.
- Final release acceptance must use the final semantic version and exact final
  tag, include corresponding source, repeat downloaded-draft verification,
  pass clean-account Apple Silicon and physical Intel checks, repeat updater
  replacement against those exact downloaded bytes, and complete the separate
  publication/readback gate.

This evidence makes the first public release's allowed private prior build
concrete; it does not waive any final-candidate gate.
