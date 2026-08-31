# Verification and reporting

## Baseline before mutation

```bash
git status --short
python3 .claude/skills/jtm-railway-audit-repair/scripts/audit_jtm_packages.py \
  --json /tmp/jtm-baseline.json --limit 40
```

It exits 1 while any ERROR stands (two do today), so a non-zero baseline is the expected reading, not a broken command. Record the affected package versions, line counts, station memberships, interval counts, warning codes and current test results. The tree is routinely dirty from parallel sessions — do not attribute pre-existing failures or unrelated edits to your repair.

## Gates that exist in this repository

```bash
SCRATCH=/tmp/jtm-rail-core ./ios/verify.sh --core   # RailCore/RailPresentation + parity tests
SCRATCH=/tmp/jtm-rail-js   ./ios/verify.sh --js     # port-fixtures --check only
SCRATCH=/tmp/jtm-rail-full ./ios/verify.sh          # + Swift textual contracts + app build
```

None of these is quick. `--js` alone regenerates every fixture in `port-fixtures/` — 1.75 million lines of JSON — and runs for minutes, so budget for it rather than treating it as a fast inner-loop check; the preflight above is the ten-second one. `ios/verify.sh` is the main gate. Beyond building and testing, it enforces the textual contracts listed in [repository-contracts.md](repository-contracts.md) — the simplify tolerance, the datum boundary and scope, the annotation layer, the pure-target import ban. A railway change that renames or relocates any of those symbols fails the gate even when behaviour is unchanged.

North America has real Python tests, and they run in under a second. Do not quote a count: a parallel session added 59 of them in one afternoon.

```bash
(cd app/scripts/railway && python3 -m unittest discover tests)
```

Use `unittest`, not `pytest`: the system Python here has no pytest. `audit-north-america-packages.py`, `crosscheck-na-stations.py` and `report-na-coverage.py` exist but require the NA raw inputs (`--registry`, `--gtfs-manifest`, `--build-report`, `--inventory`), which are not committed to this tree. Check for the inputs before promising to run them, and report their absence instead of a pass.

Bundle wiring, when packages or resource names changed:

```bash
tmp_bundle=$(mktemp -d /tmp/jtm-rail-resources.XXXXXX)
./ios/copy-rail-packages.sh "$tmp_bundle"
```

**Do not cite these as evidence:** `npm run lint` fails (`check-source.mjs` was not carried over), `npm test` runs against a tree with no JS test files, and `audit:apple-tiles:jp` / `rebuild:railway:jp` / `generate:*` reference missing scripts. Report them as unavailable rather than as passing.

## Interpreting the preflight

Scope, stated plainly: of the 31 defect classes in [history-and-failure-patterns.md](history-and-failure-patterns.md), this script mechanically detects about eight. Roughly half the rest are routed by this skill's prose but need you plus evidence to settle, and around seven — missing inventory, one railway built twice from two feeds, a service modelled as a railway, corridor extrapolation, shared vertices smoothed apart, pseudo-adjacency cliques, a wrong station coordinate — have no check here at all. A clean run means the format contracts hold. It does not mean the railway is right.

`audit_jtm_packages.py` proves the format contracts and nothing else. Its review classes each have a legitimate cause:

