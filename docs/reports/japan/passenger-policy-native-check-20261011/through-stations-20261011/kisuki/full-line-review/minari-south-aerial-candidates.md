# Minari and southern aerial candidate review — 2026-10-12

Read-only proposal based on the three new `regional-aerial/*-z18.png` images and their AX URLs, directly inspected with native original pairs `008050/000012`, `008036/000002`, `008042/000002` and `008042/000012`. No production source was changed for these candidates; no collection, build, UI or test operation was performed for this research.

## Izumo-Minari

The [Minari aerial](regional-aerial/izumo-minari-z18.png), centred35.196656,133.009867, distinguishes the rail grade from the riverside road and station building. The physical/source crosshair lies north of the rail grade. The native interval9 tail and interval10 beginning likewise show the red line north of the labelled Kisuki corridor. This supports a bounded southward display-approach proposal, while precise platform centre remains unmeasured.

The positively identified chain is **1132447256 reversed →24548956 forward →1132447258 reversed**, with exact common nodes266913452/266913455. Existing primary receipts/node sequences and tags are in [south-primary-track-identity.md](south-primary-track-identity.md) and [south-identified-leg-reference.geojson](south-identified-leg-reference.geojson).

Physical station005364 `[133.009867,35.196656]` projects onto station-way24548956 segment **12645331108→266913453** at **`[133.0097851711849,35.19655590704016]`**, distance **13.3851m**, using the existing production geometry helper's local equirectangular projection. Tagged station POI266913453 `[133.00992,35.1964823]` lies farther along the same way; its19.906m distance from the catalog seed does not make it a platform centre.

Conservative frozen boundaries: interval9 physical index109 `[133.00806,35.19881]` has a2.0812m projection `[133.00808288359283,35.19881080257575]`; interval10 index4 `[133.01089,35.19622]` has a13.241m projection `[133.01083469504653,35.19610979368334]`. These bound approximately301.12m incoming and104.98m outgoing physical approach. Quantitative records and exact projection node IDs are in [minari-station-approach-candidate.json](minari-station-approach-candidate.json). No replacement interval is applied or accepted.

A straight perpendicular projection-to-boundary connector can create a hard corner, as root observed at Minami-Daito. Any future repair must retain outside physical supports and use a bounded, same-leg tangent-preserving transition inside the selected approach. Do not apply the projection aliases as standalone short connectors. Native seam/marker review remains necessary. The Minari station aerial does not cover the wider Yunohara interval10/view2 disagreement; its source-to-identified-OSM difference remains approximately18–26m over the farther eastern supports.

## Yuki departure and north of Bingo-Ochiai

[Yuki south aerial](regional-aerial/yuki-south-z18.png) is centred35.038958,133.119919, interval16/view2. Snow reveals a diagonal grade/road context, but the precise railway centre and parallel roadside boundaries are not consistently distinct. The identified main passenger way1442622132 is only **4.5334m** from the physical camera point; its projection is `[133.11995822253084,35.03893316925836]` on its long sparse index30–31 support. Simply adopting this sparse OSM segment cannot be assumed to resolve the larger visible Apple/source curve disagreement. No replacement curve or station move is proposed.

[Bingo-Ochiai north aerial](regional-aerial/bingo-ochiai-north-z18.png) is centred35.011569,133.129644, interval16/view12, several kilometres north of Bingo-Ochiai station. It shows a curving grade and adjoining road in heavy forest shadow. The physical/source crosshair appears separate from that visible grade, but exact rails and river/bridge boundaries need localized interpretation; the screenshot is not a station-platform reference. Identified way1364934495 projects the camera point only **4.8231m** to `[133.12960285516186,35.011541860230686]`. This same-source nearby projection is insufficient to recover the visibly displaced curve. Preserve the recorded bridge node graph and real reverse curves; do not force a nearest-grade or road snap.

All three AX records show seamlessphoto capture period `---`. OSM retains KSJ2 ancestry; dates of OSM object edits do not establish fresh tracing or ground survey. Aerial grade identification, primary passenger graph identity and Apple depiction differences remain distinct evidence. Root owns the implementation decision and native acceptance.
