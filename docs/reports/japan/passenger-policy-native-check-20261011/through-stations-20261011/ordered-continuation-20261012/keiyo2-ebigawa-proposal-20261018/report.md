# Keiyo-2 Ebigawa seam deletion proposal

Status: proposed, not integrated or accepted. Read-only research under current verification policy; no production changes/tests/build/native launch/capture.

The source owner is feature14135 of JR East Keiyo. Existing repair-keiyo-midcurve.mjs keeps N02 alias[139.98762,35.6851] at the join between two OSM-derived windows. The existing keiyo-midcurve-evidence.json records this alias10.059m from the selected source track. Original smooth.png visibly dips south and returns here; original basemap has a gentle uninterrupted railway band. This is a seam defect in display construction, not a passenger topology defect.

The proposed fragment removes that single alias, retaining the two consecutive same-way supports on either side. Exact live route14656663 explicitly binds way1436589310 to Minami-Funabashi to Nishi-Funabashi. Do not replace it from another parallel rail. Existing shared-corridor metadata copies this arm to main Keiyo interval7; apply the same eventual display deletion there and refresh the relevant replay stage/parts once accepted. No production file has been edited.

Original pixels actually reviewed: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004530/000013/smooth.png` and same-directory `basemap.png`; own `view.json` identifies immutable camera.

Sources: [JR East Chiba passenger-network notice, page2](https://www.jreast.co.jp/chiba/news/pdf/pre1508_netrains.pdf); [JR East own Oct2026 train](https://timetables.jreast.co.jp/2610/train/130/132751.html); [explicit OSM route](https://www.openstreetmap.org/relation/14656663). See own-source-fragments.json for exact source records, version/timestamp/ordered memberships and cached source way geometry.

No detailed primary engineering track diagram was located in the bounded search. The JR PDF is a schematic network map and timetable proves passenger direction; the exact branch track geometry is supported separately by named MLIT features, explicit OSM membership and retained original native pixels. Do not promote the schematic to engineering geometry proof.

Next integration: preserve the candidate; update the earliest owning replay/evidence only after parent review, retain unsupported spans, then inspect relevant complete intervals in designated native/Main window. Whole-line output and platform/production joins remain unmeasured.

## Source implementation staged (2026-10-18)

The existing authoritative midcurve builder/evidence now remove precisely the obsolete alias using one shared helper in the existing Minami replay module. The Minami retained/reapply boundaries apply the same pinned deletion to their frozen baseline comparisons; the historical Minami evidence file and Shio source/evidence are unchanged. The retained old post-entrance candidate is explicit in midcurve evidence, and its older pre-entrance candidate remains unchanged. The existing CLI uses partsForRetainedKeiyoStage against its original input package to validate/derive old-to-new parts/follows/family rulers before ordinary repairParts. No new pipeline, stage flag or parallel repair executable was added.

Existing keiyo-shared-corridor.test.mjs now has a regression for the missing alias in both -2 and trunk7, consecutive unchanged guard supports, physical preservation, exact existing Minami station-tail/Shio coordinates, and package/parts idempotence. The existing eastern follow ruler expectation was adjusted only by the local deleted-splice length (2.082469m). Tests/CLI/build/native have NOT been executed by this worker, per the parent's serial window instruction. A targeted JSON query confirmed current evidence candidate equals the frozen old candidate with exactly index68 deleted and both historical candidates remain preserved. Parent owns focused execution and integration.
