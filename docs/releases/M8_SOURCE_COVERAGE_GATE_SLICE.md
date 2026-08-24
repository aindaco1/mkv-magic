# M8 repository-source coverage gate

This slice changes the Swift coverage workflow from artifact-existence evidence
into a bounded regression gate. It does not treat a coverage percentage as a
substitute for assertions, sanitizer runs, real-tool fixtures, or manual UX
acceptance.

## Measurement contract

The workflow still uses SwiftPM's instrumented test run and LLVM JSON export.
A small Swift/Foundation parser then:

- accepts only canonical files beneath this checkout's production `Sources`
  tree;
- excludes tests, generated test runners, Sparkle, and other dependencies;
- validates each line, function, and region count before summing it;
- prints the covered and total counts with percentages; and
- fails closed when the report shape is malformed or no repository source is
  present.

The conservative floors are:

- **65% lines**;
- **68% functions**; and
- **58% regions**.

These floors leave room for deliberate UI and integration work while catching
material untested growth. Raising them should follow real additional coverage,
not exclusion of difficult production code.

## Observed baseline

On the current arm64 development checkout, the source-only report measures:

- **70.08% lines** — 24,466 of 34,913;
- **73.93% functions** — 2,688 of 3,636; and
- **63.08% regions** — 7,416 of 11,756.

The same current tree passes all 510 tests with 33 intentional source-only
fixture skips and zero failures under both Address Sanitizer and Thread
Sanitizer. The ordinary and coverage-instrumented runs also pass with the same
counts. An otherwise valid copy of the LLVM report with every production
coverage counter forced to zero was rejected at the line floor, exercising the
gate's nonzero failure path.

The complete source-validation gate also passes with the Universal Xcode
build, and the isolated package gate verifies its ad-hoc signed app, ZIP, DMG,
appcast, SBOM, checksums, and installed-bundle probe.

The gate does not measure private-media behavior, bundled-tool integration when
`MKV_MAGIC_TOOL_ROOT` is absent, physical M1/Intel hardware, or perceptual UX
quality. Those remain separate acceptance work.
