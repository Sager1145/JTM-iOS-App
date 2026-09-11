#!/usr/bin/env node
// Applies manual corrections to app/public/rail/jp-2025.json in order.
// Usage:
//   node apply.mjs           # apply and write the package back to disk
//   node apply.mjs --check   # apply in memory only; exit non-zero if the
//                            # result differs from what's on disk (idempotency gate)

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  decodeIntervals,
  encodeIntervals,
  projectPointOntoPolyline,
  projectOntoN02Keys,
  chainFromN02,
  buildChainWithExtensions,
  polylineKm,
  haversineM,
} from './geo.mjs';

// --- structure tuple rebasing -----------------------------------------
//
// `structure` tuples are [start_m, end_m, type, sub], expressed as
// cumulative km (in metres) along a line, using the SAME baseline the
// line's own segment km values use (not a haversine-of-simplified-coords
// recompute -- see the geo.mjs decodeIntervals/encodeIntervals comment).

function structureIntervalBounds(segments) {
  const bounds = [0];
  for (const row of segments) {
    bounds.push(bounds[bounds.length - 1] + Math.round(row[0] * 1000));
  }
  return bounds;
}

function clipStructureTuple(tuple, lo, hi) {
  const [start, end, type, sub] = tuple;
  const s = Math.max(start, lo);
  const e = Math.min(end, hi);
  if (e <= s) return null;
  return [s, e, type, sub];
}

// Rebases structure tuples from an old-line snapshot `{ segments, structure }`
// onto new destinations described by `mapping`, an array parallel to the
// snapshot's old intervals (mapping[i] <-> old interval i). Each entry is
// either null (that old interval's structure is not carried anywhere) or
// `{ line, newStart, reversed }`: `line` is the destination line object
// (tuples are appended to `line.structure`, created on first push);
// `newStart` is the cumulative km (metres) at which this old interval's
// content begins in `line`'s NEW numbering; `reversed` mirrors the tuple
// within the interval (for a reversed interval).
//
// A single old interval may legitimately feed MULTIPLE destinations (the
// same physical track reused, possibly reversed, in more than one output
// line -- e.g. a loop sharing trackage with the line it branches from): call
// this function more than once over the same old-line snapshot with
// different (possibly overlapping) mappings. Each call only ever reads the
// snapshot and appends to destination lines, so overlapping calls are safe.
function rebaseStructure(oldLine, mapping) {
  const bounds = structureIntervalBounds(oldLine.segments);
  const oldStructure = Array.isArray(oldLine.structure) ? oldLine.structure : [];
  mapping.forEach((dest, i) => {
    if (!dest) return;
    const lo = bounds[i];
    const hi = bounds[i + 1];
    const len = hi - lo;
    for (const tuple of oldStructure) {
      const clipped = clipStructureTuple(tuple, lo, hi);
      if (!clipped) continue;
      const [s, e, type, sub] = clipped;
      const relStart = s - lo;
      const relEnd = e - lo;
      let newStart;
      let newEnd;
      if (dest.reversed) {
        newStart = dest.newStart + (len - relEnd);
        newEnd = dest.newStart + (len - relStart);
      } else {
        newStart = dest.newStart + relStart;
        newEnd = dest.newStart + relEnd;
      }
      if (!Array.isArray(dest.line.structure)) dest.line.structure = [];
      dest.line.structure.push([newStart, newEnd, type, sub]);
    }
  });
}

// Sorts a line's accumulated structure tuples and merges adjacent pieces
// that share type/sub and touch end-to-end (this re-fuses tuples that
// clipStructureTuple split across an old interval boundary but that landed
// contiguously in the new numbering). Deletes the key entirely if nothing
// ended up mapped, matching the convention that lines with no structure
// data simply omit the field.
function finalizeStructure(line) {
  if (!Array.isArray(line.structure)) {
    delete line.structure;
    return;
  }
  const sorted = line.structure.slice().sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const merged = [];
  for (const t of sorted) {
    const last = merged[merged.length - 1];
    // Do NOT fuse touching pieces: the shipped tuples are one-per-N02-section
    // and the reviewer asked that no original boundary be erased, so the only
    // count change a rebase may cause is the split of a tuple that straddles
    // a moved interval boundary.
    if (last && false) {
      last[1] = t[1];
    } else {
      merged.push(t.slice());
    }
  }
  if (merged.length === 0) {
    delete line.structure;
  } else {
    line.structure = merged;
  }
}

