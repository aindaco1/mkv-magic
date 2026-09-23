# Jev development evaluation

Jev is a default local development check, following the CutNotes evaluation
pattern. It evaluates explanations against structured evidence from existing
MKV Magic tests. It is not compiled into the app or used for media processing.
The deterministic planner, output verifiers, and safety assertions remain
authoritative. No shared application dependency or second workflow engine was
introduced.

## Run

```sh
python3 scripts/test.py
python3 scripts/test.py --offline
python3 scripts/test.py --dry-run
```

The standard command runs `scripts/ci/validate.sh` (including offline evaluator
regressions), then labeled calibration/validation and fresh workflow review.
The validation script is still the common deterministic gate used by hosted CI;
CI has no Jev credential and makes no inference calls. The standard local command
uses a stable Swift scratch directory under the system temporary directory to
keep generated signed test bundles outside cloud-synced source folders. An
absolute `MKV_MAGIC_SWIFT_SCRATCH_PATH` overrides that location.

Configure `MKV_MAGIC_TOOL_ROOT` with an absolute path to a verified bundled
runtime. `.build/tool-runtime` is the shared local runtime location, also used
by the packet-audit benchmark. The real-media scenario is mandatory: an absent runtime, skipped
exporter, missing result, or changed source stops full evaluation. There is no
fallback to Homebrew media tools. `--offline` can run without a runtime, but any
skipped tool tests remain unverified.

Configure `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` in the environment,
or use an existing Wrangler login. Authentication invokes the locally cached
Wrangler 4.136.2 through `npx --no-install`; it does not install dependencies or
initiate a login. The ignored `.mkv-magic-development.json` may hold only
`cloudflare_account_id` and `tool_root`. Never store an API token in this file.
Missing credentials are an error, not a silent skip.

Every run gets a new `.build/jev/development-*` directory. `--output-dir` can
select another new directory. Prior reports are never overwritten. Reports
distinguish full, offline, and request-preview runs; only a full successful run
sets `full_suite_passed`. No report sets `release_accepted`.

## Registered evidence

`WorkflowEvidence` is a test-only exporter. Its call sites are the existing
common-flow, reviewed-batch, real-tool History, and AppKit policy tests. The
export contains named Boolean observations and actual application explanations,
never serialized app models. The scenario registry is
`scripts/testing/jev-cases.json`.

| Scenario | Evidence actually exercised |
| --- | --- |
| Metadata plan | Zero-encode property edit, temporary clone, verify then commit |
| Fused exact trim | Exact trim and conversion share one planned video generation |
| Cleanup review | Planned cleanup remains awaiting approval; production status labels |
| Already-satisfied cleanup | No runnable plan or Run action; the summary explains that no output is needed |
| Remux review | One remux with zero video/audio encodes |
| Waiting queue | Two independently reviewed jobs wait without execution attempts |
| Subtitle cold queue | Four SRT/ASS cleanup jobs survive model/store reload, pause, and drain; exact output hashes and unchanged originals |
| Changed source | Stale input requires fresh review; another job completes; retry retains identity |
| Failed retry | A real injected History-write failure followed by reviewed retry; attempt count increases |
| Cancellation | Cancelled subtitle execution preserves the original and commits no output |
| Restored real remux | Bundled tools execute a restored plural-sidecar job; tracks, metadata, source hashes, and lifecycle are audited |
| Commit boundary | Native controller disables cancellation during atomic commit and explains why |

The level in each report distinguishes planner, presentation, model, local
execution, generated media, and native-controller evidence. A fresh model is
not a cold launch of a sandboxed installed app. The native-controller case is
not a screenshot or a complete keyboard/VoiceOver session. Those checks remain
in the existing native, hardware, private-library, and release acceptance ledgers.

Pending-step review receives only the actionable step names and their production
status labels. Already-satisfied steps have a separate scenario; mixing both
without their dispositions made the first judge run misinterpret a valid preview.
Calibration also exposed ambiguity in the phrase "applied cleanup steps". The
final question asks whether the listed changes are future work or already
executed. The 0.10 margin was retained; the final calibration's smallest observed
margin was 0.65. The original validation examples are now retained regressions,
and six fresh pairs were written before the final validation run.

