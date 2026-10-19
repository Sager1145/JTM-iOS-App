# Tokyo / Shinagawa bounded source review — 2026-10-11

This is a read-only source/data review. It does not establish native pixel
alignment, a visible rendering defect, or acceptance of either entire station.
The existing through-station README remains the sole checklist.

## Scope and retained evidence

Inputs were `app/public/rail/jp-2025.json`, `display-lanes.json`,
`jp-render-groups.json`, the existing Tokyo/Shinagawa provenance in
`app/public/rail/jp-2025.sources.md`, and their production builder/Swift
consumers. The scoped query selected package lines serving 東京 or 品川, plus
`jp-東日本旅客鉄道-大崎支線` and `jp-東日本旅客鉄道-大崎支線-p1`:
12 line records and 11 follow rows touching those records.

Every scoped follow resolved to existing source/canonical display parts and
stayed within both stored measure bounds. No overlapping tenant windows named
conflicting canonical owners. Explicit circle aliases retained matching
operator and display anchors. Adjacent overridden Sobu intervals retained
exact shared endpoints. These conclusions cover the inspected inputs only;
no nationwide query, test, build, native operation, or geometry edit was run.

## Tokyo independent terminal and platform groups

- `jp-東日本旅客鉄道-東北新幹線`, terminal interval **21**, ends on retained
  display support **[139.7676701, 35.681109]**. Its independent physical station
  centroid is unchanged. The old centroid barb and regenerated approach are
  documented in `repair-tokyo-platform-approaches.py` and
  `repair-shinagawa-display-lanes.mjs`.
- `jp-東海旅客鉄道-東海道新幹線`, terminal interval **15**, retains Tokyo
  **[139.768107, 35.681116]**. It is not joined to the Tohoku Shinkansen.
- Surface Tokyo `jp-東日本旅客鉄道-東海道線` and terminal interval **11** of
  `jp-東日本旅客鉄道-東北線-2` share reviewed anchor
  **[139.7671827, 35.6811274]**. Tohoku-2 names Tokaido as circle owner for
  station code **003766**.
- Underground Tokyo `jp-東日本旅客鉄道-総武線` and interval **0** of
  `jp-東日本旅客鉄道-総武線-3` share **[139.765379, 35.681726]**.
  Sobu-3 names Sobu as circle owner for **003766**.
- Keiyo Tokyo remains at **[139.765236, 35.677692]**; Marunouchi Tokyo at
  **[139.7648, 35.681935]**. Their separate locations are retained.

The older hub report/family descriptions are not proof that the independent
underground corridor shares a physical alignment with the surface railway.
No new cross-company, platform-layer, Shinkansen, Sobu, or Keiyo merge is
authorized by this review.

## Shinagawa retained independent passenger corridor

`jp-東日本旅客鉄道-総武線-3` retains the reviewed normal passenger-pair
display anchor for station **004095** at
**[139.73965305042694, 35.629035]**. The physical station remains
**[139.739427, 35.629035]**. There is no Shinagawa circle-owner alias to the
surface Tokaido line and no obsolete Sobu-to-Tokaido follow through that station.

The stored zero-offset station pin spans **6358.7–6958.7 m** on Sobu-3 part 0,
300 m either side of its representative anchor. Its two-sided approaches,
actual western curve and retained southern support survive. The provenance
and replay owners are `repair-tokyo-platform-approaches.py` and
`repair-shinagawa-display-lanes.mjs`. The existing JR platform map identifies
platforms 13–15 separately from 6–12; it is not a geographic measurement.

The two Osaki records retain reviewed follows to Sobu-3's shared southern tail:

| Tenant part 0 | Tenant measures, m | Sobu-3 part 0 measures, m |
| --- | --- | --- |
| `jp-東日本旅客鉄道-大崎支線` | 1659.926171711952–2530.2959981808012 | 9438.910697753388–10309.280524222238 |
| `jp-東日本旅客鉄道-大崎支線-p1` | 1635.485811822731–2513.9733767882385 | 9430.79295925673–10309.280524222238 |

The canonical family window is Sobu-3 **9430.79295925673–10309.280524222238 m**.
It does not collapse the independent northern Shinagawa platform approach.

## Native owner lifecycle: unobserved candidate, no proposed fix

`build-display-network.py` removes matching explicit circle aliases around
line 3369. Chunk `dependsOn` construction around line 3464 covers follows,
family ink and reviewed terminal joins; circle aliases are not directly added.
The reviewed terminal registry contains Oshiage/Shibuya pairs, not these Tokyo
pairs.

Normal Tokyo viewport requests co-load eligible aliases and owners in one
urgent batch. `RailNetworkStore.activateDisplayLines` publishes after batch
completion; current viewport entries are protected from byte-budget eviction.
`RailDisplayNetwork.closure` maintains the recorded dependency closure.
Consequently absence of a circle-owner dependency alone does not establish a
normal loading defect.

One source-derived eligibility difference was found: Tohoku's complete
visibility group is **574.295 km**, rank 1, giving native MapLibre minimum 3;
Tokaido's group is **121.409 km**, rank 1, giving minimum 4. `RailStyle` converts
MapLibre to app zoom by **+1**. Thus at normalized **visibility zoom 4–5**,
Tohoku-2 can qualify while Tokaido does not. A hypothetical retained Tohoku-2
terminal circle would have the terminal floor 4; the alias was removed during
building. `RailMapCoordinator` requires the owning line to be drawn before
admitting its station. Prefetch loading alone does not change that gate.

There is no separate global zoom-6/9 network-station cutoff. Terminal thresholds,
era, viewport, drawn-line membership, selection/layer state, name placement
and MapKit collision admission still apply. Other Tokyo terminal platforms
may remain, and their markers can legitimately declutter at this regional
scale. This is therefore an **unobserved conventional-platform annotation
candidate**, not a proven missing Tokyo dot, corridor break, or actionable
defect. A dependency-only change would not settle its drawing semantics.

Sobu and Sobu-3 both use **148.764 km**, rank 3, with the same native threshold;
no corresponding normal eligibility difference was established. No dependency
or renderer change is proposed without actual native evidence.
