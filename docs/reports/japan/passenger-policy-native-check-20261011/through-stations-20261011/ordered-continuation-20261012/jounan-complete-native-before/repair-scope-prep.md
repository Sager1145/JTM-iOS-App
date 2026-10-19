# Jōnan display repair scope preparation

Date: 2026-10-13  
Status: bounded read-only scope note. No geometry candidate, source edit, build, or new native capture is accepted here.

## Current representation and defect boundary

`jp-伊予鉄道-城南線` is one immutable 12-station/11-interval legal record. Its serialized west end is 本町一丁目 (`008756`) → 西堀端 (`008761`) → 南堀端 (`008768`). This ordering crosses different junction arms and must not be interpreted as an operational reverse move. Keep the source station IDs, interval order, route identities, and physical registry unchanged.

The compact display representation already separates the west arm from the through line:

- display part 0: three points, 52.2 m, junction `[132.75865,33.8403]` west to 西堀端 `[132.758085,33.8403]`, classification `complex`;
- display part 1: 73 points, 3581.7 m, 本町一丁目 south through the junction and east to 道後温泉, classification `station-approach/groomed`;
- display lane: `jp-伊予鉄道-城南線`, part 1, measures **250.0–3568.4 m**, offset **-0.5**. Preserve its direction and measure convention.

The saved west Main pair shows the broader cartographic issue: the Otemachi/Nishi horizontal stroke is about 15 m north of the Apple tram guide/frame band, and the north-south stem is about 6 m west. A future display repair therefore needs evidence for all legal records meeting the city-tram loop, rather than a one-interval reversal patch or a shared-dot snap.

## Complete related legal-record scope

The connected city-tram scope is **six legal line IDs, 29 intervals, 70 planned native viewpoints**. Station sequences below define every exact interval: interval `#n` joins sequence entries `n` and `n+1`.

| Legal line ID | Exact intervals | Station-ID sequence | Planned viewpoints |
|---|---:|---|---:|
| `jp-伊予鉄道-城南線` | `#0–#10` | `008756 → 008761 → 008768 → 008764 → 008755 → 008754 → 008753 → 008749 → 008742 → 008738 → 008732 → 008729` | 27: `2,3,3,2,2,3,2,2,3,3,2` |
| `jp-伊予鉄道-城北線` | `#0–#7` | `008736 → 008734 → 008733 → 008730 → 008726 → 008720 → 008719 → 008725 → 008739` | 19: `2,2,3,3,2,2,2,3` |
| `jp-伊予鉄道-大手町線` | `#0–#3` | `008761 → 008760 → 008758 → 008751 → 008739` | 10: `2,2,3,3` |
| `jp-伊予鉄道-本町線` | `#0–#3` | `008719 → 008727 → 008735 → 008748 → 008756` | 9: `2,2,2,3` |
| `jp-伊予鉄道-花園線` | `#0` | `008772 → 008768` | 3 |
| `jp-伊予鉄道-連絡線` | `#0` | `008736 → 008742` | 2 |

The existing Primary baseline covers all **11 Jōnan intervals / 27 viewpoints / 81 panels**, with zero capture failures. The other five related records remain **18 intervals / 43 viewpoints** pending in that plan. The saved Main full-line, west-junction, and Dōgo pairs supplement the Jōnan baseline but do not replace native coverage for the related records.

Why the entire six-line scope is required:

- Jōnan intervals `#0` and `#1` render both Jōnan display parts; nearby `#2` can also include both within a viewport. Intervals `#2–#10` depend on the same whole-line smoothing digest and part 1. A part or lane change invalidates all 11 interval receipts.
- 城北線, 大手町線, 本町線, 花園線, and 連絡線 each have one display part spanning their full legal record. Local endpoint edits still change that record's whole-line dependency, so its complete interval set is the bounded acceptance scope.
- The east loop closes through Jōnan `008742`, 連絡線 `008742→008736`, 城北線 `008736→008739`, and 大手町線 `008739→008761`. Reviewing only the west junction cannot prove loop continuity.

