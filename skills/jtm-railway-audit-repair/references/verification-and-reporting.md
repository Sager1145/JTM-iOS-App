# Verification and reporting

## Baseline before mutation

```bash
git status --short
git diff --check
python3 skills/jtm-railway-audit-repair/scripts/audit_jtm_packages.py \
  --repo . --countries jp,tw,hk,mo
```

Save the affected package counts, version, line IDs, station memberships, segment counts, warnings, and current test results. Do not attribute pre-existing failures or unrelated dirty files to the repair.

## Current standalone repository gates

Run the narrowest useful gates while iterating, then the proportionate full gate:

```bash
SCRATCH=/tmp/jtm-rail-audit-core ./ios/verify.sh --core
SCRATCH=/tmp/jtm-rail-audit-js ./ios/verify.sh --js
SCRATCH=/tmp/jtm-rail-audit-full ./ios/verify.sh
```

Additional useful checks:

```bash
(cd app && npm run lint)
(cd app && npm test)
tmp_bundle=$(mktemp -d /tmp/jtm-rail-resources.XXXXXX)
./ios/copy-rail-packages.sh "$tmp_bundle"
```

Interpret `npm test` honestly: a zero-test run is not coverage. The canonical `ios/verify.sh --js` check validates the retained JS fixture contract, while the Swift suite validates port parity and app-specific invariants.

If the original Web repository contains dedicated validators, discover and run the affected ones under `app/scripts/validation/` and their tests. Prefer existing project commands over reconstructing them from historical filenames.

## Regeneration review

After changing a builder or source:

1. Regenerate only the affected country and dependent artifacts.
2. Review the semantic diff in the package, stations, rail sections, readings, samples, fixtures, source notes, logos, and audit ledgers.
3. Confirm package version/provenance changes are intentional.
4. Re-run the structural audit. Use `--strict` only when every heuristic warning in the selected scope has been triaged; warnings are review candidates, not automatic proof of defects.
5. Confirm Web and iOS consume the same package through `ios/copy-rail-packages.sh`.

## Required visual checks when rendering is in scope

- WebUI: inspect the exact problem location and representative low, medium, and high zooms; include dense metros, branches/loops, terminals, and a normal control line.
- iOS: build/run the current source, use the same locations and comparable camera framing, and inspect both full network and ridden route/playback paths.
- Check light and dark railway contrast only when style changed; geometry work should not be accepted solely because the line is visually attractive.
- Save screenshots or coordinates with the audit report when they materially support a conclusion. If the map cannot be controlled reliably, report the visual audit as incomplete rather than inventing evidence.

## Result taxonomy

- `PASS`: the checked invariant is supported by adequate evidence and passed.
- `WARNING`: suspicious or incomplete evidence needs review but does not yet prove a defect.
- `ERROR`: a reproducible defect violates a defined invariant.
- `INCOMPLETE`: the requested scope could not be fully checked because authoritative data, coverage, environment, or visual evidence was unavailable.

Count global/orphan findings separately from per-line results so they cannot disappear from the headline summary.

## Final report template

```text
Scope
- Countries and package versions
- Requested mode: audit / diagnosis / repair
- Lines, stations, intervals, and rendered subjects checked

Evidence
- Primary sources, versions/dates, CRS, licences
- Secondary cross-checks and excluded ambiguous evidence

Findings
- Inventory/identity
- Stations and memberships
- Topology and direction/branch behavior
- Surveyed geometry and basemap alignment
- WebUI final rendering
- iOS final rendering and datum boundary
- Global/orphan issues

Changes (repair mode only)
- Owning source/builder/override
- Generated artifacts
- Why the fix is bounded and reproducible

Verification
- Exact commands and pass/fail counts
- Visual locations and zooms
- Cross-platform parity and final-render checks

Unresolved
- Warning/error ledger
- Evidence still required
- Final result: PASS / WARNING / ERROR / INCOMPLETE
```
