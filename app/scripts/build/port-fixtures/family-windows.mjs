// =========================================================================
//  family-windows.json — the derived family-window slicing rail-network.js
//  and railmap.js apply for a same-family follow (build-display-lanes.mjs
//  `deriveFamilyWindows`, na-render-groups.json render groups)
//
//  A family window exists wherever a follow row's follower and leader share
//  one na-render-groups.json render group: same corridor + same RenderKey is
//  ONE drawn lane (rules.md §2, §5, §9.5), but the family still keeps its
//  whole-railroad colour everywhere (LIRR is MTA blue everywhere; Metro-North
//  is MTA blue everywhere). The follower's window becomes a TENANT window
//  (its own stroke is not drawn there) and the leader's matching window
//  becomes a LANDLORD window (it draws the shared family stroke there, in
//  the group's colour, via its own `familyFeatureIndex` feature).
//
//  This fixture pins, for a handful of real converging corridors, exactly
//  which stretch of each named part is a tenant window, which is a landlord
//  window, and — reproducing the same partition rail-network.js/railmap.js
//  apply via the SHARED `RailStroke.familyPartition` (rail-stroke.js, and
//  RailCore's `ContinuousStroke.familyPartition` on iOS — answer-identical
//  to 1e-9 m, per that function's own doc) — exactly which pieces are
//  emitted, in measure order, and which colour each one draws in. The Swift
//  port's own parity test (`FamilyWindowParityTests`) calls that SAME
//  production function against `cases` below and is expected to land on the
//  same boundaries and the same colours.
//
//  `cases` mixes real corridors (named lines/parts from the built us
//  network) with synthetic probes (a placeholder lineId/partIndex, windows
//  chosen by hand) for edge shapes no real corridor in this package
//  currently exhibits. Every entry — real or synthetic — carries the exact
//  same required fields `FamilyWindowParityTests.Case` decodes
//  (label/lineId/partIndex/totalMetres/familyWindows/tenantWindows/
//  hasFamilyFeature/baseColor/familyColor/emittedPieces); anything beyond
//  that (`beadDecisions` on the bead case, `withheld`/`withheldPieces` on
//  the withheld case) is an ADDITIVE field Swift's `Decodable` conformance
//  simply does not declare and therefore ignores — see the doc on each case
//  below. The top-level `caFamilyWindows` field is additive the same way:
//  `Fixture` only decodes `cases`.
//
//  Cases are named real corridors where one exists, not synthetic geometry:
//  LIRR's Jamaica/Valley Stream/Port Jefferson throats, Metro-North's Park
//  Avenue trunk (Harlem Line landlord, Hudson Line tenant), MBTA's Green
//  Line central subway (D branch landlord, C branch tenant) and Southwest
//  Corridor commuter trunk (Providence/Stoughton landlord, Fairmount
//  tenant), Metrolink's LA Union Station approach, SFMTA's Market Street
//  throat, and — new this pass, now that na-render-groups.json's `byLineId`
//  finally names the NYCT subway trunk lines — the Lexington Ave Line
//  (nyct:green): the 5 (express) is landlord, the 4/6/6x (running the same
//  local track over long stretches) are tenants, giving both branches of
//  the bead rule a real corridor: a landlord bead present at a shared
//  express/local stop (125 St), and the fallback lowest-lineId pick where
//  no landlord calls (the Lexington Ave local-only stops, 116 St down to
//  Spring St).
// =========================================================================

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

export const name = "family-windows.json";

const require = createRequire(import.meta.url);

