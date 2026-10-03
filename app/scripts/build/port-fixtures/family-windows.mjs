// =========================================================================
//  family-windows.json — the derived family-window slicing rail-network.js
//  and railmap.js apply for same-family follows in Japanese render groups.
//
//  The real Japanese corridors and synthetic boundary probes call the shared
//  RailStroke.familyPartition production function. The fixture pins exact
//  tenant/landlord windows, emitted piece boundaries, and colours. Withheld
//  spans are also partitioned by the existing clipping implementation.
// =========================================================================

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

export const name = "family-windows.json";

const require = createRequire(import.meta.url);

// jp's own real corridors — a route-preserving family pair (jp-render-
// groups.json "九州旅客鉄道:長崎線"): the base line is the landlord over its
// own `-2` branch-service split, which is a pure tenant with no landlord
// window of its own. Read off the built jp network.
const JP_REAL_CASES = [
  {
    country: "jp",
    lineId: "jp-東日本旅客鉄道-総武線-2",
    partIndex: 0,
    label: "総武線 御茶ノ水支線 — retain continuous ink where the trunk lane cannot replace it",
  },
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
// strictly inside them. No real Japanese corridor currently carries both a
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
  const jpNetwork = networkFor("jp");

  // Real corridors have no genuine withheld×family overlap in the current
  // Japanese packages — confirmed here, at build time, rather than merely
  // asserted in the comment above: if a future data change gives some line
  // both a withheld span AND a family window on the same part, this throws
  // so the fixture gets a REAL case instead of staying synthetic.
  for (const checkedNetwork of [jpNetwork]) {
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

  const realCases = JP_REAL_CASES.map(({ lineId, partIndex, label, country }) => {
    const lineNetwork = networkFor(country);
    const strokeLine = (lineNetwork.strokeModel?.lines || []).find(
      (held) => held.lineId === lineId,
    );
    if (!strokeLine)
      throw new Error(
        `family-windows fixture: ${lineId} not found in the built ${country} network`);
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

  return {
    describes:
      "rail-network.js familyWindowRowsByPart + railmap.js _applyContinuousStrokes' " +
      "family-window slicing (build-display-lanes.mjs deriveFamilyWindows, via " +
      "jp-render-groups.json render groups and display-lanes.json " +
      "familyWindowsByRegion)",
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
      "`from`/`to` values and identical colours for every case here.",
    cases: [...realCases, ...syntheticCases, withheldCase],
  };
}
