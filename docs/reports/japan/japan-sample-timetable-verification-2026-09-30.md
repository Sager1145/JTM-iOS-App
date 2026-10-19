# Japan sample timetable verification — 2026-09-30 (America/Toronto)

Evidence and sidecars use the retrieval date 2026-10-01 UTC; this report uses the local September 30 date.

The loaded Japan sample inventory contains **256 recorded rides**: 201 July/August rides, 39 New Year loop rides and 16 Tokyo limited-express loop rides. This revision verifies complete passenger-call timetables **within the recorded ride interval for six services (45 calls)** against official, service-date-specific tables. Five also have matching complete physical-station sequences. The remaining **250 rides have not received historical full timetable verification in this revision**; inventory coverage must not be reported as timetable coverage.

## Verified changes

| Recorded ride | Official service date | Ridden interval | Passenger calls | Physical station rows | Operating number |
|---|---|---|---:|---:|---|
| Shirasagi 6 (`20260708_02_shirasagi2`, legacy ID retained) | 2026-07-08 | 敦賀—米原 | 3 | 12, matching | 6M |
| Shiokaze 5 | 2026-07-23 | 岡山—宇多津 | 3 | 13, matching | 5M |
| Nanpū 9 | 2026-07-24 | 宇多津—阿波池田 | 6 | 14, matching | **39D**, corrected from 9D |
| Nanpū 17 | 2026-07-24 | 阿波池田—高知 | 6 | 24, matching | **47D**, corrected from 17D |
| Nanpū 28 | 2026-07-24 | 高知—岡山 | 13 | 49, matching | **58D**, corrected from 28D |
| Sunrise Izumo | 2026-07-29 | 沼津—出雲市 | 14 | 217 official rows; two differences below | 5031M before 岡山; 4031M from 岡山 |

The update fills **40 arrival/departure fields**, corrects the two 大杉 calls previously marked as passing, corrects three displayed Nanpū operating numbers, and supplies operating numbers on **323 consecutive route sections**. Existing Sunrise overnight times (24:53 through 34:00) already match. Its route-section numbers now change at 岡山, and a short note records its coupling with Sunrise Seto before 岡山. Shiokaze's paired Ishizuchi number is not applied to the Shiokaze ride. Service marketing numbers such as 南風28号 are different from operating numbers such as 58D.

## Official evidence

Each source's operating calendar was checked in the specific July date's `drivingday-01` cell. A `date=` query alone does not prove the service operates that day: IDs may be reused between editions, and links to alternate service variants can retain the original query date even when their calendars exclude it. The complete source table was reviewed, including all passing station rows in the ridden interval; changes retain only ride-local metadata. The machine-readable review records publisher, issue, source URL, retrieval SHA-256, calendar locator, full passenger-call comparison and explicit gaps.