// --- decoded-interval helpers (decodeIntervals now yields {coords, km}) -

function entryCoords(entry) {
  return Array.isArray(entry) ? entry : entry.coords;
}

function reverseEntry(entry) {
  const coords = entryCoords(entry).slice().reverse();
  return Array.isArray(entry) ? coords : { coords, km: entry.km };
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..', '..', '..', '..');
const packagePath = path.join(repoRoot, 'app', 'public', 'rail', 'jp-2025.json');
const correctionsPath = path.join(__dirname, 'corrections.json');

const checkMode = process.argv.includes('--check');

const baseFlagIndex = process.argv.indexOf('--base');
const basePath = baseFlagIndex !== -1 ? process.argv[baseFlagIndex + 1] : null;
if (baseFlagIndex !== -1 && !basePath) {
  throw new Error('--base requires a path argument');
}

function findLine(pkg, lineId) {
  const line = pkg.lines.find((l) => l.id === lineId);
  if (!line) {
    throw new Error(`line not found: ${lineId}`);
  }
  return line;
}

function spansEqual(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
  return a.every((span, i) => {
    const other = b[i];
    return (
      Array.isArray(span) &&
      Array.isArray(other) &&
      span.length === other.length &&
      span.every((v, j) => v === other[j])
    );
  });
}

function applySetServiceStatus(pkg, op) {
  const line = findLine(pkg, op.lineId);
  const { stations } = line;
  const [expectStart, expectEnd] = op.expectStations;

  for (const [start, end] of op.serviceSpans) {
    if (start < 0 || start >= stations.length || end < 0 || end >= stations.length) {
      throw new Error(`[${op.id}] span indices out of range for ${op.lineId}`);
    }
  }

  const firstSpan = op.serviceSpans[0];
  const startName = stations[firstSpan[0]][1];
  const endName = stations[firstSpan[1]][1];
  if (startName !== expectStart) {
    throw new Error(
      `[${op.id}] expected station at index ${firstSpan[0]} to be "${expectStart}", found "${startName}"`
    );
  }
  if (endName !== expectEnd) {
    throw new Error(
      `[${op.id}] expected station at index ${firstSpan[1]} to be "${expectEnd}", found "${endName}"`
    );
  }

  const alreadyApplied =
    line.serviceStatus === op.serviceStatus && spansEqual(line.serviceSpans, op.serviceSpans);

  line.serviceStatus = op.serviceStatus;
  line.serviceSpans = op.serviceSpans;

  return alreadyApplied;
}

function applySetKind(pkg, op) {
  const line = findLine(pkg, op.lineId);
  if (line.kind !== op.from && line.kind !== op.to) {
    throw new Error(
      `[${op.id}] line ${op.lineId} has kind "${line.kind}", expected "${op.from}" or "${op.to}"`
    );
  }
  const alreadyApplied = line.kind === op.to;
  line.kind = op.to;
  return alreadyApplied;
}

function applyRenameStation(pkg, op) {
  let matchedFrom = 0;
  let matchedTo = 0;

  for (const line of pkg.lines) {
    for (const row of line.stations) {
      if (row[0] === op.stationId) {
        if (row[1] === op.from) {
          row[1] = op.to;
          matchedFrom += 1;
        } else if (row[1] === op.to) {
          matchedTo += 1;
        }
      }
    }
  }

  if (matchedFrom === 0 && matchedTo === 0) {
    throw new Error(
      `[${op.id}] no station rows found for stationId ${op.stationId} named "${op.from}" or "${op.to}"`
    );
  }

  return matchedFrom === 0 && matchedTo > 0;
}

// --- batch B: topology ------------------------------------------------

function applySplitIntervalAtStation(pkg, op) {
  const line = findLine(pkg, op.lineId);
  if (line.segments.length !== line.stations.length - 1) {
    throw new Error(
      `[${op.id}] ${op.lineId}: segments.length=${line.segments.length} inconsistent with stations.length=${line.stations.length}`
    );
  }
  const [fromId, toId] = op.betweenIds;
  const idx = line.stations.findIndex((r) => r[0] === fromId);
  if (idx === -1) {
    throw new Error(`[${op.id}] station ${fromId} not found on ${op.lineId}`);
  }
  const nextRow = line.stations[idx + 1];
  if (nextRow && nextRow[0] === op.newStation.sid) {
    return true; // already applied
  }
  if (!nextRow || nextRow[0] !== toId) {
    throw new Error(
      `[${op.id}] expected station after ${fromId} to be ${toId}, found ${nextRow ? nextRow[0] : 'end of line'}`
    );
  }

  const anchorLine = findLine(pkg, op.anchorSource.lineId);
  const anchorRow = anchorLine.stations.find((r) => r[0] === op.anchorSource.sid);
  if (!anchorRow) {
    throw new Error(`[${op.id}] anchor row ${op.anchorSource.sid} not found on ${op.anchorSource.lineId}`);
  }

  const oldSegments = line.segments;
  const oldStructure = line.structure;
  const oldBounds = structureIntervalBounds(oldSegments);

  const polylines = decodeIntervals(line);
  const poly = entryCoords(polylines[idx]);
  const proj = projectPointOntoPolyline([anchorRow[2], anchorRow[3]], poly);
  if (proj.distanceM > op.maxM) {
    throw new Error(
      `[${op.id}] anchor is ${proj.distanceM.toFixed(1)}m from the ${fromId}->${toId} interval (max ${op.maxM}m)`
    );
  }

  const newRow = [op.newStation.sid, op.newStation.name, proj.point[0], proj.point[1], anchorRow[4], anchorRow[5]];
  const polyA = [...poly.slice(0, proj.insertIndex + 1), proj.point];
  const polyB = [proj.point, ...poly.slice(proj.insertIndex + 1)];
  polylines.splice(idx, 1, polyA, polyB);

  line.stations.splice(idx + 1, 0, newRow);
  line.segments = encodeIntervals(polylines);

  // Splitting an interval doesn't move any cumulative-km position along the
  // line (it only inserts a vertex), so this is an identity rebase: every
  // old interval, including the one that got split into two, keeps its
  // original absolute km position.
  line.structure = undefined;
  rebaseStructure(
    { segments: oldSegments, structure: oldStructure },
    oldSegments.map((_, i) => ({ line, newStart: oldBounds[i], reversed: false }))
  );
  finalizeStructure(line);

  op._result = { projDistanceM: Math.round(proj.distanceM * 10) / 10 };
  return false;
}

function applyRemoveLine(pkg, op) {
  const idx = pkg.lines.findIndex((l) => l.id === op.lineId);
  if (idx === -1) {
    return true; // already applied
  }
  pkg.lines.splice(idx, 1);
  return false;
}

function applyPortlinerRestructure(pkg, op) {
  const main = findLine(pkg, op.mainLineId);
  const loopLine = findLine(pkg, op.loopLineId);

  const mainApplied = main.stations[op.keepPrefixIds.length] && main.stations[op.keepPrefixIds.length][0] === op.newIntervalTo;
  const loopApplied =
    loopLine.stations.length === op.loopStations.length &&
    loopLine.stations[0] &&
    loopLine.stations[0][0] === op.loopStations[0];
  if (mainApplied && loopApplied) {
    return true;
  }
  if (mainApplied || loopApplied) {
    throw new Error(
      `[${op.id}] half-applied portliner-restructure: main applied=${mainApplied}, loop applied=${loopApplied}`
    );
  }

  const oldMainSegments = main.segments;
  const oldMainStructure = main.structure;
  const oldLoopSegments = loopLine.segments;
  const oldLoopStructure = loopLine.structure;

  const mainPolys = decodeIntervals(main); // [{coords, km}]
  const bySid = Object.fromEntries(main.stations.map((r) => [r[0], r]));
  const fromRow = bySid[op.newIntervalFrom];
  const toRowOld = loopLine.stations.find((r) => r[0] === op.newIntervalTo);
  if (!fromRow || !toRowOld) {
    throw new Error(`[${op.id}] could not resolve endpoints for the new interval`);
  }

  const chain = chainFromN02({
    keys: op.newIntervalKeys,
    fromAnchor: [fromRow[2], fromRow[3]],
    toAnchor: [toRowOld[2], toRowOld[3]],
    fromMaxM: op.maxM,
    toMaxM: op.maxM,
    snapM: op.snapM || 20,
  });

  const oldLoopFirst = decodeIntervals(loopLine)[0]; // {coords, km}: みなとじま -> 市民広場

  const prefixCount = op.keepPrefixIds.length - 1;
  const suffixCount = op.keepSuffixIds.length - 1;
  const prefixEntries = mainPolys.slice(0, prefixCount); // unchanged interval, keep km
  const suffixEntries = mainPolys.slice(mainPolys.length - suffixCount); // unchanged interval, keep km
  const newMainEntries = [
    ...prefixEntries,
    chain.coords, // new track -> recompute km
    oldLoopFirst, // same physical interval, same direction -> keep km
    ...suffixEntries,
  ];
  const newMainStations = [
    ...op.keepPrefixIds.map((id) => bySid[id]),
    toRowOld,
    ...op.keepSuffixIds.map((id) => bySid[id]),
  ];

  main.stations = newMainStations;
  main.segments = encodeIntervals(newMainEntries);

  const loopEntries = op.reuseIntervalFromMain.map((i) => reverseEntry(mainPolys[i])); // reused main interval, reversed -> keep km
  loopLine.stations = op.loopStations.map((id) => bySid[id]);
  loopLine.segments = encodeIntervals(loopEntries);

  // --- structure rebase --------------------------------------------------
  const mainPieceKms = [
    ...prefixEntries.map((e) => e.km),
    chain.km,
    oldLoopFirst.km,
    ...suffixEntries.map((e) => e.km),
  ];
  const newMainBounds = [0];
  for (const km of mainPieceKms) newMainBounds.push(newMainBounds[newMainBounds.length - 1] + Math.round(km * 1000));

  const newLoopBounds = [0];
  for (const e of loopEntries) newLoopBounds.push(newLoopBounds[newLoopBounds.length - 1] + Math.round(e.km * 1000));

  main.structure = undefined;
  loopLine.structure = undefined;

  // old main's prefix/suffix intervals stay on main, unchanged direction,
  // shifted to their new positions.
  const mainOwnMapping = oldMainSegments.map(() => null);
  for (let k = 0; k < prefixCount; k += 1) {
    mainOwnMapping[k] = { line: main, newStart: newMainBounds[k], reversed: false };
  }
  const suffixStartOldIdx = oldMainSegments.length - suffixCount;
  const suffixStartNewIdx = prefixCount + 2; // prefix + chain + oldLoopFirst
  for (let k = 0; k < suffixCount; k += 1) {
    mainOwnMapping[suffixStartOldIdx + k] = { line: main, newStart: newMainBounds[suffixStartNewIdx + k], reversed: false };
  }
  rebaseStructure({ segments: oldMainSegments, structure: oldMainStructure }, mainOwnMapping);

  // old main's reused-for-loop intervals go to loopLine, reversed.
  const mainToLoopMapping = oldMainSegments.map(() => null);
  op.reuseIntervalFromMain.forEach((oldIdx, k) => {
    mainToLoopMapping[oldIdx] = { line: loopLine, newStart: newLoopBounds[k], reversed: true };
  });
  rebaseStructure({ segments: oldMainSegments, structure: oldMainStructure }, mainToLoopMapping);

  // old loop line's own first interval (みなとじま -> 市民広場) moves onto
  // main, unchanged direction, at the oldLoopFirst position.
  const loopToMainMapping = oldLoopSegments.map(() => null);
  loopToMainMapping[0] = { line: main, newStart: newMainBounds[prefixCount + 1], reversed: false };
  rebaseStructure({ segments: oldLoopSegments, structure: oldLoopStructure }, loopToMainMapping);

  finalizeStructure(main);
  finalizeStructure(loopLine);

  op._result = { newIntervalKm: chain.km };
  return false;
}

function applyPrependInterval(pkg, op) {
  const line = findLine(pkg, op.lineId);
  if (line.segments.length !== line.stations.length - 1) {
    throw new Error(
      `[${op.id}] ${op.lineId}: segments.length=${line.segments.length} inconsistent with stations.length=${line.stations.length}`
    );
  }
  if (line.stations[0][0] === op.newStation.sid) {
    return true; // already applied
  }
  if (line.stations[0][0] !== op.toStationId) {
    throw new Error(`[${op.id}] expected first station of ${op.lineId} to be ${op.toStationId}`);
  }

  const anchorLine = findLine(pkg, op.fromAnchorSource.lineId);
  const anchorRow = anchorLine.stations.find((r) => r[0] === op.fromAnchorSource.sid);
  if (!anchorRow) {
    throw new Error(`[${op.id}] anchor row ${op.fromAnchorSource.sid} not found on ${op.fromAnchorSource.lineId}`);
  }

  const toAnchor = [line.stations[0][2], line.stations[0][3]];
  const chain = buildChainWithExtensions({
    keys: op.keys,
    fromAnchor: [anchorRow[2], anchorRow[3]],
    toAnchor,
    tightM: op.tightM || 40,
    looseM: op.looseM || 200,
    snapM: op.snapM || 20,
  });

  const oldSegments = line.segments;
  const oldStructure = line.structure;
  const oldBounds = structureIntervalBounds(oldSegments);

  const newRow = [op.newStation.sid, op.newStation.name, anchorRow[2], anchorRow[3], anchorRow[4], anchorRow[5]];
  const polylines = decodeIntervals(line);
  polylines.unshift(chain.coords);
  line.stations.unshift(newRow);
  line.segments = encodeIntervals(polylines);

  const shiftM = Math.round(chain.km * 1000);
  line.structure = undefined;
  rebaseStructure(
    { segments: oldSegments, structure: oldStructure },
    oldSegments.map((_, i) => ({ line, newStart: oldBounds[i] + shiftM, reversed: false }))
  );
  finalizeStructure(line);

  op._result = { newIntervalKm: chain.km, fromExtensionM: chain.fromExtensionM, toExtensionM: chain.toExtensionM, structureShiftM: shiftM };
  return false;
}

function resolveStationSpec(spec, pkg) {
  if (spec.kind === 'existing') {
    const src = findLine(pkg, spec.sourceLineId);
    const row = src.stations.find((r) => r[0] === spec.sid);
    if (!row) {
      throw new Error(`station ${spec.sid} not found on ${spec.sourceLineId}`);
    }
    return { row: row.slice(), n02Point: null };
  }
  return {
    row: [spec.sid, spec.name, null, null, spec.roma, spec.romaSource],
    n02Point: spec.n02Point,
  };
}

function buildIntervalsFromSpec(pkg, stationSpecs, intervalSpecs) {
  const states = stationSpecs.map((s) => resolveStationSpec(s, pkg));
  const polylines = [];
  const notes = [];
  for (let i = 0; i < intervalSpecs.length; i += 1) {
    const ivl = intervalSpecs[i];
    const fromRow = states[i].row;
    const toRow = states[i + 1].row;
    if (fromRow[2] == null) {
      const p = projectOntoN02Keys(states[i].n02Point, ivl.keys, ivl.newStationMaxM || 60);
      fromRow[2] = p.point[0];
      fromRow[3] = p.point[1];
      notes.push(`${fromRow[1]} anchored ${p.distanceM.toFixed(1)}m from N02 track`);
    }
    if (toRow[2] == null) {
      const p = projectOntoN02Keys(states[i + 1].n02Point, ivl.keys, ivl.newStationMaxM || 60);
      toRow[2] = p.point[0];
      toRow[3] = p.point[1];
      notes.push(`${toRow[1]} anchored ${p.distanceM.toFixed(1)}m from N02 track`);
    }
    const chain = buildChainWithExtensions({
      keys: ivl.keys,
      fromAnchor: [fromRow[2], fromRow[3]],
      toAnchor: [toRow[2], toRow[3]],
      tightM: ivl.tightM || 40,
      looseM: ivl.looseM || 200,
      snapM: ivl.snapM || 20,
    });
    polylines.push(chain.coords);
    if (chain.fromExtensionM) notes.push(`${fromRow[1]} extended ${chain.fromExtensionM}m to reach the anchor`);
    if (chain.toExtensionM) notes.push(`${toRow[1]} extended ${chain.toExtensionM}m to reach the anchor`);
    notes.push(`interval ${fromRow[1]}->${toRow[1]}: ${chain.km}km`);
  }
  return { stations: states.map((s) => s.row), polylines, notes };
}

function applyAddLine(pkg, op) {
  const alreadyApplied = pkg.lines.some((l) => l.id === op.lineId);
  if (alreadyApplied) {
    return true;
  }

  let meta = {};
  if (op.cloneMetaFrom) {
    const src = findLine(pkg, op.cloneMetaFrom);
    meta = { ...src };
    delete meta.stations;
    delete meta.segments;
    delete meta.structure;
  }
  meta = { ...meta, ...(op.metaOverrides || {}), id: op.lineId };

  const built = buildIntervalsFromSpec(pkg, op.stations, op.intervals);
  meta.stations = built.stations;
  meta.segments = encodeIntervals(built.polylines);

  // insert keeping pkg.lines sorted by id
  const insertAt = pkg.lines.findIndex((l) => l.id > op.lineId);
  if (insertAt === -1) {
    pkg.lines.push(meta);
  } else {
    pkg.lines.splice(insertAt, 0, meta);
  }

  op._result = { notes: built.notes };
  return false;
}

function ringSignedArea(polylines) {
  // Shoelace signed area over (lon, lat); positive == anticlockwise on a
  // north-up map. Junction vertices are shared between consecutive
  // polylines, so summing each polyline's own internal edges covers every
  // real edge of the closed ring exactly once.
  let area = 0;
  for (const poly of polylines) {
    for (let i = 0; i < poly.length - 1; i += 1) {
      const [x1, y1] = poly[i];
      const [x2, y2] = poly[i + 1];
      area += x1 * y2 - x2 * y1;
    }
  }
  return area / 2;
}

function applySplitLoop(pkg, op) {
  const existing = pkg.lines.find((l) => l.id === op.newLineId);
  const main = findLine(pkg, op.lineId);
  const splitIdx = op.splitStationIndex; // index shared by both rows (e.g. 都庁前)

  if (existing) {
    // Idempotency gate: the loop row must already be in the canonical
    // anticlockwise winding, anchored at the split station (都庁前) with
    // the next station being the one reached via 新宿, AND main must
    // already be truncated to the radial row (splitIdx+1 stations) -- a
    // new-line-present-but-main-not-truncated state is half-applied.
    const s0 = existing.stations[0];
    const s1 = existing.stations[1];
    const canonicalWinding = !!(s0 && s1 && s0[1] === '都庁前' && s1[1] === '新宿');
    const mainTruncated = main.stations.length === splitIdx + 1;
    if (canonicalWinding && mainTruncated) {
      return true;
    }
    throw new Error(
      `${op.type}: line ${op.newLineId} exists but the state is inconsistent (canonicalWinding=${canonicalWinding}, mainTruncated=${mainTruncated}, main.stations.length=${main.stations.length})`
    );
  }

  if (!main.stations[splitIdx] || main.stations[splitIdx][1] !== op.expectStation) {
    throw new Error(
      `[${op.id}] expected station at index ${splitIdx} to be "${op.expectStation}", found "${main.stations[splitIdx] ? main.stations[splitIdx][1] : 'end of line'}"`
    );
  }
  if (!(main.stations.length > splitIdx)) {
    throw new Error(`[${op.id}] splitStationIndex ${splitIdx} out of range for ${op.lineId} (stations.length=${main.stations.length})`);
  }

  const oldSegments = main.segments;
  const oldStructure = main.structure;
  const oldBounds = structureIntervalBounds(oldSegments);

  const decoded = decodeIntervals(main); // [{coords, km}]
  const stations = main.stations;

  const row1Stations = stations.slice(0, splitIdx + 1);
  const row1Entries = decoded.slice(0, splitIdx); // unchanged, keep km

  const row2StationsBase = stations.slice(splitIdx);
  const row2EntriesBase = decoded.slice(splitIdx); // unchanged, keep km
  const baseCount = row2EntriesBase.length;

  const fromAnchorRow = stations[stations.length - 1];
  const toAnchorRow = stations[splitIdx];
  const closing = buildChainWithExtensions({
    keys: op.closingKeys,
    fromAnchor: [fromAnchorRow[2], fromAnchorRow[3]],
    toAnchor: [toAnchorRow[2], toAnchorRow[3]],
    tightM: op.tightM || 40,
    looseM: op.looseM || 200,
    snapM: op.snapM || 20,
  });

  let row2Entries = [...row2EntriesBase, closing.coords]; // last one is new track, recompute km
  let row2Stations = row2StationsBase;
  let row2Reversed = false;

  // The builder requires every `loop` part to have positive shoelace signed
  // area in (lon, lat) — anticlockwise on a north-up map — and refuses to
  // silently reverse a ring that carries lane/follow rows. The Oedo loop as
  // assembled above (都庁前 -> 新宿西口 -> ... -> 新宿 -> 都庁前) is clockwise,
  // so flip it here to the canonical anticlockwise winding, which Toei calls
  // the 都庁前→六本木・大門方面 direction (via 新宿).
  if (ringSignedArea(row2Entries.map(entryCoords)) < 0) {
    row2Stations = [row2StationsBase[0], ...row2StationsBase.slice(1).reverse()];
    row2Entries = [...row2Entries].reverse().map(reverseEntry);
    row2Reversed = true;
  }

  main.stations = row1Stations;
  main.segments = encodeIntervals(row1Entries);

  const meta2 = { ...main };
  delete meta2.stations;
  delete meta2.segments;
  delete meta2.structure;
  meta2.id = op.newLineId;
  meta2.railwayIdentity = op.lineId;
  meta2.isLoop = 1;
  meta2.stations = row2Stations;
  meta2.segments = encodeIntervals(row2Entries);

  const insertAt = pkg.lines.findIndex((l) => l.id > op.newLineId);
  if (insertAt === -1) {
    pkg.lines.push(meta2);
  } else {
    pkg.lines.splice(insertAt, 0, meta2);
  }

  // --- structure rebase --------------------------------------------------
  main.structure = undefined;
  meta2.structure = undefined;

  // row1 (radial): identity, since it's an unchanged prefix of the old line.
  const row1Mapping = oldSegments.map((_, i) => (i < splitIdx ? { line: main, newStart: oldBounds[i], reversed: false } : null));
  rebaseStructure({ segments: oldSegments, structure: oldStructure }, row1Mapping);

  // row2 (loop): the old base intervals (splitIdx..end), individually
  // unchanged in direction/content, land at whatever position they ended up
  // at in row2Entries's final (possibly ring-reversed) order.
  const row2Bounds = [0];
  for (const entry of row2Entries) {
    const km = Array.isArray(entry) ? polylineKm(entry) : entry.km;
    row2Bounds.push(row2Bounds[row2Bounds.length - 1] + Math.round(km * 1000));
  }
  const row2Mapping = oldSegments.map(() => null);
  for (let k = 0; k < baseCount; k += 1) {
    const oldIdx = splitIdx + k;
    const finalPos = row2Reversed ? row2EntriesBase.length - k : k; // reversing the whole array also reverses order
    row2Mapping[oldIdx] = { line: meta2, newStart: row2Bounds[finalPos], reversed: row2Reversed };
  }
  rebaseStructure({ segments: oldSegments, structure: oldStructure }, row2Mapping);

  finalizeStructure(main);
  finalizeStructure(meta2);

  op._result = { closingKm: closing.km };
  return false;
}

// Removes an inclusive range of interior vertices (fromVertex..toVertex,
// never the interval's first or last vertex) from a single interval of a
// line, recomputes that interval's km from its own haversine length (3dp),
// leaves every other interval's stored km untouched, and rebases
// `structure`: intervals before segmentIndex are unchanged, intervals after
// it shift by the metres removed, and tuples inside segmentIndex itself keep
// their start but have their end clamped to the interval's new (shorter)
// length.
function applyDropVertexRange(pkg, op) {
  const line = findLine(pkg, op.lineId);
  const oldSegments = line.segments;
  const oldStructure = Array.isArray(line.structure) ? line.structure : [];
  const oldBounds = structureIntervalBounds(oldSegments);

  const polylines = decodeIntervals(line);
  const entry = polylines[op.segmentIndex];
  if (!entry) {
    throw new Error(`[${op.id}] segmentIndex ${op.segmentIndex} out of range for ${op.lineId}`);
  }
  const coords = entryCoords(entry);
  const currentCount = coords.length;
  if (op.fromVertex <= 0 || op.toVertex >= currentCount - 1 || op.fromVertex > op.toVertex) {
    throw new Error(
      `[${op.id}] fromVertex/toVertex ${op.fromVertex}..${op.toVertex} invalid for a ${currentCount}-vertex interval (endpoints may not be removed)`
    );
  }
  const removedCount = op.toVertex - op.fromVertex + 1;
  // The op pins the pre-op vertex count: the current count alone cannot tell
  // "not yet applied" from "already applied" (both are just numbers), and a
  // main-line vertex legitimately survives within 60 m of expectNear.
  if (!Number.isInteger(op.expectVertexCount))
    throw new Error(`[${op.id}] drop-vertex-range needs expectVertexCount (the pre-op vertex count)`);
  const originalCount = op.expectVertexCount;
  const expectedAfterCount = originalCount - removedCount;
  if (coords.length === expectedAfterCount) return true; // already applied
  if (coords.length !== originalCount) {
    throw new Error(
      `[${op.id}] ${op.lineId} interval ${op.segmentIndex} has ${coords.length} vertices, expected ${originalCount} (before) or ${expectedAfterCount} (after)`
    );
  }

  const dist = haversineM(coords[op.fromVertex], op.expectNear);
  if (dist > 60) {
    throw new Error(`[${op.id}] vertex ${op.fromVertex} is ${dist.toFixed(1)}m from expectNear (max 60m)`);
  }

  const newCoords = [...coords.slice(0, op.fromVertex), ...coords.slice(op.toVertex + 1)];
  const newKm = Math.round(polylineKm(newCoords) * 1000) / 1000;
  const newLenM = Math.round(newKm * 1000);

  const newEntries = polylines.map((e, i) => (i === op.segmentIndex ? newCoords : e));
  line.segments = encodeIntervals(newEntries);

  const oldLenM = oldBounds[op.segmentIndex + 1] - oldBounds[op.segmentIndex];
  const shiftM = newLenM - oldLenM;

  line.structure = undefined;

  const beforeMapping = oldSegments.map((_, i) =>
    i < op.segmentIndex ? { line, newStart: oldBounds[i], reversed: false } : null
  );
  rebaseStructure({ segments: oldSegments, structure: oldStructure }, beforeMapping);

  const afterMapping = oldSegments.map((_, i) =>
    i > op.segmentIndex ? { line, newStart: oldBounds[i] + shiftM, reversed: false } : null
  );
  rebaseStructure({ segments: oldSegments, structure: oldStructure }, afterMapping);

  const lo = oldBounds[op.segmentIndex];
  const hi = oldBounds[op.segmentIndex + 1];
  for (const tuple of oldStructure) {
    const clipped = clipStructureTuple(tuple, lo, hi);
    if (!clipped) continue;
    const [s, e, type, sub] = clipped;
    const relStart = Math.min(s - lo, newLenM);
    const relEnd = Math.min(e - lo, newLenM);
    if (relEnd <= relStart) continue;
    if (!Array.isArray(line.structure)) line.structure = [];
    line.structure.push([lo + relStart, lo + relEnd, type, sub]);
  }

  finalizeStructure(line);

  op._result = { removedVertices: removedCount, newKm, shiftM };
  return false;
}

const OPERATIONS = {
  'set-service-status': applySetServiceStatus,
  'set-kind': applySetKind,
  'rename-station': applyRenameStation,
  'split-interval-at-station': applySplitIntervalAtStation,
  'remove-line': applyRemoveLine,
  'portliner-restructure': applyPortlinerRestructure,
  'prepend-interval': applyPrependInterval,
  'add-line': applyAddLine,
  'split-loop': applySplitLoop,
  'drop-vertex-range': applyDropVertexRange,
};

function recomputeStats(pkg) {
  let intervals = 0;
  let stations = 0;
  let structure = 0;
  for (const line of pkg.lines) {
    intervals += line.segments.length;
    stations += line.stations.length;
    if (Array.isArray(line.structure)) structure += line.structure.length;
  }
  return {
    ...pkg.stats,
    lines: pkg.lines.length,
    intervals,
    stations,
    structure,
  };
}

function main() {
  const readPath = basePath || packagePath;
  const rawBefore = readFileSync(readPath, 'utf8');
  // In --check mode, the comparison target is always what's on disk at
  // packagePath, even when --base points the input at a different file.
  const rawOnDisk = basePath ? readFileSync(packagePath, 'utf8') : rawBefore;
  const pkg = JSON.parse(rawBefore);
  const corrections = JSON.parse(readFileSync(correctionsPath, 'utf8'));

  const statsBefore = pkg.stats;

  for (const op of corrections) {
    const handler = OPERATIONS[op.type];
    if (!handler) {
      throw new Error(`[${op.id}] unknown operation type: ${op.type}`);
    }
    const alreadyApplied = handler(pkg, op);
    console.log(`[${op.id}] ${alreadyApplied ? 'already applied' : 'applied'}`);
  }

  pkg.stats = recomputeStats(pkg);

  console.log('stats before:', JSON.stringify(statsBefore));
  console.log('stats after: ', JSON.stringify(pkg.stats));

  const serialized = `${JSON.stringify(pkg)}\n`;

  if (checkMode) {
    if (serialized !== rawOnDisk) {
      console.error('CHECK FAILED: on-disk package differs from the applied result (not idempotent, or corrections not yet applied).');
      process.exit(1);
    }
    console.log('CHECK OK: on-disk package matches the applied result.');
    return;
  }

  writeFileSync(packagePath, serialized, 'utf8');
  console.log(`wrote ${packagePath}`);
}

main();
