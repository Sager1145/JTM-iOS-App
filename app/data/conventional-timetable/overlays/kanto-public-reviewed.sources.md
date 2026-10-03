# Kanto public timetable overlay

Reviewed 2026-10-03 UTC. This isolated overlay uses the `LineServiceCatalog` version 1 JSON contract and physical inventory version `2025.5.2`. It adds four short factual excerpts from JR East's public October 2026 train pages. No ODPT credential is required. Existing bundled resources, builders and Swift code were not changed.

## Exact reviewed service date

Every trip is restricted to **2026-10-02**. For each of the four source pages, the October 2026 operating calendar's day 2 cell was inspected in the HTML and explicitly carries `class="ok"`; day 3 carries `class="none"`. This establishes the selected date directly from the published per-train calendar. No recurrence or weekday/holiday calendar is generated. The accompanying text also identifies weekday operation. Class validity is conservatively the one-day half-open interval `[2026-10-02, 2026-10-03)`.

The four pages were individually opened through web browsing. A bounded read of those same public HTML pages verified the calendar cells because browser text extraction strips bold calendar formatting. No bulk timetable extraction or full timetable reproduction was performed.

## Timed facts and physical identity

| Official train page | Published type | Reviewed timed calls |
| --- | --- | --- |
| [995T Tokyo–Takao](https://timetables.jreast.co.jp/2610/train/155/155531.html) | 快速 | 新宿 09:44 arrival / 09:45 departure; 中野 09:48 / 09:49; 高円寺 09:51 / 09:51 |
| [967T Tokyo–Takao](https://timetables.jreast.co.jp/2610/train/105/109551.html) | 中央特快 | 新宿 09:48 / 09:48; 中野 09:53 / 09:54; 三鷹 10:04 / 10:05 |
| [1091T Tokyo–Ome](https://timetables.jreast.co.jp/2610/train/155/155641.html) | 青梅特快 | 新宿 10:33 / 10:36; 立川 11:04 / 11:04; 西立川 11:07 / 11:08 |
| [1541E Koganei–Shinagawa](https://timetables.jreast.co.jp/2610/train/065/069941.html) | 普通 | 上野 08:54 / 08:55; 東京 09:01 / 09:02; 新橋 09:05 / 09:06; 品川 arrival 09:12 |

Types and train numbers are explicitly labeled on the respective train pages. Public source train-page numbers are retained in the source URLs; local artifact IDs use the date and published train number. They are not ODPT identities.

All excerpt stops were matched by exact names within these exact physical package IDs, then stored using their inventory station codes:

- `jp-東日本旅客鉄道-中央線`: 新宿 `003700`, 中野 `003568`, 高円寺 `003573`, 三鷹 `003587`, 立川 `003634`.
- `jp-東日本旅客鉄道-青梅線`: 立川 `003634`, 西立川 `003581`.
- `jp-東日本旅客鉄道-東北線-2`: 上野 `003505`, 東京 `003766`.
- `jp-東日本旅客鉄道-東海道線`: 東京 `003766`, 新橋 `003872`, 品川 `004095`.

The single published 1091T stop list explicitly shows the Chuo–Ome continuation; the excerpt spans the exact shared 立川 identity. The single published 1541E stop list shows the Ueno–Tokyo–Shinagawa continuation; its excerpt spans the exact shared 東京 identity. This does not infer an interoperator continuation from shared stations. No previous/next train relationships are published on these sources, so every ODPT linkage and source-identity field remains null.

## Limits and verification

The JSON has four lines, six bounded class-evidence records and four trips, with three or four timed calls per trip. Arrival/departure minutes are converted directly to seconds from Japanese service-day midnight. Local Python checks confirm inventory identities and chronological times; compilation and importer integration were left to the parent task's gated batch.

The excerpts are partial. Omitted stops are unknown, never asserted non-stops; physical intermediate stations must not become passenger calls. No scheduled trip is synthesized from a generic route map, and no operating dates beyond the individually inspected October 2 cells are exported. Toei/Keikyu interoperator schedules were not guessed from separate station departure tables.
