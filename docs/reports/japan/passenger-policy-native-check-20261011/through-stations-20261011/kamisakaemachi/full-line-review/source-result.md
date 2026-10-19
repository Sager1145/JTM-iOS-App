# Kamisakaemachi bounded display repair: source result

Applied2026-10-12. `repair-keishin-kamisakaemachi-display.mjs` owns an outer composed stage over the existing strict Otani curve repair. Frozen identified rail/node evidence, exact pre-station line/native rows, measured-reference dependencies and transition parameters live in `keishin-kamisakaemachi-display-evidence.json`.

Station005987 display alias is exactly `[135.8601033764409,35.005199183147624]`,8.182m west/north of the unchanged physical seed. Root's actual GSI rail grade and positive parallel passenger identity support the corridor correction; no platform-centre or Apple-POI snap claim. Independent side platforms remain staggered in the evidence.

Frozen actual decoded boundaries are incoming#4 index28 `[135.86004,35.00486]` and outgoing#5 index2 `[135.86048,35.00564]`. My initial research note numbered incoming raw supports one too high; proposal/report indices are corrected. The accepted bounds follow root's actual index28/index2 instruction. Incoming boundary projects4.483m from the identified paired mean; outgoing3.279m. Twenty-metre quintic displacement tapers follow that same passenger mean within the original approximately38m/58m windows, ending in one-metre guards collinear with retained outside rays. Neither perpendicular connectors nor global smoothing changes are used.

Display overrides now contain55/47 points. Physical station rows, segments, distances, prior Otani interval4 supports before the selected boundary, unrelated lines and native/reference data remain unchanged. Only one Keishin cached display part and established package-input dependency references were refreshed using a fresh exact-snapshot guarded apply. Source reads confirm current street-way taxonomy changed tram→rail after the retained cache, while embedded=pavement, coordinates and exact paired continuation nodes are unchanged; guards use the current pinned primary metadata.

Focused `node --test app/scripts/railway/tests/keishin-kamisakaemachi-display.test.mjs`: **5/5 pass**. Initial RED failed on the absent shipped station alias before implementation/apply. Regressions cover shared station/approach endpoints, strict earlier-stage replay, physical/outside/native/measured preservation, rejection of changed source identity/dependencies, and prevention of artificial perpendicular seam corners. Retained raw seam turn is below0.001°. Actual production `rail-stroke.js` worst turn within25m of each retained seam:

| Boundary | 1pixel/metre | 4pixels/metre |
|---|---|---|
| Incoming#4 | 8.372° | 5.609° |
| Outgoing#5 | 5.965° | 4.996° |

A focused in-memory replay of the current package, current native cached parts and all existing shared package dependency references reproduces them exactly unchanged. JS and Swift already consume both display station aliases and interval overrides; no counterpart code changes required. No native/UI operation, build, Swift resource copy or commit was performed here. Root owns combined resource regeneration and native acceptance.
