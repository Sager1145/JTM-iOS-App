# Keiyo-3 west-arm fork support proposal

Status: proposed, not integrated or accepted. Read-only research under current verification policy; no production changes/tests/build/native launch/capture.

Exact N02 feature14126 ends at[139.95631,35.69447]; feature14147 returns south via[139.95623,35.69376] and continues southwest to[139.95346,35.68953]. This confirms that the named own branch leaves to the west/south instead of following the east Minami-Funabashi arm. JR East train445E independently establishes Nishi-Funabashi to Ichikawa-Shiohama to Tokyo service.

Live OSM relation14656632 explicitly orders departure ways229030139,180845372,180845377,180845376 on Fuchu-Honmachi to Tokyo; reverse service14656631 uses the parallel west-arm chain. Competing east ways180845369 and229030138 belong explicit Minami-Funabashi relations14656663/64. Thus the selected track was identified by route membership and exact source connectivity, not nearest-rail selection.

The proposed display-only fragment replaces current controls22..34 with the bounded own southbound track slice and explicit projected boundary witnesses (6.93m and0.78m). It removes the12.33m eastward deviation of current control29 from that selected own directional track. These distances describe source geometry, not measured Apple pixel residuals. This one-track support proposal remains pending correct representative-centre and transition review in native/Main. The lower physical fork at display39 and shared trunk interval8 lie outside this window; no alias/station/physical/mileage/date/topology change is proposed.

Original pixels actually reviewed: `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/004531/000004/smooth.png` and same-directory `basemap.png`; own `view.json` identifies immutable camera.

Sources: [JR East Chiba passenger-network notice, page2](https://www.jreast.co.jp/chiba/news/pdf/pre1508_netrains.pdf); [JR East own Oct2026 train](https://timetables.jreast.co.jp/2610/train/130/134601.html); [explicit OSM route](https://www.openstreetmap.org/relation/14656632). See own-source-fragments.json for exact source records, version/timestamp/ordered memberships and cached source way geometry.

No detailed primary engineering track diagram was located in the bounded search. The JR PDF is a schematic network map and timetable proves passenger direction; the exact branch track geometry is supported separately by named MLIT features, explicit OSM membership and retained original native pixels. Do not promote the schematic to engineering geometry proof.

Next integration: preserve the candidate; update the earliest owning replay/evidence only after parent review, retain unsupported spans, then inspect relevant complete intervals in designated native/Main window. Whole-line output and platform/production joins remain unmeasured.

## Source implementation staged (2026-10-18)

The authorized seven existing source/evidence/test files now contain the implementation. The new approach descriptor is inside the existing western tail evidence window, with exact own route14656632 member order, source-way records, raw N02 source fragments, and the existing repo geo projection witnesses. Start distance is6.926917297994057m; end distance is0.7751701360287496m. They describe geometry projection to the explicitly selected own passenger track, not Apple pixel error or a surveyed corridor centre.

One strict westernPassengerApproach helper in the existing Shio module derives the source slice and accepts only the frozen old/new interior between exact outer guards. The older tail builder normalizes its reconstructed and existing displays through that helper; Shio retained/reapply uses it on its incoming and frozen baseline upstream arrays. Historical Shio evidence is unchanged. The shared corridor evidence distinguishes canonical index39 from display index48, and midcurve uses the former only for raw N02 comparisons. Shared trunk8 and Shio station-tail coordinates remain outside the changed approach window. Attribution remains in the existing selectedDisplayEvidence reference, whose western record now contains this own passengerApproach source proof; no stage/status flag or new repair module was introduced.

Existing tests now cover explicit route/source membership, wrong east-arm and modified source rejection, strict unchanged outside guards, old-tail replay, canonical/display fork identity, unchanged shared trunk8/Shio station tails/Ebigawa+Minami line, and package/parts replay idempotence. Historical fixed western counts/rulers were adjusted for the bounded source-window delta. The tail-only fixture now strips the actual retained Minami/Shio stages before restoring historical display inputs, and its summary reports the upstream approach delta separately from the lower tail.

Parent's candidate-root CLI export, Ebigawa helper/evidence/provenance/policy, current production package/lanes and other-line fixes were preserved. This worker ran no tests, candidate CLI, build, app, native capture or production apply. A targeted JSON source query confirmed unchanged outer controls/tail and exact raw39/display48 lower-fork identity. Execution remains pending parent review.

Focused new regressions:

```sh
node --test --test-name-pattern='western passenger approach|western approach replay' app/scripts/railway/tests/keiyo-display-curves.test.mjs app/scripts/railway/tests/keiyo-shared-corridor.test.mjs
```

Existing broader Keiyo source regression files if needed after reviewing those results:

```sh
node --test app/scripts/railway/tests/keiyo-display-curves.test.mjs app/scripts/railway/tests/keiyo-shared-corridor.test.mjs
```

Existing single candidate integration/export (no apply):

```sh
node app/scripts/railway/repair-keiyo-midcurve.mjs --west --candidate-root /private/tmp/jtm-keiyo3-west-candidate-20261018
```

### Concise provenance follow-up

The existing keiyo-west-shared-corridor marker now explicitly records passengerApproach source attribution, own ordered way chain, route14656632, canonical window22..34, exact outer guards, canonical/display fork39/48 and the unsurveyed display-reference policy. repairWestPackage refreshes this marker on the existing --west integration path. Historical tail/Minami/Shio markers remain untouched; their replays preserve the western marker. The existing western approach replay regression pins these fields and already checks full package/parts idempotence. Only the midcurve builder and that test changed in this follow-up; geometry/CLI/projection/evidence did not. No execution by this worker.

Focused provenance/replay command: `node --test --test-name-pattern="western approach replay" app/scripts/railway/tests/keiyo-shared-corridor.test.mjs`.
