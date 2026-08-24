# M8 non-UI coverage gate

This records enforcement of the product specification's public-beta non-UI
coverage target. It does not treat coverage as a substitute for assertion
quality, real-tool fixtures, sanitizers, or manual UX acceptance.

## Measurement contract

The existing source-only LLVM coverage parser continues to aggregate every
production file below `Sources` and enforce the repository's all-source line,
function, and region regression floors. It now also groups all production
targets other than the AppKit executable target `MKVMagic` and requires at
least 80% collective line coverage for that non-UI group.

The AppKit target remains part of the all-source floors. It is separated only
for the additional 80% contract because window construction, platform
callbacks, and visual state require focused policy and manual accessibility
evidence rather than being hidden by a single aggregate.

## Observed baseline

The current instrumented run measures:

- 87.64% non-UI lines — 17,231 of 19,662;
- 69.70% all-source lines;
- 73.82% all-source functions; and
- 62.83% all-source regions.

The strongest target-level line results include 93.34% for Core, 90.21% for
System, 87.28% for Media, 85.17% for Planning, and 84.44% for Execution. The
AppKit executable is 47.52%, which explains why the previous all-source number
did not reveal that the non-UI public-beta target was already satisfied.

## Regression evidence

The normal source gate now runs a synthetic coverage fixture that:

- accepts 90% non-UI lines while excluding an uncovered dependency outside the
  repository source root;
- rejects 79% non-UI coverage even when the all-source floor still passes;
- rejects an all-source line regression; and
- rejects malformed production metrics and a report missing the known AppKit
  target.

The complete instrumented run remains the evidence for real repository counts;
the synthetic test protects the gate's own grouping and rejection behavior.
