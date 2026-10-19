# Keikyu airport terminal display candidate

The frozen z18 Apple basemap shows one long southwest–northeast blue station frame on the labelled Keikyu Kuko Line. Its reviewed longitudinal centreline runs from approximately pixel `[290,468]` to `[525,347]`; the arithmetic midpoint is `[407.5,407.5]`, georeferenced by the frozen 999×654 `mapRect` to `[139.78536347354134,35.54936765286402]`.

The two automatic platform candidates in `analysis.json` run northwest–southeast on the visible Tokyo Monorail structures. Both are unresolved with zero supported parallel rail pixels and are excluded. The extractor's 2% railway support is not used as midpoint authority.

The candidate preserves interval 5 source points 0…19 literally and replaces only the terminal point and station display alias `004368`. The incoming tail changes heading by about 4° and reaches the visible Keikyu frame midpoint without a hook. Physical station coordinates, IDs, kilometres, source segments, every other interval, and Main framing stay unchanged. This is an Apple cartographic display candidate, not surveyed platform geometry, and remains blocked from production pending complete native and Main review.
