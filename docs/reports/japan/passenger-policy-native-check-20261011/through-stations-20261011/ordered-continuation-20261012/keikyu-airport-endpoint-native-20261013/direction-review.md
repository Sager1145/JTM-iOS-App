# Keikyu Airport Line direction review

Reviewed 2026-10-13 against the current compact package, the physical-topology registry, the through-service catalog, and current official Keikyu service material. This is a direction/topology finding; it does not certify surveyed track or underground platform accuracy.

## Finding

**No false reversal was found at Keikyu Kamata.** `jp-京浜急行電鉄-空港線` is ordered Keikyu Kamata (`004331`) to Haneda Airport Terminal 1·2 (`004368`). Its first interval leaves Keikyu Kamata on a 209.5° bearing, retraces four vertices of Main Line interval 37 in the opposite stored direction for about 151 m, and then bends southeast toward Kojiya. The line itself has one continuous Kamata-to-airport direction and no internal U-turn.

The shared approach has two operational readings:

- From the Shinagawa/Asakusa side, the incoming Main Line tangent is 209.9° and the Airport Line exit is 209.5° (about 0.4° deflection). The current through-service catalog explicitly orders Main Line `004042`→`004331`, then Airport Line `004331`→`004368`; current official Keikyu timetable material also shows a Narita/Asakusa/Shinagawa train continuing through Keikyu Kamata to Haneda. This is a train-passable continuation, not a reversal.
- From the Yokohama side, the Main Line approach is 29.5° and the Airport Line exit is 209.5° (about 180°). That sharp reversal is operationally real: Keikyu's own *Nagisa* no. 633 explains that Yokohama-origin airport trains change direction at Keikyu Kamata, and current official Keikyu timetable material shows a Zushi/Yokohama-origin train continuing through Keikyu Kamata to Haneda. The compact geometry therefore must not be "smoothed" into a fictitious west-to-east bypass.

The topology registry keeps the cross-identity Main Line/Airport Line relationship conservative: candidate 132 reports five shared source vertices and remains `requires-independent-physical-evidence`; there is no approved Main–Airport entry in `physical-rail-junctions.json`. A shared station code or shared display vertices alone must not be promoted to a generic physical junction. The ordered through-service records and the official direction-change evidence are the bounded legal route evidence for the two service directions.

## Terminal display observation

The Main terminal pair places the Terminal 1·2 dot near the east end of the diagonal station box rather than its longitudinal centre. Treat that as a separate own-frame endpoint-placement defect. The z18 extraction is `partial_image_support`; both detected platform-midpoint candidates are unresolved and report no supported parallel rail at their midpoint. This review does not accept a replacement coordinate and does not use platform cartography to certify underground rail precision.

## Inputs

- `app/public/rail/jp-2025.json`: Airport intervals 0–5; Main intervals 37–38.
- `app/data/physical-rail-topology.json`: Japan candidate 132.
- `app/data/physical-rail-junctions.json`: no reviewed Main–Airport junction.
- `ios/RailKit/Sources/RailCore/Resources/japan-through-services.json`: north-side Main→Airport ordered patterns.
- [Keikyu *Nagisa* no. 633](https://www.keikyu.co.jp/visit/magazine/pdf/nagisa633.pdf): the Yokohama-side direction change at Keikyu Kamata.
- [Official Keikyu Zushi/Yokohama→Haneda timetable](https://norikae.keikyu.co.jp/transit/norikae/T7?d=2&date=&dw=0&sf=1711&slCode=253-2&tm=1450&tx=840100-2988-1402D) and [official Keikyu Narita/Shinagawa→Haneda timetable](https://norikae.keikyu.co.jp/transit/norikae/T7?d=1&dw=0&sf=2417&slCode=250-0&tm=1521&tx=820100-2695-1402K).
- `terminal-z18-before/apple-map-extraction/analysis.json` and the saved Main terminal overlay/basemap pair in this scope.