## Shared station IDs and guards

| Station ID | Name | Legal records | Scope implication |
|---|---|---|---|
| `008756` | 本町一丁目 | 城南線 index 0; 本町線 index 4 | Different junction arm from 西堀端; preserve the 2018 identity distinction and check Jōnan `#0` plus 本町線 `#3`. |
| `008761` | 西堀端 | 城南線 index 1; 大手町線 index 0 | West-arm stop shared by the two legal records; check Jōnan `#0/#1` and 大手町線 `#0`. |
| `008768` | 南堀端 | 城南線 index 2; 花園線 index 1 | South/east junction; check Jōnan `#1/#2` and 花園線 `#0`. |
| `008742` | 上一万 | 城南線 index 8; 連絡線 index 1 | East-loop/Dōgo branch junction; check Jōnan `#7/#8` and 連絡線 `#0`. |
| `008736` | 平和通一丁目 | 城北線 index 0; 連絡線 index 0 | East-loop join; check 城北線 `#0` and 連絡線 `#0`. |
| `008739` | 古町 | 城北線 index 8; 大手町線 index 4; 高浜線 index 2 | Loop join. 高浜線 is private rail, so keep its geometry immutable; if a global station coordinate/dot changes, add 高浜線 `#1/#2` as alias guards. |
| `008719` | 本町六丁目 | 城北線 index 6; 本町線 index 0 | Same ID has line-specific coordinates (`[132.75823,33.85346]` vs `[132.75884,33.85313]`); do not collapse the two stop faces to one coordinate. Check 城北線 `#5/#6` and 本町線 `#0`. |

`008772` 松山市駅 on 花園線 is distinct from private-rail `008773` 松山市. Do not merge them by name proximity.

## Display-lane and continuation dependencies

- `jp-伊予鉄道-城南線`: part 1 lane `250.0–3568.4 m`, offset `-0.5`.
- `jp-伊予鉄道-城北線`: part 0 lane `0–2728.6 m`, offset `+0.5`.
- `jp-伊予鉄道-大手町線`, `本町線`, `花園線`, and `連絡線`: no compact lane entry.
- `jp-伊予鉄道-高浜線`: part 0 lane `0–5311.2 m`, offset `-1`; this is an alias guard only unless its own evidence establishes a defect.
- No related 伊予鉄道 line ID appears in compact `follows`, family-window, loop, chain-boundary, or render-group references. The service catalog has coverage `unknown` and no trips for these lines, so it cannot authorize an operational continuation or turnback.
- Physical-topology candidates 城南↔大手町, 城南↔本町, 城南↔花園, and 城南↔連絡 all remain `requires-independent-physical-evidence`. No new cross-identity join is authorized.

## Evidence still needed before an owner candidate

Keep the existing `nishihoribata-z18-before` extraction and 2010 regional aerial as regional/identity evidence only. After the Airport work is accepted, acquire focused z18 raws for the west junction arms, 南堀端, 上一万, 平和通一丁目, 古町, and the two line-specific 本町六丁目 stop faces. A future candidate then needs the complete 29-interval native scope above in each Inspector plus Main focused/full-line guards. Do not infer surveyed tram precision from the regional aerial or force shared station IDs onto a single platform point.

## Input custody

- `app/public/rail/jp-2025.json`: `e10fb8d56fbda440f679d3fab798bdc09eeec03c6ae6db8835805a72330e6aaf`
- `app/public/rail/display-lanes.json`: `eaac1ab3e3592fc222f96ffc486009aa4fbbd127a8fbbf31c11a496a0a066771`
- `app/data/physical-rail-topology.json`: `9baedae7805d2855acbe34aca81d0bdcc3ea527391a84c07356b0a068d5406e3`
- baseline `report.json`: `5f9057484f52647473907defb0b5afa81296c928cf609066765c1e9eb19ffef0`
