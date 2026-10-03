# Limited-express passing-station evidence cleanup

The historical timetable database and the recorded sample rides serve different
service dates. September 2026 timetable records cannot establish July, May or
New Year sample paths. Missing official passing rows remain unknown; neither a
station directory nor a shortest-path solve can become a timetable fact.

## Findings and changes

The canonical timetable contains 882 trips, 8,520 station rows and 30 `pass`
rows. All 30 are the explicitly printed 品川 `レ` mark in individual Narita
Express Shinjuku branch columns. Each registered official page was rechecked.
For example, [Narita Express 1](https://timetables.jreast.co.jp/2610/train/030/031131.html)
prints 品川 `レ` in the 2201M column while the paired 2001M column gives passenger
clocks; [Narita Express 54](https://timetables.jreast.co.jp/2610/train/030/031291.html)
does the same for its secondary branch. The review sidecar pins all 30 URLs,
trip/sequence/station identities and the printed mark. No station rows were
added or deleted from the canonical timetable.

The validator now rejects a `pass` row without high-confidence, verified,
row-specific `call_type` evidence from the same source and a source locator.
Trip-level stop evidence alone cannot satisfy this requirement. Reviewed marks
are normalized after the existing source-pinned inputs; the normalizer refuses
changed station/sequence/source identities. Future source review must attest an
explicit passing row rather than interpreting a blank clock, an omitted
station or a different route's `||` mark as evidence.

Japan's 256 loaded rides contain 43 limited-express/sleeper rides. The cleanup
removes **1,035 unsupported passing rows from 38 rides** and discards the
physical-line/operator sections inferred from those station chains. It retains
**81 source-listed passing rows in five exact-date, physically reviewed ride
intervals**: Shirasagi 6, Shiokaze 5, Nanpū 9, Nanpū 17 and Nanpū 28. Passenger
calls and their clocks are preserved, including clocks after 24:00. Foreign,
local, rapid and Shinkansen sample inventories are outside this cleanup.

Sunrise Izumo retains its 14 source-reviewed passenger calls and the confirmed
operating-number change from 5031M to 4031M at 岡山. Its 203 unsupported physical
passing rows and guessed physical line constraints are removed. Its known 新垂井
branch and 手柄山平和公園 inventory gaps still prevent full physical-route
verification. Six sample rides retain historical passenger timetable review;
the other 37 limited-express/sleeper passenger lists remain historically
unverified. Existing passenger rows are preserved records, not newly certified
calls. The 38 cleaned rides disclose their physical-route uncertainty in notes.

Regenerated sample map geometry is a **visualization hypothesis between the
recorded passenger calls**, not the actual published train path. It must never
be imported into the timetable's stop list, elevated to physical-route evidence
or called a verified passing sequence. Removing old anchors intentionally
allows different inferred map geometry; that difference cannot resolve the
Sunrise source gaps.

## Reproduction and review records

```sh
python3 app/scripts/samples/remove-unverified-limited-express-passes.py
node app/scripts/build/precompute-train-parts.mjs
PRECOMPUTE_STORE=app/data/special-samples/tokyo-limited-express-loop.json PRECOMPUTE_OUT_DIR=app/data/tokyo-limited-express-loop-data node app/scripts/build/precompute-train-parts.mjs
python3 app/scripts/samples/align-sample-timetable-fields.py
python3 app/scripts/samples/remove-unverified-limited-express-passes.py --check
python3 app/scripts/samples/repair-japan-sample-timetables.py --check
python3 app/scripts/samples/align-sample-timetable-fields.py --check
```

`sample-passing-station-audit.json` retains the removed names, exact service
dates, source-review URLs, counts and cache interpretation for every in-scope
ride. `reviewed-pass-marks-20261003.json` owns the canonical passing evidence;
`normalize-reviewed-pass-marks.py` regenerates its row-level provenance.
The canonical database and RailCore bundled fallback are rebuilt together.
Changed sample payloads invalidate prior port fixtures; those must be regenerated
before relying on native parity evidence. A sample geometry hash or successful
solver run establishes consistency with its input package, not train-route
truth or historical timetable coverage.

Validation so far: 14 sample tests and 35 timetable pipeline tests passed.
The source snapshot verification reports matching canonical/runtime SQLite,
rail-history revision 2026-09-28.3, Japan timezone and no integrity/alignment
errors. These are scoped checks, not a complete inventory certification.

## Native editor scope

`TrainTimetableDatabase.editorProjection` retains passenger calls only. Verified
line boundaries remain `routeSections`; importing a dated timetable does not
synthesize `pass_through` station rows at hidden junctions.

`RideEditorView` removes the automatic Tokyo-default inference task. The
explicit `rideEditorInferRoute` action requests the shortest physical draft
path while preserving every recorded anchor, then presents preview and
confirmation. The manual range action remains available. Generated passing
labels disclose that they are inferred physical points with no timetable-call
provenance. These editor strings cover four languages.

Native UI edits are frozen and passed to the separate autofill work in a
sequential writer handoff. No app or native UI PASS is claimed by this report.
The 12 inference and five save/export Swift tests passed in the publisher's
targeted runtime run. The concurrent `LocalJourneyAutofill` compile defect has
been corrected. Full Core and native UI validation remain incomplete. North America samples are
preserved; none of their canonical sources or generated geometry is changed by
the Japan passing-station cleanup.

## Final source freeze and remaining publishing checks

The repeatable cleanup also removes `preferred_line_names` and
`preferred_operator_names` from every cleaned limited-express sample. These
old route-policy hints came from the same unverified paths as the discarded
sections and must not steer new physical inference as source facts.

Final generation now solves all 256 Japanese samples with matching canonical,
full and part train payloads and source attestations (details below). The broad
sample alignment check previously failed on an already stale Canada manifest.
No North America canonical source or generated geometry was modified by this
work; that existing failure is reported separately from the Japan checks.

Machine-readable file ownership, absolute paths, hashes, interim results and
stale generated artifacts are recorded in
`sample-passing-cleanup-artifact-manifest.json`. The timetable's canonical
fingerprint after row-level passing evidence is
`1eab79052da2b9b1c343146540a9689891845492796c238ab1a7207ad7deb7ee`.
Its rebuilt canonical and RailCore runtime SQLite SHA-256 is
`44dbd21da235bbeab2f9ef1a38c16812ecb8932abb3b55adcfc00c9c120ac926`.

## Route inference and undo verification scope

The draft-only inference kernel's 12 focused regressions passed in the
publisher's targeted native runtime gate. They cover ordered passenger anchors, competing alignments,
physical direction, repeated visits, explicit line constraints, non-call line
boundaries, and applying/undoing a complete proposal. Whole-draft undo now
restores the exact original source sections as well as station visits and clocks;
normalizing a source boundary into adjacent passenger pairs must not erase it.
Operator constraints use existing company identity labels so published `JR東日本`
and package `東日本旅客鉄道` resolve consistently while other JR companies remain distinct.
The existing partial-span editing behavior remains intact. The earlier package
compile was blocked by a concurrent `LocalJourneyAutofill.swift` dependency error;
that failed compile is not a passing Swift test result.

## Final cache regeneration supersedes the interim result

The final publishing run regenerated all 256 Japanese samples: the 201 regular
samples, 39 New Year samples, and 16 Tokyo limited-express samples all have
solved caches, with no unsolvable entries. Canonical/full/part train payloads and
source-data attestations match exactly. This supersedes the earlier stale-cache
and NEX-unavailable results above, without restoring any discarded passing rows.

The NEX failure came from precompute geometry admission: raw samples had no
explicit physical sections, but solving their sparse calls requested inferred
総武線 interval identities. The earlier adapter collected only raw section line
IDs, so the physical geometry was unavailable. The publisher fixed lazy admission
of the actually requested line IDs, interval prefixes and their station-circle
owners. Two regressions against the real package passed; the NEX slice then
produced one physical feature in 100 ms. That one physical feature was rechecked
against the package with zero geometry differences. This does not constitute a
visual audit of all 256 rides or proof of their actual historical train paths.

Evidence: `/private/tmp/jtm-final-jp256-post-cleanup-proof.json`,
`/private/tmp/jtm-precompute-inferred-geometry-regression.log`, and
`/private/tmp/jtm-final-jp-nex-inferred-geometry-slice.log`. Golden generation,
Node checks, the full Core gate and native UI validation remain pending at this
report revision; no passing results are claimed for those gates yet.

## Save/reopen integration follow-up

The export path originally rebuilt route sections only for adjacent recorded
stops. For passenger calls A, B and verified physical sections A–X, X–B,
that discarded both source sections and their line constraints. Both Swift and JavaScript patches are now adopted in the canonical source,
with five Swift and 15 JavaScript regression tests. Canonical JavaScript bytes
match the reviewed temporary implementation that passed all 15 tests. No new
runtime job was started during the native owner's exclusive CPU window. It retains a continuous authored chain only
when its explicit endpoints consume every recorded visit in order. It adds no
passing stops and does not infer passenger-call coverage inside a section.
Incomplete, discontinuous, genuinely out-of-order, conflicting-code, or
insufficient repeated-visit chains use the existing adjacent-pair fallback.
The first and last calls are pinned to the first and last boundaries; distinct
intermediate boundaries consume the intermediate calls in order. A future call
or destination may also be passed earlier without consuming its later visit.

The real classic JavaScript import/export path reproduces six failures among
15 targeted tests with the original implementation; the temporary patch passes
all 15, independently rerun by Codex. Five Swift tests covering JSON save/reopen,
invalid chains, repeated visits and actual route-edit/apply/undo/save passed
against the patched Core. Both owned suites (17 tests) completed successfully;
the combined 60-test, nine-suite run still failed with two issues in the separate
`JapanThroughServicesTests` suite. Its log is
`/private/tmp/jtm-post-cleanup-targeted-core-union.log`; this is scoped success,
not a passing full Core or native UI gate.
A test-constructor argument ordering mistake in the inference suite was corrected
before the next publisher run. The full shared Core gate remains unverified;
its subsequent batch reported parity/provenance failures and signal 10 without
a completed passing summary.

A bounded Grok 4.7 xhigh read-only review of the inference/editing/test files
produced no findings after 18 minutes and was stopped (exit 130). It made no
edits and is not counted as validation. Codex retains responsibility for source
review and integration.

Final adoption evidence: `/private/tmp/jtm-pass-export-fix/swift-canonical-adoption.json`
and `/private/tmp/jtm-pass-export-fix/javascript-canonical-adoption.json`.
The empty-catalog export comparison of all 256 raw Japanese samples changed no
train payloads. The shared golden generation later failed on missing station
candidate-index initialization in its route-graph fixture setup; the publisher
owns that fixture repair and remaining full Node/Core/native verification.
