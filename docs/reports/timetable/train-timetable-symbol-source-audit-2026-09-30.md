# Independent timetable symbol source audit — 2026-09-30

Scope: the selected Hokuto 1 / 1D, Hokuto 2 / 2D and Huis Ten Bosch 11 / 6011H columns only. This audit does not establish symbol coverage for other trains or prove physical routes.

A separate GPT-6.1 Sol audit checked the live official pages through the browser on 2026-09-30. The existing 16 normalized symbols matched. Eight printed `||` rows were missing from the two Hokuto columns. The corrected subset contains 24 symbols: 15 `レ` and 9 `||`. These rows remain separate from passenger calls and contain no invented clocks.

| Column and source | Selected-date evidence | Corrected independent rows |
|---|---|---|
| [Hokuto 1](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=150), source `jr-hokkaido-hokuto-suzuran-down-20260930` | 2026年9月30日(水), third train column 1D, October 2026 issue | 5 `レ`; 4 `||` after passenger sequence 8 (伊達紋別): 室蘭、母恋、御崎、輪西 |
| [Hokuto 2](https://jrhokkaidonorikae.com/vtime/vtime.php?d=20260930&s=151), source `jr-hokkaido-hokuto-suzuran-up-20260930` | Same selected date, first train column 2D, October 2026 issue | 10 `レ`; 4 `||` after passenger sequence 5 (東室蘭): 輪西、御崎、母恋、室蘭 |
| [Huis Ten Bosch 11](https://www.jrkyushu-timetable.jp/jr-k_time/2610/0008/00085801.html?c=28283&ym=202609&d=30), source `jr-kyushu-huis-ten-bosch11-20260930` | September 30 selected, right-hand 6011H column | Existing `||` at 佐世保, after passenger sequence 9 (早岐) |

On Hokuto 2, the existing 伊達紋別 and 洞爺 `レ` rows move from positions 0–1 to 4–5 within the same passenger-stop interval, after the four branch rows. This preserves the printed table order and does not turn those rows into an itinerary.

The web search tool returned an older September issue footer for one Hokkaido page. The live pages explicitly showed the October issue and selected September 30, consistent with the source registry. No issue correction was made based on the stale cache.

The reviewed candidates now retain the selected-date, column locator and exact symbol rows. Their normalizers regenerate both symbol JSONL files, so the rebuild no longer depends on manually retained symbol output. Python source-pinned and Swift runtime assertions check the branch-row order and passenger separation.

Source screenshots were inspected in browser tool output, but no original HTML/PDF/image is retained in the repository. URL and selected-column provenance remain available; source reproduction/processing permission remains unresolved in the existing registry. The independently observed facts do not resolve that source gap or the broader inventory/route-evidence gaps.
