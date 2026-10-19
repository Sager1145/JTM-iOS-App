# Native Apple Maps Transit junction review — 2026-10-15

Root operated the installed macOS Apple Maps application, confirmed **Transit selected** in Map Modes, and inspected the following actual rendered views. These are cartographic display observations, not proof of physical switches or a completed Main repair.

| Junction | Actual observation | Saved native pixels |
|---|---|---|
| Hiroshima Kamiyacho | One green Hiroden trunk across the east/west road; separate west→south and east→south curves. The two curves meet the southern corridor at different positions. The orange Astram Line is independent even where the drawn paths cross. Route badges have several colours while the underlying Hiroden corridor remains green. | `kamiyacho-overview.png`, `kamiyacho-junction-close.png`, `kamiyacho-junction-detail.png` |
| Hiroshima Dobashi | A continuous north/south green trunk, with a west→north curve. No west→south curve is drawn in the observed view. Do not manufacture a full triangle from three approaching arms. | `dobashi-overview.png`, `dobashi-junction-close.png` |
| Toyama Marunouchi | Routes 2/3/5/6 share one green/turquoise corridor. Apple uses a conspicuously simplified, angular junction at the north-side station position. This differs from Hiroshima: its exact corner geometry is not a universal smoothing template. | `marunouchi-overview.png`, `marunouchi-junction-close.png`, `marunouchi-junction-detail.png` |

## Consequences for Ujina work

1. Identify each legal incoming/outgoing pair independently. Station-list backtracking cannot define a train movement.
2. Preserve a through trunk plus separately evidenced turning curves. A single forced shared display point can distort both curves; use the actual cartographic merge positions.
3. Consolidate genuinely shared corridor drawing, retaining line/service identity, station groups and date filtering. Coloured service badges are not an instruction to offset and repaint the same tram track repeatedly.
4. Keep Astram independent. Nearest blue-rail pixel selection around Hondori/Kamiyacho is ambiguous without an own-Hiroden corridor mask.
5. Where the Apple cartography is simplified, use regional overhead evidence to establish the physical direction, and preserve real smooth curves instead of copying an artificial angular schematic.

Code review: `MapLineGeometry.continuousJoin` already handles same-line three-way endpoints, but sharing one endpoint is not evidence that all movements or one common switch point exist. `rail-network.js/displayPartsForLine` supports display-only branch lead-ins and preserves canonical intervals. Existing Ujina has three parts around one source junction; its new same-camera comparison shows both the south/east displacement and the east spur corner. A renderer-wide smoothing change is not justified by these observations.

`kamiyacho-inspector-standard-z19` is an exact-camera native same-view export (132.45765,34.39499,z19), selected owner Ujina. Its interval selection remained #4; it shows all three line parts in the viewport and provides junction evidence only, **not interval #4 coverage at this location**. Original data and Main have not been changed by this research step. Full candidate three-Inspector/Main acceptance remains pending.

Native Maps required one restart after its View menu left the automation handle bound to a stale menu. The restored window was used for every saved image above. No default map setting beyond the requested Transit mode was changed.

## Main baseline and repair proposal

The existing signed Main candidate (Toyama candidate name, current shipped renderer/resources) was launched at Kamiyacho with the isolated camera entry. Actual camera centre 34.394990,132.457650, zoom18.18,1024×768; no rides. `main-baseline-on.png`/`main-baseline-off.png` and AX record the real renderer’s displaced station dots, parallel/overlapping line representations and curved branch placement. Network was restored ON. This is baseline evidence, not post-fix acceptance.

`../root-candidate-v1/kamiyacho-own-corridor-proposal.json` and its GeoJSON/annotated overlay trace the own Hiroden west/east/south limbs separately from Astram and propose whole-frame aliases for the two Kamiyacho stops. It is explicitly a **partial-window control proposal**, with the through EW main-line context separately owned. No proposal coordinates have been written to production. Complete Ujina19intervals and affected Main-line neighbours, three-Inspector and Main checks, remain required before applying a repair.
