# M8 keyboard and VoiceOver baseline slice

This slice fixes one concrete keyboard defect and makes the four central MKV
Magic surfaces substantially more understandable to assistive technology. It is
automated AppKit evidence, not a claimed manual VoiceOver acceptance pass.

## Keyboard contract

- **Command-O** in File → Open now targets the main controller's existing local
  file/folder chooser. Previously the menu item displayed the shortcut but had
  no action or target.
- The main window initially focuses **Choose media files or folders**.
- Queue and History initially focus their primary tables so arrow-key navigation
  starts in the useful content rather than an arbitrary control.
- Saved-workflow plan review initially focuses **Use This Plan** or **Done**.
  Return activates it; Escape cancels an actionable review.
- These are native AppKit responders and controls. The slice adds no global key
  monitor, synthetic event injection, shell command, network dependency, LLM,
  or custom animation.

## VoiceOver contract

Explicit accessibility names and concise help now cover:

- the inspected-media list, selected-media details, segment-title field,
  application status, and current plan impact;
- the production-queue table, summary, pause/cancel/reorder controls, and the
  context-dependent Hold, Resume, or Review Again action;
- the History table, selected job progress, report export, and export status;
  and
- workflow/source context, encoding impact, ordered card outcomes, source
  safety, acceptance, and cancellation.

Visible native button titles remain their actions. Help explains consequences
without hiding essential safety information exclusively from sighted users.

### Workflow editor continuation

The saved-workflow editor now begins in its workflow list and gives explicit
names and help to the workflow/step tables, name and status fields, new-workflow
button, step menu, reorder/removal controls, import/export, save, and preview.
Native **Command-S** saves the local workflow library; Return remains **Save &
Preview**. When no inspected Matroska file is selected, the disabled preview
control explains the prerequisite to VoiceOver instead of exposing only an
unavailable action.

## Regression evidence

Seven focused AppKit tests prove:

1. File → Open has Command-O, the correct selector, and the live main-controller
   target.
2. Each audited window has the intended initial responder.
3. The main accessibility tree contains the media, inspector, title, status,
   and impact names.
4. Queue and History expose their table/detail names and meaningful control
   help.
5. Workflow review exposes context, impact, outcomes, safety, Return, and Escape.
6. The workflow editor begins in the saved-workflow table, exposes its core
   builder semantics, and maps Command-S and Return to distinct native actions.
7. An unavailable workflow preview explains that an inspected Matroska file is
   required.

All seven focused tests pass with zero failures. After the workflow-editor
continuation, the complete local gate passes with **501 tests, 33 expected
real-tool fixture skips, and zero failures** in each of its normal, coverage,
AddressSanitizer, and ThreadSanitizer modes. Its Universal app and package
checks verify nested Sparkle signing, the update archive and appcast, SBOM,
third-party notices, checksums, build metadata, ZIP, and DMG.

## Still required for M8 acceptance

- Walk every implemented window using only the keyboard with macOS Full
  Keyboard Access both enabled and disabled where applicable.
- Perform an observed VoiceOver traversal on a packaged app, including dynamic
  queue state changes, disabled controls, sheets, tables, outline views, and
  Save/Open panels.
- Test Increase Contrast, Differentiate Without Color, Reduce Transparency,
  Reduce Motion, larger display scaling, and representative light/dark themes.
- Audit every label, error, warning, and focus return after cancellation or
  failure; verify localization-safe layout.
- Repeat on the M1 reference and physical Intel Mac. No physical-hardware,
  private-library, signed/notarized-build, or public-release acceptance is
  claimed by this slice.