// Real corridors, read off the built us network below. `label` documents
// which member (landlord/tenant/pure-tenant) each entry is.
const REAL_CASES = [
  {
    lineId: "mta-long-island-rail-road-west-hempstead-branch",
    partIndex: 0,
    label: "LIRR Jamaica throat — West Hempstead Branch landlord window",
  },
  {
    lineId: "mta-long-island-rail-road-long-beach-branch",
    partIndex: 0,
    label: "LIRR Valley Stream throat — Long Beach Branch landlord window",
  },
  {
    lineId: "mta-long-island-rail-road-port-jefferson-branch",
    partIndex: 0,
    label: "LIRR Port Jefferson Branch landlord window",
  },
  {
    lineId: "metro-north-railroad-harlem",
    partIndex: 0,
    label: "Metro-North Park Avenue trunk — Harlem Line landlord window",
  },
  {
    lineId: "metro-north-railroad-hudson",
    partIndex: 0,
    label: "Metro-North Park Avenue trunk — Hudson Line tenant (pure tenant, no landlord window of its own)",
  },
  {
    lineId: "mbta-d",
    partIndex: 0,
    label: "MBTA Green Line central subway — D branch landlord window",
  },
  {
    lineId: "mbta-c",
    partIndex: 0,
    label: "MBTA Green Line central subway — C branch tenant (pure tenant)",
  },
  {
    lineId: "mbta-providence-stoughton-line",
    partIndex: 0,
    label: "MBTA Southwest Corridor — Providence/Stoughton Line landlord windows (3 stretches)",
  },
  {
    lineId: "mbta-fairmount-line",
    partIndex: 0,
    label: "MBTA Southwest Corridor throat — Fairmount Line tenant (pure tenant)",
  },
  {
    lineId: "metrolink-ie-oc-line",
    partIndex: 0,
    label: "Metrolink LA Union Station approach — IE-OC Line landlord windows (2 stretches)",
  },
  {
    lineId: "san-francisco-municipal-tran-f",
    partIndex: 0,
    label: "SFMTA Market Street throat — F Market & Wharves landlord windows (2 stretches, shared with the California St cable car)",
  },
  {
    lineId: "metropolitan-transit-authori-5",
    partIndex: 0,
    label: "NYCT Lexington Ave Line (nyct:green) — 5 (express) landlord window over the 4/6/6x shared local track",
  },
];

// jp's own real corridors — a route-preserving family pair (jp-render-
// groups.json "九州旅客鉄道:長崎線"): the base line is the landlord over its
// own `-2` branch-service split, which is a pure tenant with no landlord
// window of its own. Read off the built jp network, not the us one.
const JP_REAL_CASES = [
  {
    country: "jp",
    lineId: "jp-九州旅客鉄道-長崎線",
    partIndex: 0,
    label: "九州旅客鉄道 長崎線 — base line landlord window over its own -2 branch-service split (2 stretches)",
  },
  {
    country: "jp",
    lineId: "jp-九州旅客鉄道-長崎線-2",
    partIndex: 0,
    label: "九州旅客鉄道 長崎線-2 branch-service split — pure tenant (no landlord window of its own)",
  },
];

// Physical stations (stationGroupId) the express-landlord/local-tenant bead
// case records a decision for, exercising BOTH branches of the rule: a
// landlord bead present (125 St, where the 5 itself stops — every tenant of
// nyct:green there is suppressed) and the fallback (the Lexington Ave
// local-only stops, where the 5 does not call at all — exactly the
// lowest-lineId tenant, "…-6" over "…-6x", survives).
const BEAD_CASE_GROUP_ID = "nyct:green";
const BEAD_CASE_LINE_IDS = [
  "metropolitan-transit-authori-4",
  "metropolitan-transit-authori-5",
  "metropolitan-transit-authori-6",
  "metropolitan-transit-authori-6x",
];
const BEAD_CASE_STATIONS = [
  { stationGroupId: "us-official-125-st-3", name: "125 St" },
  { stationGroupId: "us-official-116-st-2", name: "116 St" },
  { stationGroupId: "us-official-110-st", name: "110 St" },
  { stationGroupId: "us-official-103-st-2", name: "103 St" },
  { stationGroupId: "us-official-96-st-2", name: "96 St" },
  { stationGroupId: "us-official-77-st", name: "77 St" },
  { stationGroupId: "us-official-68-st-hunter-college", name: "68 St-Hunter College" },
  { stationGroupId: "us-official-astor-pl", name: "Astor Pl" },
  { stationGroupId: "us-official-spring-st", name: "Spring St" },
];

// Synthetic structural probes: window shapes no real corridor in this
// package currently exhibits, exercised directly against
// `RailStroke.familyPartition` with a placeholder lineId/partIndex (never
// looked up in the built network — `totalMetres`/`familyWindows`/
// `tenantWindows` are supplied by hand instead of read off a part).
const SYNTHETIC_CASES = [
  {
    lineId: "synthetic#reversed-follow",
    partIndex: 0,
    label: "synthetic — reversed follow window (from > to, as a reversed correspondence hands build-display-lanes.mjs before normalisation)",
    totalMetres: 1000,
    tenantWindows: [{ from: 600, to: 400, groupId: "synthetic:group" }],
    familyWindows: [],
    baseColor: "#336699",
    familyColor: null,
  },
  {
    lineId: "synthetic#adjacent-landlord-windows",
    partIndex: 0,
    label: "synthetic — two landlord windows meeting exactly end-to-end (kept as two family pieces, never merged into one — familyPartition's own contract, independent of build-display-lanes.mjs's unionWindows upstream)",
    totalMetres: 1000,
    tenantWindows: [],
    familyWindows: [
      { from: 200, to: 500, groupId: "synthetic:group" },
      { from: 500, to: 800, groupId: "synthetic:group" },
    ],
    baseColor: "#336699",
    familyColor: "#993366",
  },
];

