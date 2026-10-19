# IR Kanazawa #3: native ruler and southern boundary audit

2026-10-18. Read-only own-line data calculation and dependency review. No production/code edits, hashes, test commands, build, app/native or capture. This supersedes the proposed5..22 window in kanazawa-own-source.md; that old proposal is frozen as kanazawa-candidate-fragment-5-22.json. Current kanazawa-candidate-fragment.json is revised5..26, still an unrendered proposal.

## Native owner and ruler

Current display-lanes.json owns exactly one IR part: [lineID,0,-1,-1,604,64389,"station-approach/groomed",coordinates,[]]. Its604 coordinates exactly equal current rail-network.js displayPartsForLine(line)[0]; current calculated equirectangular length64388.984397m rounds64389.0m. Decoded interval3 starts at native127. Revised decoded5..26 maps to native132..153 inclusive. Exact frozen old native row and own metadata are in kanazawa-native-seam-audit.json.

The revised22→29 control replacement gives611 native coordinates, total64387.933726m→64387.9m. Direct splice of only that native window equals the recalculated web part exactly, including all existing station grooming outside it. This is an in-memory calculation using the existing display function, not native runtime or pixel evidence. Physical compact row, stored intervalkm2.59, station IDs/anchors, other intervals and other lines stay unchanged.

There is also an existing own lane row [lineID,0,0,64389,0.5]. Its end measure must become64387.9, retaining lane0.5 and origin0. Updating only partsByRegion would leave a stale lane ruler. No own follows, family windows, loop/reversed-loop, released interval, color/render-group override, stroke exclusion, hub-report member or chain-boundary record was found. The shared-corridors, jp-render-groups, display-chain-boundaries and display-hubs source files have no own line reference. Slot8 withheld spans remain[]. No shared/trunk owner is implicated.

The existing Python chain_from_embedded_coordinates uses this fallback row's exact vertices and recomputes its own native ruler; Swift consumes the derived chain's laneRows/totalMetres. A later scoped native export must therefore read both revised package and lanes, rather than reuse old IR bundle geometry. No export is performed here.

Package mutation also changes the established input references in station-english-verified-jp-east.json, jp-kana-evidence.json, station-english.json and station-names-coverage.json. The existing refreshDependencyReferences helper already updates those exact references in order; no station-name payload or new reference scheme is needed. No dependency hashes were computed during this audit.

## Why the previous southern join is revised

Both old boundary22 and retained guard23 are offset from the SAME explicit own834273931→394894111 chain (14.94m and15.83m). Controls24..28 remain15.81,18.39,16.83,14.79,19.60m away. There is no exact rejoining source coordinate in this range. Controls29/30 project to the chain's finite southern end with38.46/162.13m distances, so those values are endpoint shortfall, not cross-track error; extending through the station would need more own track/platform evidence.

The old5..22 proposal ended on selected track then crossed back to a generalized N02 path over69.64m, adding13.73° at projected22 and11.94° at retained23, where raw23 previously turned only0.45°. Thus14.94m was not sufficient justification and no<15m acceptance rule applies.

Retaining23 as a boundary is worse: its following N02 edge23→24 is only5.58m, causing a16.95m lateral diagonal with70.79°/63.06° turns. Ending20 similarly creates57.66°/61.46° turns. These short-edge options are rejected.

The revised boundary26 uses the same own chain through the bridge/approach curve, projected to [136.6505481689217,36.58145972267588] on the source segment [136.6506586,36.581561]→[136.6497164,36.5806969]. It retains raw27 [136.64981,36.58058] and all later supports. It returns to the generalized source over118.09m versus the old117.16m edge, with7.23° at projected26 and4.32° at retained27. This is the smallest maximum heading change among the bounded20..28 candidate endpoints checked; it avoids the short lateral leg and stops before the platform fan. The result has maximum7.23° across the whole interval, compared with the old37.51° V. The old entire native part shortens only1.05m.

This is a **schematic transition between two references in the same confirmed conventional corridor**, not a claimed physical turnout, surveyed seam or paired-track centre. Its justification is explicit own source identity, a long longitudinal join, preserved station approach and improved turn continuity—not an offset cutoff. The exact evidence gap remains if policy demands a physical coalescing seam: none has been identified. A candidate rendering must verify the northeast join, body, southwest transition and station approach before accepting this display policy.

## Source and visual dependencies

No new OSM query or different rail was selected. The same versioned own chain, exact shared node, relation4669038 memberships and official conventional1–7/Shinkansen11–14 distinction from kanazawa-own-source.md apply. No averaging is used. North boundary5 remains the existing repo-geo projection (3.67m offset) with raw4 retained; southern boundary now has16.83m offset, deliberately not selected for being under15m.

Reopened ORIGINAL000011/000006 smooth.png and basemap.png with functions.view_image. They show the red generalized line and separate conventional/Shinkansen bands through the proposed southern transition; broad railway shading cannot certify a precise track midpoint. Previous original000011/000003,000004,000007 reviews remain applicable to identity/current defect. No proposed pixels have been rendered or accepted.
