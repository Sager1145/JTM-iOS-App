# Normalizers 3 — full iOS audit evidence

Cumulative scope and parent-adjudicated priorities are in the [main audit](/Users/sager/Documents/GitHub/JTM-iOS-App/docs/reports/integration/full-ios-code-audit-2026-10-11.md). Local reviewer IDs refer to this evidence file only. Source review does not establish an executed pass.

## Method and boundaries

Read [ios/AGENTS.md](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/AGENTS.md), [ios/VERIFICATION.md](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/VERIFICATION.md), MattPocock TDD test-quality guidance and codebase-design guidance. Full templates were read first; sibling review used exact source mappings to those fully read templates, with every inserted, replaced and removed line reviewed, including every changed assertion, literal and control-flow variant. This was semantic reconstruction, not an AST/inventory review. Truncated early source output was reread in bounded sections before any affected file was marked full. Every file's identity, date bounds, station resolution, permissions, unknown versus planned versus actual facts, output ownership and rejection behavior were reviewed. Caller and materialization dependencies were read where needed. No normalizers, tests, builders, builds or full-tree hash workflows were executed. No production files were edited.

## Confirmed code-path findings

### P2 — Akagi validates English source only after overwriting its valid evidence files

[ios/tools/normalize-reviewed-akagi-20260930-seed.py:43–49](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-akagi-20260930-seed.py:43) calls the shared writer before checking `english_name_source.url_or_locator`. The shared [normalize-reviewed-east-next-batch-seeds.py:378–393](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-east-next-batch-seeds.py:378) overwrites the source registry and service-name-period files using only native trip sources/names. The wrapper appends the English source and name only at lines 51–59 after the check.

Concrete failing input: retain all accepted native timetable facts but change only the English URL. The shared normalization completes and replaces the existing Akagi English source/name rows; the wrapper then raises its explicit “Akagi English name source changed” error without restoring those rows. A rejected candidate thus removes previously valid English evidence. This is established by the writer/check order, not by an executed mutation. The independent behavior oracle is the wrapper's own rejection contract plus the previously existing canonical English source/name records; the happy-path Akagi tests check the resulting English name but do not cover this rejected-input state.

### P2 — Priority current-N02 rejection can leave completeness promoted without its route evidence

[ios/tools/normalize-reviewed-priority-current-n02-route-identities-20260930.py:291–306](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-priority-current-n02-route-identities-20260930.py:291) writes each matching completeness file before verifying that all required trips were found. It then modifies research queues at lines 308–328 and only afterwards writes the source, route and fact outputs at lines 343–345. Existing explicit queue rejection at lines 315–316 therefore also occurs after completeness writes.

Concrete failing input/state: one required route completeness row is absent, or one target research row has a non-open status. Other found rows are saved with `status=partial`, `confidence=high`, and “All passenger-pair legs have source-pinned current N02 identities,” then normalization raises before emitting the associated route/fact outputs. On an initial promotion this leaves canonical coverage claims ahead of the evidence output. The independent oracle is the script's explicitly required all-trip set and open-queue contract; those guards reject the state, yet earlier writes persist. No mutation was executed. Existing rerunnable happy-path coverage does not observe rejected-input output preservation.

## Bounded observations, not elevated defects

* Fuji Excursion 11's first three bundled stops have both clocks null but `time_accuracy=minute` ([normalize-reviewed-east-spacia-nikko1-fuji-excursion11-20260930.py:115](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/normalize-reviewed-east-spacia-nikko1-fuji-excursion11-20260930.py:115); bundled `normalized/stop-times/east-fuji-excursion11-20260930/seeds.jsonl:1–3`). The source's partial-timing note at lines 89–91 explicitly preserves unknown clocks. This is a metadata consistency observation. The SQL enum does not explicitly forbid minute accuracy with null clocks, and native physical-route matching additionally checks clock presence, so this review does not claim a schema violation or false route-clock proof.
* The Hokuto extension normalizer accepts an original last-verified date of September 20 without itself writing September 30. This is an orchestration dependency, not a regeneration defect: [rebuild-reviewed-train-timetable.py:376–404](/Users/sager/Documents/GitHub/JTM-iOS-App/ios/tools/rebuild-reviewed-train-timetable.py:376) recomputes service bounds from explicit valid calendar additions and `main:415` runs that refresh before build steps. The exact September 30 Hokuto additions satisfy that scope. Current bundled Hokuto service metadata already ends September 30.
* Source-publisher labels in some Fujikawa metadata do not match the source-host name, but URLs and pinned facts remain explicit; no product consequence was established.
* Reused normalizer EXPECTED/PINS/STOPS tables provide parity oracles; the complete preceding test report separately identifies concrete assertion weaknesses. Duplication alone is not reported as a defect.

## Completion evidence and limits

Both coverage JSONs were parsed and counted: Python tests 97/97 full; tools 98/98 full. This is source review evidence. Runtime, build, pixel, leak and performance claims were not measured. The two error-path findings describe deterministically reachable rejected-input writes; they do not claim the checked-in current candidates fail today.
