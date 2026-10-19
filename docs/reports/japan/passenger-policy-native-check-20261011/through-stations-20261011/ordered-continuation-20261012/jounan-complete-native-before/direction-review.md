# Iyotetsu Jōnan Line west-junction direction review

Reviewed 2026-10-13 against the current compact package, its source rail identities, the physical-topology registry, the current official Iyotetsu tram map, Iyotetsu's 2018 stop-renaming notice, and the saved regional/Main evidence. This is a bounded identity and direction finding; it is not a geometry repair or acceptance.

## Finding

**The `#0`→`#1` reversal is a serialized junction-arm backtrack, not evidence of an operational turnback.** The compact station list orders 本町一丁目 (`008756`) → 西堀端 (`008761`) → 南堀端 (`008768`). Interval `#0` runs south from 本町一丁目 to the junction, then 52.2 m west to 西堀端. Interval `#1` restarts 27.2 m east of the 西堀端 dot, runs back east to the same junction, then south and east to 南堀端. The terminal bearing changes from 270° to 90°, so reading the two legal-line intervals as one train path creates a literal reverse U.

That reading conflicts with the identity evidence:

- Iyotetsu's 2018 notice says the former 本町線 stop named 西堀端 was in a different location from the loop-line 西堀端 stop and renamed it 本町一丁目. The two current station IDs and coordinates therefore represent distinct stop faces on different junction arms, not one interchangeable station point.
- The current official tram map keeps 本町一丁目 on the 本町 service arm and 西堀端 on the loop/JR Matsuyama arm. It does not establish 本町一丁目→西堀端→南堀端 as one ordered passenger continuation.
- The saved 2010 regional aerial shows a north–south rail continuation and a west-to-south curved continuation at the junction. It does not show a train reversing west and then east across 西堀端.

The current compact is best classified as a **station/line-inventory ordering problem at a multi-arm legal line record**. `008756` is also attached to `jp-伊予鉄道-本町線`, `008761` to `jp-伊予鉄道-大手町線`, and `008768` to `jp-伊予鉄道-花園線`. The physical-topology candidates for Jōnan–Hommachi, Jōnan–Otemachi, and Jōnan–Hanazono all remain `requires-independent-physical-evidence`, with no approved junction entry. Neither the shared legal identity nor the compact station sequence proves an operational turnback or authorizes a new cross-identity edge.

## Geometry status

The saved Main west-junction pair also shows a broader alignment issue: the horizontal Otemachi/Nishi source stroke is about 15 m north of the Apple tram guide/frame band, and the north–south stem is about 6 m west. Because this can affect several records in the legal city-tram group, it should not be treated as a local `#0`/`#1` reversal fix or solved by sharing the wrong station dot. No replacement coordinate, station reassignment, or display candidate is accepted here.

## Inputs

- `app/public/rail/jp-2025.json`: `jp-伊予鉄道-城南線` intervals 0–1 and the associated 本町線/大手町線/花園線 station records.
- `app/data/rail-sections.json`: the Jōnan, Hommachi, Otemachi, and Hanazono source identities around the junction.
- `app/data/physical-rail-topology.json` and `app/data/physical-rail-junctions.json`: unapproved candidates 157–159 and no reviewed junction.
- [Current official Iyotetsu tram route map](https://www.iyotetsu.co.jp/rosen/map/routemap/routemap_tram.pdf).
- [Iyotetsu 2018 stop-renaming notice](https://www.iyotetsu.co.jp/sp/topics/press/2018/0125_3day.pdf): the Hommachi Line stop formerly sharing the 西堀端 name was at a different location and became 本町一丁目.
- Saved `jounan-west-junction-main` overlay/basemap pair and the regional GSI aerial identified as April–May 2010 imagery in this review scope.