- [Shirasagi 6, July 8](https://timetable.jr-odekake.net/train-timetable/259871?date=20260708), JR timetable July 2026 issue.
- [Shiokaze 5, July 23](https://timetable.jr-odekake.net/train-timetable/291?date=20260723), August 2026 issue.
- [Nanpū 9, July 24](https://timetable.jr-odekake.net/train-timetable/59471?date=20260724), August 2026 issue.
- [Nanpū 17, July 24](https://timetable.jr-odekake.net/train-timetable/104441?date=20260724), August 2026 issue.
- [Nanpū 28, July 24](https://timetable.jr-odekake.net/train-timetable/104481?date=20260724), August 2026 issue.
- [Sunrise Izumo, July 29](https://timetable.jr-odekake.net/train-timetable/38481?date=20260729), August 2026 issue; the table also contains Seto columns, whose separate route must not be mistaken for Izumo's route.

These are official JR West / Kotsu Shimbun tables, including JR Shikoku and JR Central through services. Raw official tables are retained outside the repository for verification only; this change introduces no scraper and no source-table redistribution permission. The repository's September 30 normalized timetable database was not substituted for July or earlier rides.

## Remaining source and route gaps

Sunrise's passenger calls and all passenger times match, but full physical route correctness remains unresolved. The sample includes 垂井 while the official downhill table omits it (the 新垂井 branch). The source includes 手柄山平和公園 between 姫路 and 英賀保, opened after the N02-25 inventory used by the sample, while the sample lacks it. Neither discrepancy was hidden by changing timetable metadata or drawing unsupported geometry. Thus Sunrise has status `passenger_timetable_verified_route_gap`, not `ridden_timetable_verified`.

The New Year loop (2025-12-31/2026-01-01) and Tokyo loop (2026-05-29) remain historically unverified at full timetable/operating-number scope. The [official Tobu Nikko inbound timetable](https://www.tobu.co.jp/pdf/railway/timetable_nikko_up.pdf?20250314=) states the March 14, 2026 revision and corroborates the Spacia Nikko 4 ride's 浦和18:10, 池袋18:29 and 新宿18:35 calls. It does not provide date-specific JR/Tobu operating numbers, so the later JR page's 1094M was not used to claim historical full verification. The [official New Year announcement](https://www.jreast.co.jp/press/2025/20251017_ho01.pdf) supports the seasonal overnight operation, not every regular service's complete timetable. Existing special-loop sources must be audited for effective dates before treating them as historical evidence.

## Loaded-data parity and validation

Canonical inputs are `app/data/train-store.json`, `app/data/special-samples/new-year-grand-loop.json`, and `app/data/special-samples/tokyo-limited-express-loop.json`. Their loaded copies live in `sample-data`, `new-year-grand-loop-data`, and `tokyo-limited-express-loop-data`, respectively. The repair synchronizes canonical, `sample-full` and the six affected `part` train payloads. All part `route` objects, solver contexts, station identities, topology and geometry are preserved. Route template keys do not include stop times/types or section operating numbers; hard line/operator constraints and all section endpoints are unchanged.

Apply or check the manually reviewed repairs:

```sh
python3 app/scripts/samples/repair-japan-sample-timetables.py
python3 app/scripts/samples/repair-japan-sample-timetables.py --check
node app/scripts/validation/audit-japan-sample-branding.mjs
```

`--check` validates all 256 canonical/full/manifest/part copies, exact six reviewed passenger-call sequences, chronology including times above 24:00, every section operating number and the coverage ledger. The sidecars are `app/data/sample-timetable-reviews.json` and `app/data/sample-timetable-audit-20261001.json`.

If future repairs change routing inputs, solve only the affected ranges using `PRECOMPUTE_RANGE="start:end" node app/scripts/build/precompute-train-parts.mjs` (end exclusive), then `PRECOMPUTE_FINALIZE=1 node app/scripts/build/precompute-train-parts.mjs`. Current affected indices are 36, 140, 145, 148, 149 and 184; metadata-only synchronization here requires no geometry rebuild.

Port fixture maintenance uses `node app/scripts/build/build-port-fixtures.mjs --only=<fixture>.json`; append `--check` to verify an answer without writing it. Archive fixtures serialize real sample payloads, so metadata changes legitimately require refreshed answers followed by native parity tests. The builder now filters module filenames before import when `--only` is used: some modules do substantial work at import time, which previously caused every targeted check to construct unrelated fixtures. Full runs retain their existing behavior. All module basenames match their exported fixture names; an unknown fixture still returns failure, and an unchanged `coords.json` check passes (408 cases).

Regenerated and checked: `dates.json` (248 cases), `stats.json` (1,196), `validation.json` (157), `store-ops.json` (222), `station-display.json` (19,081), and `route-graph.json` (7). `import.json` remains unchanged and checks successfully (66); the regenerated `playback.json` answer remains byte-identical (7). Semantic diffs are limited to the reviewed facts: dates/stats contain 40 times and two stop classifications; validation/store exports carry the new section numbers, corrected display numbers and Sunrise note; station-display renders the two 大杉 passenger calls with stop rings/centers; route-graph changes only section-number and display-number inputs, with all cache keys/digests, topology and geometry answers unchanged. All six precomputed part route objects match their pre-repair objects.

## Complete sample field alignment with the Japan database

The field audit now covers all **292 rides in nine stores across seven regions**: Japan 256 (201 regular, 39 New Year, 16 Tokyo), Taiwan 28, Hong Kong 1, Macao 1, Korea 1, United States 2 and Canada 3. Every ride has an explicit `region`. **101 `number_en` fields** come directly from existing bilingual service labels, using the application's `splitLegacyServiceCaption` after normalizing fullwidth parentheses. The existing `number` captions remain intact. These translations are sample metadata, not new historical timetable evidence.

The Japan-only limited-express database is opened read-only. All 36 foreign rides are excluded from timetable matching, and 213 Japanese rides are outside limited-express scope. Of the 43 Japanese limited-express/sleeper rides, 26 have no matching database brand/public-number trip and 17 have candidate trip identities but no unique date-valid match covering the ordered ridden endpoints. **Zero sample rides can safely receive additional historical timetable fields from the current database.** Existing six manually reviewed services and their 45 passenger calls retain the verification described above; those six do not acquire a false database linkage.

`app/data/sample-timetable-field-audit.json` records every ride's status, candidate trip IDs, source of the English field, missing supported fields and generated-copy status, along with the exact database SHA-256. `number_en` remains unknown for 191 rides; `vehicle_type` remains unknown for 290 (Sonic 54 and Kodama 970 preserve the existing captions’ explicit 885系 and 500系 facts); 84 directions and 290 notes remain unspecified. Company and train type are present for every ride. Unknown platform numbers and actual arrival/departure observations stay unknown; published planned times are not copied into actual-operation fields. The ledger also records missing section operating numbers. Missing arrival/departure values at ridden boundaries and passing stations are often deliberate, so their counts are not evidence of defective timetables.

The audit requires both timetable-version validity and operation calendars, including dated add/remove exceptions and a verified holiday year when applicable. Operating numbers alone cannot identify a service; public service numbers and operating numbers remain separate. The matcher never substitutes September evidence for a July, May or New Year ride. Its enrichment path copies only exact/minute passenger-call times, keeps service-day times above 24:00, accepts only numeric platforms compatible with `platform_number`, and preserves off-ride boundary times and route sections. Dated direction and vehicle-series fields require explicit database facts.

Generated Taiwan/Hong Kong/Macao station IDs legitimately differ from canonical input IDs after regional station normalization. The alignment preserves these resolved identifiers and cached route objects, verifies exact generated full/part parity, and compares non-routing metadata with the canonical stores. US/Canada precompute commands now use their own country packages and stores.

```sh
python3 app/scripts/samples/align-sample-timetable-fields.py
python3 app/scripts/samples/align-sample-timetable-fields.py --check
python3 -m unittest discover app/scripts/samples/tests -v
python3 app/scripts/samples/repair-japan-sample-timetables.py --check
```

The ten targeted tests cover public-number identity, digit boundaries, version/calendar exceptions, unverified holiday calendars, overnight seconds, ordered/ambiguous endpoints, ride-boundary and platform enrichment, the seven-region inventory, and shared-caption English extraction and vehicle captions versus route-system numbers. Full precomputation is performed separately to regenerate source attestations and corresponding sample geometry from the current source packages.

The scoped US Acela regeneration uses current package/station identities for New Haven and Back Bay, keeping Empire Builder intact. Canada retains its two archival Canadian/Québec corridor examples with explicit current-coverage gaps: their old VIA routes are absent from the current package, and 72 referenced station IDs are unavailable. A third, undated Ottawa–Montréal route example uses the current surveyed package and exact station IDs; it explicitly claims no verified train running number, timetable or vehicle assignment. Its notes are preserved by the existing North America sample generator.

All nine complete precompute datasets were regenerated against the current source bytes and published atomically. The 292 parts contain 290 solved routes and two explicitly unavailable archival Canada routes; no record lacks a route result. Region counts are Japan 201/201, Taiwan 28/28, Hong Kong/Macao/Korea 1/1 each, United States 2/2, Canada 1/3, New Year 39/39 and Tokyo 16/16 (solved/total). The alignment `--check` also verifies every manifest/part content attestation against the current package, station, section, matched-input and optional history bytes. Metadata, passenger-call fields and section operating numbers match canonical/full/part copies while deliberate regional station-ID normalization remains intact. The standard `precompute:us`, `precompute:ca` and two special-loop npm commands now work directly from their maintained canonical stores.

## Native resource freshness and final validation

Every iOS build copies the seven canonical country packages, station/section/reading/history resources and all nine sample stores/datasets. Removed optional resources are pruned. The build verifies the normalized timetable's source snapshot, rebuilds a stale artifact, and snapshots the canonical SQLite database into the main app bundle with SQLite backup, including committed WAL transactions. Main-bundle timetable data takes precedence over the Swift-package fallback. The final bundle contains the current 882 trips and 8,520 stop times; its logical SQLite contents match the canonical database and its integrity check passes.

The generated `rail-resource-revisions.json` fingerprints each country's shipped resources. Persistent native route caches require the current revision; cross-border US/Canada caches require both countries' revisions. Native sample precomputes require matching package/station/section/matched-input/history hashes. Finalization also rejects parts whose train payload no longer matches the source store. All seven regions use the same loading and validation paths, and new installations expose all seven by default while respecting an existing explicit North America visibility preference. Timetable lookup, draft application and English timetable-name enrichment accept Japan only; foreign station identifiers cannot bypass that restriction by claiming a Japanese region.

Final validation passed: the iOS simulator build; all 154 JavaScript tests; 49 focused native timetable, country-scope, resource-revision, sample-provenance and English-name tests; 48 native import/storage/validation/route-graph/section-solve parity tests; seven resource snapshot/revision tests; and both sample alignment checks. The affected `validation.json` and `route-section-solve.json` fixtures were refreshed from current JavaScript answers. The final app bundle's resource manifest was recomputed independently and matched. These checks validate the repository's current sources; they do not imply complete historical timetable coverage or an automatic online data feed.
