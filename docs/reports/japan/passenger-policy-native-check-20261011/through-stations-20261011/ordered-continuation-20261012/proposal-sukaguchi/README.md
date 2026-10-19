# Sukaguchi complete three-interval display proposal

2026-10-13. Status: **proposal; root review and actual native replay required**.

This proposal replaces the display coordinates of complete Tsushima #0 and Main #17/#18. It retains all physical source records, mileage, interval IDs and routing edges. Nothing has been applied to production data or built/launched in a native app.

The proposed Sukaguchi alias is [136.84625120866804,35.198706437899155], corresponding to original pixel (592,378). Its complete narrow cartographic face evidence is recorded in `../sukaguchi-independent-identity/adjudication.{md,json}`. The station's transverse building masks the railway at the midpoint, and physical directional platform numbers remain unresolved. This is a cartographic normal-projection candidate, not physical switch or platform-number proof.

Main #17 approaches on the northwest Main glyph, rather than prematurely borrowing the west Tsushima branch. The exact shared display stem is three points: **Sukaguchi (592,378) → own black flank (555,351) → downstream common glyph (410,251)**. Main #17 uses precisely the reverse three. The canonical physical shared point formerly projecting to (306.56,201.53) is absent from the proposed shared display stem.

All four station aliases use the root-agreed exact coordinates:

| Station | Original capture pixel | Exact candidate coordinate |
| --- | --- | --- |
| Marunouchi 005337 | own-normal (471,231) | [136.84198711408624,35.204625793777495] |
| Sukaguchi 005352 | complete-face projection (592,378) | [136.84625120866804,35.198706437899155] |
| Shinkawabashi 005374 | own-normal (454,280) | [136.85237591897993,35.195456036607474] |
| Jimokuji 005368 | root-validated own-normal (490,315) | [136.82580403802893,35.19600760468442] |

## Files

- `candidate.json`: three complete coordinate arrays and the shared station aliases. Tsushima #0 has272 points; Main #17 has87; Main #18 has92.
- `candidate.geojson`: the same complete intervals for external-reference replay.
- `control-provenance.json`:223 original-pixel controls, their capture names, original RGB, camera-derived coordinates and fitting ownership. Alias and label/occlusion candidates are explicitly distinguished from observed own glyph pixels.
- `reprojection-manifest.json` and `reprojections/`:14 full original-view overlays, including all7 Tsushima #0 views,3 Main #17 views and4 Main #18 views. Same-camera station captures are retained individually; their cartography is not assumed identical. Orange is the candidate, cyan original supports and yellow station aliases.
- `focused-query-receipt.json`: finite coordinates, exact alias equality, exact reverse-shared three-point equality, candidate direction and edge queries.
- `build-proposal.py`: bounded, reproducible local proposal generator. It reads the existing raw captures and writes only this directory.

## Fitting and review limits

Manual corridor identity and label-exclusion bands precede any local pixel query. A column query selects the thin dark sleeper glyph near its established corridor; broad road/casing colours and light-blue letter-neighbouring text outlines are excluded. Piecewise shape-preserving Hermite interpolation joins the accepted supports through label gaps. No source vertex is inserted as a return guard. The shared three-point stem remains exact and reverse-equal.

The initial static overlay review exposed casing-edge picks at the river bend. Those were replaced with explicit thin-glyph pixels on the complete v2/v3 bend, including v2 (150,543),(200,514),(250,481),(400,380) and v3 (450,313),(500,306),(520,303),(530,301),(540,299),(680,261),(690,258),(750,233),(800,207),(850,175). The regenerated bend overlay follows the visible single sleeper glyph without the rejected step.

The focused array query finds a2.30° station continuation difference for reverse Main #18 → Tsushima #0 and for Main #17 → Main #18, rather than a reversal or45° connector. Maximum raw small-edge tangent changes are15.43° for Tsushima #0,15.31° for Main #17 and8.37° for Main #18. These include pixel discretization and closely spaced support transitions; they are recorded for root's native smoothing review, not asserted acceptable.

Static full-view overlays were inspected across the complete three-interval scope. Label gaps, antialiasing/sleeper width, the occluded Sukaguchi midpoint and the curved Shinkawabashi label gap remain evidence-bounded. Root must inspect the proposed arrays in all requested Inspector apps and actual Main, including final smoothing and station circles. No runtime, final native alignment, lane/follow behaviour or operational track-number acceptance is claimed here.