| Code | Real defect it catches | Legitimate cause to rule out |
|---|---|---|
| `STRAIGHT_CHORD`, `SPARSE_GEOMETRY` | an interval drawn station-to-station instead of along the track | a genuinely straight, short interval — but check the builder's source coverage first |
| `DETOUR_RATIO` | per-station projection onto a round-trip shape picking opposite passes (CTA Brown Line: 410 m drawn as 32.6 km) | a real switchback or street loop — Alishan, 木次線 出雲坂根, 영동선 all land here legitimately |
| `VERTEX_JUMP` | missing survey detail inside an interval | a long tunnel or bridge that the official centreline really does describe with two points |
| `REVERSAL_CANDIDATE` | an artificial double-back created by merged directions or bad ordering | a real switchback (Alishan, Hisatsu, mountain lines) |
| `SELF_OVERLAP` | a line drawn twice, or an out-and-back produced by wrong station coordinates (Alaska's Aurora Winter, 72.8%) | very little — the parallel-and-far-apart-along-the-line test already excludes spirals, horseshoes and street running |
| `GEOGRAPHIC_OUTLIER` | a rotated or concatenated station order, or a stray coordinate | none common — investigate every one |

`INTERVAL_RETRACES_LINE` is an ERROR, not a review class: an interval that passes within 40 m of most of its own line's stations is carrying an extra lap, and nothing legitimate has that shape.

Triage each finding and record the conclusion. An untriaged warning is not a pass, and `--strict` is only meaningful once the scope's warnings have been reviewed.

Know what it **cannot** see, and cover those separately when they are in scope:

- **Inventory.** It never asks whether a railway that should exist is absent.
- **The same railway built twice from two feeds.** `SELF_OVERLAP` only sees a line lying on *itself*. Cross-line duplication needs a corridor comparison plus a station-set overlap test; the operator string is exactly the wrong key.
- **Whether a station's coordinate is right.** It can tell you the geometry doubles back; it cannot tell you Fairbanks is on the wrong peninsula.
- **A uniform shift.** Every geometric test here is relative, so a package shipped wholesale in GCJ-02 instead of WGS84 passes silently — verified by mutation. Datum questions need the multi-point audit in [regional-evidence.md](regional-evidence.md), never this.
- **Seam-scale micro-kinks.** The 41% spike rate that multi-source splicing gave Hong Kong sits below `REVERSAL_CANDIDATE`'s 40 m minimum edge, by design — raising it would bury the real switchbacks.

Measured sensitivity, from injecting each defect into a clean package and rewriting `km` the way a builder would:

| Injected defect | Caught by |
|---|---|
| station-to-station chord | `STRAIGHT_CHORD` |
| out-and-back excursion, +4 km on a long line (1.8x) | `SELF_OVERLAP` only — below `DETOUR_RATIO`'s 3x floor |
| out-and-back, +24 km (4x) | `DETOUR_RATIO`, `SELF_OVERLAP` |
| an extra lap of the line | `INTERVAL_RETRACES_LINE` + three others |
| artificial spike at a vertex | `REVERSAL_CANDIDATE` |
| anchor moved 220 m off its line | `ANCHOR_OFF_LINE` |
| one interval teleported 300 km | `GEOGRAPHIC_OUTLIER` |
| whole package shifted to GCJ-02 | **nothing** — see above |

`DETOUR_RATIO`'s floor is deliberate: below about 3x, honestly winding track is indistinguishable from a fake excursion by ratio alone. `SELF_OVERLAP` covers that half instead, and fires on share **or** absolute length (≥10% or ≥1.5 km), because share alone dilutes a local defect on a long line — a 4 km excursion on the 宜蘭線 is 4%.
- **What either client actually draws.** Everything after the package — grooming, lanes, simplification, LOD, the datum boundary, endpoint snapping, graph-edge geometry — is invisible here.

## Regeneration review

1. Regenerate only the affected region and its dependent artefacts.
2. Review the semantic diff across package, stations, rail sections, readings, sample stores, precomputed parts, fixtures, source notes, logos and audit ledgers.
3. Confirm version/provenance changes are intentional.
4. Re-run the preflight and compare against the baseline JSON — the interesting number is which codes appeared or disappeared, not the total.
5. Confirm both clients still consume the same package through `ios/copy-rail-packages.sh`.

## Visual checks, when rendering is in scope

- **WebUI:** the exact problem location plus representative low, medium and high zooms; include a dense metro, a branch or loop, a terminal, and one control line that was already correct.
- **iOS:** build and run the current source, same locations, comparable camera framing, and check the complete network, the ridden-route path and playback separately.
- Compare against the Apple basemap track, not against an Apple Maps POI: a search result may be an entrance, a building or a complex centroid rather than the platform.
- Save screenshots or coordinates alongside the report when they carry a conclusion. If the map cannot be driven reliably, report the visual audit as `INCOMPLETE` rather than inventing evidence.

## Result taxonomy

- `PASS` — the checked invariant is supported by adequate evidence and passed.
- `WARNING` — suspicious or incomplete evidence, review needed, no defect proven.
- `ERROR` — a reproducible defect violating a defined invariant.
- `INCOMPLETE` — the requested scope could not be fully checked because data, coverage, environment or visual evidence was unavailable.

Count global and orphan findings separately from per-line results so they cannot vanish from the headline.

## Final report template

```text
Scope
- Regions and package versions
- Mode: audit / diagnosis / repair
- Lines, stations, intervals and rendered subjects checked

Evidence
- Primary sources with version/date, CRS, licence
- Secondary cross-checks; ambiguous evidence excluded and why

Findings
- Inventory and identity
- Stations and memberships
- Topology, direction and branch behaviour
- Surveyed geometry and basemap alignment
- WebUI final rendering
- iOS final rendering and the datum boundary
- Global / orphan issues

Changes (repair mode only)
- Owning source / builder / override
- Generated artefacts
- Why the fix is bounded and reproducible

Verification
- Exact commands, pass/fail counts, warning codes triaged
- Visual locations and zooms
- Cross-platform parity and final-render checks

Unresolved
- Warning ledger with the conclusion for each
- Evidence still required
- Result: PASS / WARNING / ERROR / INCOMPLETE
```