The evidence manifest binds all registered outputs to the current Swift source,
test/evaluator source, fixtures, policy, dependency lock, and a
successful local validation. Unknown IDs/fields, wrong types, changed hashes,
symlinks, oversized content, and obvious path/contact data are rejected before
authentication. This is an allowlisted synthetic-test workflow, not a general
redactor or permission to upload arbitrary local text. Do not add private or
custom fixtures to its exporter. Remote requests contain only projected facts,
explanation text, and the fixed question; no manifest, paths, raw test logs,
source code, media, subtitles, credentials, or support diagnostics are sent.

## Calibration and interpretation

The corpus contains 12 labeled good/bad calibration pairs, six retained regression
pairs, and six fresh validation pairs (48 examples). Labels are engineering judgments,
not independent human ratings. Each question judges one explicit meaning in
the candidate explanation; facts provide context and cannot substitute for
words missing from that explanation. Tests still check exact numerical,
structural, and preservation contracts independently.

The review policy uses a fixed minimum 0.10 margin between the top two returned
probabilities. Ties, ambiguous answers, and unrecognized model versions route to
`review`, which fails the full development check. Calibration must correctly
classify deliberately bad examples as failures. The ordinary run never tunes
questions, changes thresholds, or updates the accepted model list.

To bootstrap a changed protocol, run:

```sh
python3 scripts/testing/jev.py --calibrate --output-dir .build/jev/new-calibration
```

It uses only calibration labels and writes a proposed policy only if every
example is correctly classified with the fixed margin. Inspect that proposal
before replacing `scripts/testing/jev-policy.json`, then run separate validation
and fresh workflows. Inspected validation examples become regressions; after
prompt tuning, create new held-out examples rather than reporting old validation
as independent evidence.

Saved, hash-bound evidence can be reviewed without repeating native tests:

```sh
python3 scripts/testing/jev.py \
  --evidence-dir .build/jev/EXISTING-RUN/workflow-evidence \
  --output-dir .build/jev/new-review
```

`--dry-run` on this command previews requests without authentication. Saved
evidence must still match current source. This command alone never establishes
a fresh full-suite pass. API errors stop immediately without automatic retries,
fallback, purchase, or top-up. Reports retain validated responses, resolved model,
probabilities, usage, protocol hash, calibration hash, and actual candidate text.

The default 60 requests (48 labeled examples plus 12 workflow cases) reserve a
conservative inference estimate of $0.08064 using 32,000 input tokens per request
and the dated TypeSafe list price of $0.042 per million input tokens. The helper
refuses more than 100 requests or an estimate above $0.25 by default. These are
estimates, not provider-enforced billing caps or receipts; Cloudflare billing
remains authoritative.

Reference: [TypeSafe model inputs and pricing](https://docs.typesafe.ai/models),
[atomic questions](https://docs.typesafe.ai/introduction), and
[confidence interpretation](https://docs.typesafe.ai/confidence).

## Validation record

22 September 2026, on the local Apple Silicon development Mac:

- `python3 scripts/test.py --output-dir .build/jev/development-final` exited 0.
- Source/security/format checks and the Universal release build passed.
- Swift ran 891 tests with zero failures and one optional private-media skip.
  All 12 mandatory evidence scenarios ran, including the bundled-tool remux.
- All 19 offline evaluator/runner regressions passed, covering source/evidence
  binding, private-field rejection, malformed responses, uncertain/new models,
  failure precedence, no retries, request previews, and scratch-directory use.
- Jev 1.13.0 matched all 24 calibration labels, all 12 retained regression
  labels, and all 12 fresh validation labels; all 12 workflow reviews passed.
- The final 60 requests used 31,056 input tokens and 2,400 output tokens. The
  dated inference estimate was $0.001304352, not a billing receipt and excluding
  the earlier calibration and diagnostic runs.

Evidence is retained locally in `.build/jev/development-final/`: the development
report, source-bound workflow manifest, individual observations, request and
response JSON, and readable Jev review. `.build/jev/development-first/` retains
the initial 10/11 workflow result. That failure exposed insufficiently scoped
test evidence and ambiguous calibration wording; no application behavior or
confidence threshold was changed to obtain the final result.

No physical Intel, installed-app, private playback, or release acceptance is
implied. Source and generated test evidence cannot substitute for those gates.

After reconciling the published macOS 27 fixes on September 23, the full
development check passed again: 893 Swift tests with one optional private-media
skip, 19 evaluator regressions, all 48 labeled examples, and all 12 workflows.
The Universal build and source/security checks passed. The source-bound report
is retained locally in `.build/jev/release-0.3.0/`; the rubric, model policy,
and calibration labels are unchanged.