// Withheld × family: a withheld (bridged blocked-interval) span straddling
// a landlord window's edge — the exact case railmap.js's withheld-run build
// and RailMapView.swift's `withheldRuns` both now handle by clipping to the
// complement of tenant windows (`RailStroke.clipRangesToComplement`) and
// then splitting the survivor(s) again at every landlord-window edge
// strictly inside them. No real us corridor currently carries both a
// withheld span and a family window on the same part (checked against the
// built network — see the build() guard below), so this is synthetic too.
// `withheld`/`withheldPieces` are ADDITIVE fields `FamilyWindowParityTests`
// does not decode (it has no notion of withheld spans at all — that is a
// web-only overlay); `familyWindows`/`tenantWindows`/`emittedPieces` below
// are still real `familyPartition` inputs/outputs Swift DOES check, so this
// case pulls double duty.
const WITHHELD_FAMILY_CASE = {
  lineId: "synthetic#withheld-straddles-landlord-edge",
  partIndex: 0,
  label: "synthetic — withheld span straddling a landlord window's edge",
  totalMetres: 1000,
  tenantWindows: [],
  familyWindows: [{ from: 300, to: 700, groupId: "synthetic:group" }],
  baseColor: "#336699",
  familyColor: "#993366",
  // The withheld overlay's own input: one span, metres in this (synthetic)
  // part's own measure space, crossing the landlord window's LEADING edge
  // (300) — half of it (100…300) is on plain track (this line's own
  // colour), half (300…500) is on the landlord window (the family colour).
  withheld: [[100, 500]],
};

function piecesFor(RailStroke, totalMetres, tenantWindows, familyWindows, baseColor, familyColor) {
  const partition = RailStroke.familyPartition(totalMetres, tenantWindows, familyWindows);
  const basePieces = partition.base.map((range) => ({
    feature: "base",
    from: Number(range.from.toFixed(1)),
    to: Number(range.to.toFixed(1)),
    colorKey: baseColor,
  }));
  const familyPieces = familyColor
    ? partition.family.map((range) => ({
        feature: "family",
        from: Number(range.from.toFixed(1)),
        to: Number(range.to.toFixed(1)),
        colorKey: familyColor,
        groupId: range.groupId,
      }))
    : [];
  return [...basePieces, ...familyPieces].sort((a, b) => a.from - b.from);
}

// The withheld-run split railmap.js's `_applyContinuousStrokes` and
// RailMapView.swift's `continuousStrokeBuild` both apply: clip to the
// complement of tenant windows, then split each surviving piece again at
// every landlord-window edge strictly inside it, colouring each final
// sub-piece by its own midpoint against the landlord windows.
function withheldPiecesFor(RailStroke, withheld, tenantWindows, familyWindows, baseColor, familyColor) {
  const visible = RailStroke.clipRangesToComplement(
    withheld.map(([from, to]) => ({ from, to })),
    tenantWindows,
  );
  const pieces = [];
  for (const range of visible) {
    const cuts = new Set([range.from, range.to]);
    for (const window of familyWindows) {
      const lo = Math.min(window.from, window.to);
      const hi = Math.max(window.from, window.to);
      if (lo > range.from && lo < range.to) cuts.add(lo);
      if (hi > range.from && hi < range.to) cuts.add(hi);
    }
    const points = [...cuts].sort((a, b) => a - b);
    for (let index = 0; index < points.length - 1; index += 1) {
      const from = points[index];
      const to = points[index + 1];
      if (to - from <= RailStroke.FAMILY_PARTITION_EPSILON_METRES) continue;
      const mid = (from + to) / 2;
      const inLandlord = familyWindows.some((window) => mid >= window.from && mid <= window.to);
      pieces.push({
        from: Number(from.toFixed(1)),
        to: Number(to.toFixed(1)),
        colorKey: inLandlord ? familyColor : baseColor,
      });
    }
  }
  return pieces;
}

