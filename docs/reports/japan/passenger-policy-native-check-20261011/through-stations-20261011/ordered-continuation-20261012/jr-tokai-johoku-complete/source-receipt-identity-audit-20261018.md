# JR Tokai Johoku source and receipt audit — 2026-10-18

The current own line is `jp-JR東海交通事業-城北線`, six stations and five intervals, Biwajima → Kachigawa. All **40 legacy viewpoints already have their original basemap/smooth PNGs** (7/9/8/9/7 views). The old risk ledger showing 40 pending captures is stale: the later 2026-10-11 batch snapshot and actual files confirm their presence. No fresh capture is necessary for this bounded audit. The prepared `/private/tmp/jtm-johoku-request.json` was not run by this worker.

All current decoded own SOURCE controls exactly equal the 2026-10-11 `alignment-full-plan.json` source doubles, with current continuation flags decoded by retaining the preceding own station anchor. The legacy plan source equals its display for every interval. No line-specific display override or display station alias is present in the current line. This is exact input reuse context, not a claim that the historical rendering equals the current runtime.

| Own interval | Stations | Controls | Maximum local deflection | Legacy receipt directory | Views |
| --- | --- | --- | --- | --- | --- |
| #0 | 枇杷島 → 尾張星の宮 | 29 | 14.4664° at v21 `[136.85449, 35.21134]` | `000018` | 7 |
| #1 | 尾張星の宮 → 小田井 | 38 | 11.5323° at v15 `[136.85977, 35.21707]` | `000019` | 9 |
| #2 | 小田井 → 比良 | 20 | 5.0280° at v8 `[136.89878, 35.22806]` | `000020` | 8 |
| #3 | 比良 → 味美 | 22 | 4.1189° at v15 `[136.92852, 35.22974]` | `000021` | 9 |
| #4 | 味美 → 勝川 | 14 | 13.4955° at v9 `[136.94895, 35.22708]` | `000022` | 7 |

The current diagnostic feature uses a local deflection threshold of 20° (`DiagnosticRequest.swift`, `displayCorner`). The source-only calculation uses that same latitude-scaled angle definition: **no own vertex reaches 20°**. These numerical observations do not establish physical connectivity or alignment. No corner deletion or candidate geometry is supported by this metadata audit.

## Source and terminal identity

The registered N02-25 `app/data/rail-sections.json` own features are indices **11410–11423**, with both `N02_003=城北線` and `N02_004=JR東海交通事業`. Same-name Iyotetsu features 612–629 and their many “Johoku” repair reports are unrelated. The current package describes its base geometry as intervals cut from N02-25; this report does not elevate N02 to an independent track survey.

The current native parts row is `[["jp-JR東海交通事業-城北線", 0, 0, 4, 119, 11264.3, null, null, []]]`. No own byRegion/follows/family/hub-ruler entry was found in the targeted lane query. The five own physical lengths and continuation flags remain unchanged.

The own northern/eastern endpoint is **勝川 Kachigawa `005284` `[136.953335,35.228025]`**. JR Chuo Kachigawa is a distinct station `005280` `[136.95646,35.2299]`; its remote platform is not an authorized extension or replacement. At the opposite end, own **枇杷島 Biwajima `005349` `[136.861283,35.199601]`** shares a station ID with Tokaido, whose line-specific coordinate is `[136.861354,35.199653]`. Shared identity does not prove the same passenger face or authorize merging the two physical traces. Own 味美 Ajiyoshi `005282` is distinct from Meitetsu Komaki Ajiyoshi `005267` `[136.937185,35.235105]`. These distinctions are guards for pixel review; this audit does not independently establish platform caps.

## Legacy receipt bounds

Actual originals lie below `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000018` through `000022`, with every file path recorded in [the audit manifest](source-receipt-identity-audit-20261018.json). Timestamps span `2026-10-11T04:38:22Z` through `04:38:32Z`. Every receipt remains `pending`, `reviewFresh=false`; all have dependency `6caaeeb92631dd8c19c28c399b59f8511e03eebfad112b6c8d250eb5876962f5`.

The old renderer contract is `inspector-centreline-v5-preserve-small-survey-curves;fixed-z17-v2`, z17, 1024×768, isolated own centreline after whole-line smoothing and clipping. It excludes final lanes/follows/joins/family composition. Current new requests use specified capture settings and larger viewports, so the old pixels remain historical evidence with exact source identity, not fresh runtime proof or automatic whole-line acceptance. No pixels were viewed in this metadata audit; subsequent pixel inspection is recorded separately. No code/data/app/build/test/native operation was performed.
