Parent adjudication: the proposed direct West restaging loss is a sequencing limitation, not a confirmed defect. The driver applies explicit Haruka/Thunderbird enrichment overlays after base imports. See main rejected-suggestion section and normalizers-2 evidence.

# Normalizers 1 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## Concrete dependency defect

### P2 — West restaging replaces enriched formation records with their older partial seed

Anchor [ios/tools/normalize-reviewed-west-haruka45-52-thunderbird47-50-20260930.py:113](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-west-haruka45-52-thunderbird47-50-20260930.py:113) (output ownership151; write157). The formation constructor emits only date/planned/all_reserved/green/source/notes, then replaces the entire owning JSONL. The current same-owned artifact has independently sourced planned `car_count:9` for Haruka45 and `car_count:9, reserved_seat_capacity:546` for Thunderbird47. Retained `fact-sources-west-haruka-planned-nine-car-20260930.jsonl` attests Haruka45 via `jr-west-haruka-current-nine-car-guide-20260930` and `jr-west-2024-haruka-all-nine-car-policy`; `fact-sources-west-thunderbird-planned-nine-car-20260930.jsonl` attests Thunderbird47 count and capacity via `jr-west-thunderbird-current-nine-car-guide-20260930`. These are separate inputs and are untouched by the builder.

Running this normalizer against the current repository would deterministically remove the two planned fields from its output while leaving their field-level evidence in the repository. Existing source-pinned test [ios/tools/tests/test_west_haruka45_52_thunderbird47_50_20260930_source_pinned.py:81](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/tests/test_west_haruka45_52_thunderbird47_50_20260930_source_pinned.py:81) requires car_count9 and84 requires Thunderbird546, so the regenerated output contradicts its current caller contract. No builder or test was executed; conclusion is from the complete constructor and targeted current-row/evidence inspection. Similar generic West constructors recur in85–89 and94–95.

If this is intentionally a historical first-stage importer requiring later enrichment, make that lifecycle explicit and retain a separate composable formation overlay rather than overwriting the enriched record, or provide the supported focused restaging path that preserves/restores the separately attested fields. Do not infer actual dispatch or actual-day capacity from planned values. This finding is the deterministic loss on direct restaging; it does not claim current shipped values are wrong.

No other concrete production defect was confirmed in the97-file tranche. Discarded suspicions: Hida1 unscoped name lookup currently matches all12 explicit source-code pins; Sonic58/60/101/102/201/202 current tails contain no post-midnight clocks; Kuroshio10–13/19–22 candidates match their pinned women-seat labels. These were targeted data reads only.

Read-only inspection does not establish runtime pass, source publication truth, geometric accuracy, pixels, leaks or measured performance. The separate95-file Python report records the confirmed count assertion defect and bounded oracle-quality gaps.