export function build({ RailNetwork, railPackage, APP_DIR }) {
  const RailStroke = require(path.join(APP_DIR, "public", "rail-stroke.js"));
  const railDir = path.join(APP_DIR, "public", "rail");
  const reviewed = JSON.parse(
    fs.readFileSync(path.join(railDir, "shared-corridors.json"), "utf8"),
  );
  const lanes = JSON.parse(
    fs.readFileSync(path.join(railDir, "display-lanes.json"), "utf8"),
  );

  const networks = new Map();
  const networkFor = (country) => {
    if (!networks.has(country))
      networks.set(
        country,
        RailNetwork.buildNetworkFromCompactPackage(railPackage(country), reviewed, lanes),
      );
    return networks.get(country);
  };
  const network = networkFor("us");
  const jpNetwork = networkFor("jp");

  // Real corridors have no genuine withheld×family overlap in the current
  // us or jp packages — confirmed here, at build time, rather than merely
  // asserted in the comment above: if a future data change gives some line
  // both a withheld span AND a family window on the same part, this throws
  // so the fixture gets a REAL case instead of staying synthetic.
  for (const checkedNetwork of [network, jpNetwork]) {
    for (const line of checkedNetwork.strokeModel?.lines || []) {
      for (const [partIndex, part] of line.parts.entries()) {
        const hasFamily = (part.familyWindows?.length || 0) > 0;
        const hasWithheld = (part.withheld?.length || 0) > 0;
        if (hasFamily && hasWithheld)
          throw new Error(
            `family-windows fixture: ${line.lineId}#${partIndex} now carries both a ` +
              `withheld span and a landlord window — replace WITHHELD_FAMILY_CASE's ` +
              `synthetic data with this real one.`,
          );
      }
    }
  }

  const realCases = [...REAL_CASES, ...JP_REAL_CASES].map(({ lineId, partIndex, label, country }) => {
    const lineNetwork = networkFor(country || "us");
    const strokeLine = (lineNetwork.strokeModel?.lines || []).find(
      (held) => held.lineId === lineId,
    );
    if (!strokeLine)
      throw new Error(
        `family-windows fixture: ${lineId} not found in the built ${country || "us"} network`);
    const part = strokeLine.parts[partIndex];
    if (!part)
      throw new Error(`family-windows fixture: ${lineId}#${partIndex} has no such part`);

    const baseFeature = lineNetwork.segments.features[strokeLine.featureIndex];
    const familyFeature =
      strokeLine.familyFeatureIndex != null
        ? lineNetwork.segments.features[strokeLine.familyFeatureIndex]
        : null;

    const familyWindows = part.familyWindows.map((w) => ({ ...w }));
    const tenantWindows = part.tenantWindows.map((w) => ({ ...w }));
    const baseColor = baseFeature.properties.color;
    const familyColor = familyFeature?.properties.color ?? null;

    const entry = {
      label,
      lineId,
      partIndex,
      totalMetres: Number(part.totalMetres.toFixed(1)),
      // The raw derived windows on this part, straight off
      // strokeModel.lines[].parts[].familyWindows/tenantWindows — the same
      // fields railmap.js reads at every rebuild.
      familyWindows,
      tenantWindows,
      hasFamilyFeature: strokeLine.familyFeatureIndex != null,
      baseColor,
      familyColor,
      // Every piece the base + family features together draw for this part,
      // in measure order, with the colour it draws in. A tenant window is
      // the GAP between two of these — present in neither list, drawn by
      // neither feature. Boundaries are exact: the end of one piece is the
      // start of the next (or of a tenant gap), never overlapping —
      // RailStroke.familyPartition cuts both from the same exclusion set.
      emittedPieces: piecesFor(RailStroke, part.totalMetres, tenantWindows, familyWindows, baseColor, familyColor),
    };

    // Additive: the express-landlord/local-tenant bead decision at a
    // curated list of physical stations along this corridor. Not read by
    // FamilyWindowParityTests (Case has no `beadDecisions` field) — the web
    // agent's own record of rail-network.js's family-bead suppression
    // (D1/D2) for this same family, independent of the partition/stroke
    // question the rest of this case answers.
    if (lineId === "metropolitan-transit-authori-5") {
      entry.beadDecisions = BEAD_CASE_STATIONS.map(({ stationGroupId, name }) => {
        const emittedLineIds = network.stations.features
          .filter(
            (feature) =>
              feature.properties.stationGroupId === stationGroupId &&
              BEAD_CASE_LINE_IDS.includes(feature.properties.lineId),
          )
          .map((feature) => feature.properties.lineId)
          .sort();
        return { stationGroupId, name, groupId: BEAD_CASE_GROUP_ID, emittedLineIds };
      });
    }

    return entry;
  });

  const syntheticCases = SYNTHETIC_CASES.map((c) => ({
    label: c.label,
    lineId: c.lineId,
    partIndex: c.partIndex,
    totalMetres: c.totalMetres,
    familyWindows: c.familyWindows,
    tenantWindows: c.tenantWindows,
    hasFamilyFeature: c.familyColor != null,
    baseColor: c.baseColor,
    familyColor: c.familyColor,
    emittedPieces: piecesFor(RailStroke, c.totalMetres, c.tenantWindows, c.familyWindows, c.baseColor, c.familyColor),
  }));

  const withheldCase = {
    label: WITHHELD_FAMILY_CASE.label,
    lineId: WITHHELD_FAMILY_CASE.lineId,
    partIndex: WITHHELD_FAMILY_CASE.partIndex,
    totalMetres: WITHHELD_FAMILY_CASE.totalMetres,
    familyWindows: WITHHELD_FAMILY_CASE.familyWindows,
    tenantWindows: WITHHELD_FAMILY_CASE.tenantWindows,
    hasFamilyFeature: true,
    baseColor: WITHHELD_FAMILY_CASE.baseColor,
    familyColor: WITHHELD_FAMILY_CASE.familyColor,
    emittedPieces: piecesFor(
      RailStroke,
      WITHHELD_FAMILY_CASE.totalMetres,
      WITHHELD_FAMILY_CASE.tenantWindows,
      WITHHELD_FAMILY_CASE.familyWindows,
      WITHHELD_FAMILY_CASE.baseColor,
      WITHHELD_FAMILY_CASE.familyColor,
    ),
    // Additive — see the withheldPiecesFor doc above.
    withheld: WITHHELD_FAMILY_CASE.withheld,
    withheldPieces: withheldPiecesFor(
      RailStroke,
      WITHHELD_FAMILY_CASE.withheld,
      WITHHELD_FAMILY_CASE.tenantWindows,
      WITHHELD_FAMILY_CASE.familyWindows,
      WITHHELD_FAMILY_CASE.baseColor,
      WITHHELD_FAMILY_CASE.familyColor,
    ),
  };

  // The ca case: na-render-groups.json currently derives NO family windows
  // for Canada at all (checked here, at build time, against the actual
  // built ca network — not merely asserted) — so there is nothing to pin
  // yet. Additive top-level field; recorded so a future ca family window
  // is a visible gap in this fixture rather than a silent one.
  const caNetwork = networkFor("ca");
  const caHasFamilyWindows = (caNetwork.strokeModel?.lines || []).some((line) =>
    line.parts.some((part) => (part.familyWindows?.length || 0) > 0 || (part.tenantWindows?.length || 0) > 0),
  );
  const caFamilyWindows = caHasFamilyWindows
    ? {
        region: "ca",
        hasFamilyWindows: true,
        note:
          "ca now derives family windows — extend REAL_CASES above with a real " +
          "Canadian corridor instead of relying on this note.",
      }
    : {
        region: "ca",
        hasFamilyWindows: false,
        note:
          "na-render-groups.json currently derives no ca family windows (no ca " +
          "byLineId render group has a follow naming a same-group leader) — " +
          "nothing to pin here yet.",
      };

  return {
    describes:
      "rail-network.js familyWindowRowsByPart + railmap.js _applyContinuousStrokes' " +
      "family-window slicing (build-display-lanes.mjs deriveFamilyWindows, via " +
      "na-render-groups.json render groups and display-lanes.json " +
      "familyWindowsByRegion), and rail-network.js's family-bead station " +
      "suppression (D1/D2)",
    contract:
      "For a part with tenant and/or landlord family windows, the drawn " +
      "corridor comes apart into pieces in measure order via the SHARED " +
      "RailStroke.familyPartition: BASE pieces (this line's own colour) " +
      "cover the complement of every tenant ∪ landlord window; a FAMILY " +
      "piece (the group's colour, via familyFeatureIndex) covers each " +
      "landlord window, one piece per window, never merged with a " +
      "neighbour; a tenant window is drawn by neither — it is a gap, " +
      "standing in for the corresponding landlord's own stroke drawn " +
      "elsewhere. Piece boundaries are exact window edges (already snapped " +
      "to a station measure by deriveFamilyWindows, on ONE ruler — D4), so " +
      "the Swift port's own slicing is expected to land on identical " +
      "`from`/`to` values and identical colours for every case here. A " +
      "tenant's own station bead is suppressed only when a same-group " +
      "sibling holds a LANDLORD window covering ITS OWN anchor at the same " +
      "physical station (`beadDecisions` on the NYCT case); with no such " +
      "sibling, exactly the lowest-lineId tenant keeps its bead.",
    cases: [...realCases, ...syntheticCases, withheldCase],
    caFamilyWindows,
  };
}
