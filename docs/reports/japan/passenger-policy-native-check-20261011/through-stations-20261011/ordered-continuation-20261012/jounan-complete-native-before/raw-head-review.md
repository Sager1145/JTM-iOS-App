# Jounan interval #2 raw head review

Scope: bounded read-only review of the three original z18 Apple basemaps and their exact `analysis.json` map rectangles:

- `jounan-interval2-view0-z18-before`
- `jounan-interval2-view1-z18-before`
- `jounan-interval2-view2-z18-before`

All three 1000 × 654 basemaps were opened at original resolution. Pixel controls below use the centre of the thin black rail glyph with visible ties. Road centres, moat curbs, route casing, labels, shields, and the east spur vertex were excluded. View 2 independently repeats View 1 with a map-rect reprojection of approximately −1.671 px x and +18.510 px y.

## Finding

The Jounan #2 V1 head is not supported by the black rail. The retained west station alias itself is on the rail at View 0 pixel `(490.500, 348.000)`, and the literal Hanazono/Jounan rail junction is `(600.745, 348.018)`, coordinate `[132.76179812, 33.83934635]`. V1 projects to about y=352.5 at that junction, 2.24 m south.

The mismatch then grows along the straight head: at View 1 x=100, 250, 400, and 450 the black rail is y=445, 447, 449, and 448, while V1 is approximately y=453.66, 459.82, 463.99, and 464.81. V1 then crosses the real curve: at black controls `(478,442)`, `(500,430)`, `(523,410)`, and `(538,380)`, V1 is approximately y=460.99, 439.80, 401.37, and 360.30. A constant translation cannot repair this.

## Literal control proposal

Keep the existing west alias and City Hall station representative exact. Between them, use the ordered black-glyph controls below. Coordinates are inverse projections of the listed View 1 pixels, except the exact retained endpoints and the Root-confirmed View 0 junction. The View 2 column is an independent reprojection check; each lands on the same tied black rail in that raw.

| Role | Evidence pixel | WGS84 coordinate | View 2 reprojection |
| --- | --- | --- | --- |
| retained west alias | V0 `(490.500,348.000)` | `[132.76120672,33.83934643]` | outside east views |
| literal branch junction | V0 `(600.745,348.018)` | `[132.76179812,33.83934635]` | just west of east views |
| straight head | V1 `(0,446)` | `[132.761936508,33.839337297]` | `(-1.671,464.510)` |
| straight head | V1 `(100,445)` | `[132.762472950,33.839341753]` | `(98.329,463.510)` |
| straight head | V1 `(250,447)` | `[132.763277613,33.839332841]` | `(248.329,465.510)` |
| straight head | V1 `(400,449)` | `[132.764082276,33.839323930]` | `(398.329,467.510)` |
| last straight / curve guard | V1 `(450,448)` | `[132.764350496,33.839328386]` | `(448.329,466.510)` |
| curve | V1 `(470,445)` | `[132.764457785,33.839341753]` | `(468.329,463.510)` |
| curve | V1 `(478,442)` | `[132.764500700,33.839355120]` | `(476.329,460.510)` |
| curve | V1 `(500,430)` | `[132.764618717,33.839408588]` | `(498.329,448.510)` |
| curve | V1 `(512,420)` | `[132.764683090,33.839453145]` | `(510.329,438.510)` |
| curve | V1 `(523,410)` | `[132.764742099,33.839497702]` | `(521.329,428.510)` |
| curve | V1 `(529,400)` | `[132.764774285,33.839542259]` | `(527.329,418.510)` |
| curve | V1 `(535,390)` | `[132.764806472,33.839586816]` | `(533.329,408.510)` |
| curve | V1 `(538,380)` | `[132.764822565,33.839631373]` | `(536.329,398.510)` |
| curve | V1 `(542,370)` | `[132.764844023,33.839675929]` | `(540.329,388.510)` |
| curve | V1 `(545,360)` | `[132.764860116,33.839720486]` | `(543.329,378.510)` |
| vertical approach | V1 `(546,345)` | `[132.764865481,33.839787321]` | `(544.329,363.510)` |
| retained City Hall anchor | V1 `(545.000,334.499)` | `[132.76486012,33.83983411]` | `(543.329,353.009)` |

The control sequence follows the tied black centreline rather than the moat curb. It should replace only Jounan #2's unsupported head/curve portion; the west alias, City Hall anchor, other 28 interval arrays, and other station aliases remain unchanged.

For the separate Hanazono continuity delta, the display-only lead-in should end at the literal junction `[132.76179812,33.83934635]`, not the rejected east spur vertex. The Hanazono station dot and interval endpoint remain on their own north-south face. This is compatible with `displayBranchLeadIns` as a separate display part and does not require changing the physical graph.

