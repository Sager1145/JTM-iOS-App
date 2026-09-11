// Geometry helpers for the jp-manual-corrections batch-B topology ops.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fragmentsPath = path.join(__dirname, 'n02-fragments.json');

const R_EARTH_M = 6371008.8;

export function haversineKm(a, b) {
  const [lon1, lat1] = a;
  const [lon2, lat2] = b;
  const p1 = (lat1 * Math.PI) / 180;
  const p2 = (lat2 * Math.PI) / 180;
  const dphi = ((lat2 - lat1) * Math.PI) / 180;
  const dlambda = ((lon2 - lon1) * Math.PI) / 180;
  const h =
    Math.sin(dphi / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dlambda / 2) ** 2;
  return (2 * R_EARTH_M * Math.asin(Math.min(1, Math.sqrt(h)))) / 1000;
}

export function haversineM(a, b) {
  return haversineKm(a, b) * 1000;
}

export function polylineKm(coords) {
  let total = 0;
  for (let i = 0; i < coords.length - 1; i += 1) {
    total += haversineKm(coords[i], coords[i + 1]);
  }
  return total;
}

// Local flat-earth projection (metres), centred on `origin`. Good to <1cm error
// over the short distances (<5km) these ops deal with.
function makeProjector(origin) {
  const lat0 = (origin[1] * Math.PI) / 180;
  const cosLat0 = Math.cos(lat0);
  return {
    toXY(pt) {
      const x = ((pt[0] - origin[0]) * Math.PI) / 180 * R_EARTH_M * cosLat0;
      const y = ((pt[1] - origin[1]) * Math.PI) / 180 * R_EARTH_M;
      return [x, y];
    },
    fromXY(xy) {
      const lon = origin[0] + (xy[0] / (R_EARTH_M * cosLat0)) * (180 / Math.PI);
      const lat = origin[1] + (xy[1] / R_EARTH_M) * (180 / Math.PI);
      return [lon, lat];
    },
  };
}

// Projects `point` onto the polyline `polyline` ([lon,lat] array with length >= 2).
// Returns {distanceM, insertIndex, point} where insertIndex is the index i such
// that the projected point falls on segment [i, i+1].
export function projectPointOntoPolyline(point, polyline) {
  const proj = makeProjector(point);
  const p = proj.toXY(point);
  let best = null;
  for (let i = 0; i < polyline.length - 1; i += 1) {
    const a = proj.toXY(polyline[i]);
    const b = proj.toXY(polyline[i + 1]);
    const abx = b[0] - a[0];
    const aby = b[1] - a[1];
    const len2 = abx * abx + aby * aby;
    let t = len2 === 0 ? 0 : ((p[0] - a[0]) * abx + (p[1] - a[1]) * aby) / len2;
    t = Math.max(0, Math.min(1, t));
    const cx = a[0] + t * abx;
    const cy = a[1] + t * aby;
    const dx = p[0] - cx;
    const dy = p[1] - cy;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (best === null || dist < best.dist) {
      best = { dist, i, t, xy: [cx, cy] };
    }
  }
  const outPoint = proj.fromXY(best.xy);
  return { distanceM: best.dist, insertIndex: best.i, point: outPoint };
}

// --- compact-v1 segment row <-> full-polyline decode/encode ---------------

// Returns an array of {coords, km} per interval. `km` is the row's stored
// km value, which for pre-existing intervals is the pre-simplification N02
// walk length, NOT the haversine of the (display-simplified) `coords`. That
// baseline km must be preserved by encodeIntervals for any interval whose
// coords are passed through unchanged (see encodeIntervals below).
export function decodeIntervals(line) {
  const polylines = [];
  let prevLast = null;
  for (const row of line.segments) {
    const [km, continuesFromPrevious, coords] = row;
    let full;
    if (continuesFromPrevious) {
      if (!prevLast) {
        throw new Error('decodeIntervals: continuesFromPrevious row with no previous vertex');
      }
      full = [prevLast, ...coords];
    } else {
      full = coords.slice();
    }
    polylines.push({ coords: full, km });
    prevLast = full[full.length - 1];
  }
  return polylines;
}

// `intervals` is an array of either raw coord arrays (a freshly built or
// altered interval, whose km must be recomputed from its polyline) or
// {coords, km} objects carried over from decodeIntervals (whose km must be
// kept as-is, since the stored baseline km is not always recoverable from
// the display-simplified coords — e.g. it predates simplification). A
// reversed interval (same coords, reversed) still carries its original km.
export function encodeIntervals(intervals) {
  const rows = [];
  for (let i = 0; i < intervals.length; i += 1) {
    const entry = intervals[i];
    const hasBaselineKm = entry && !Array.isArray(entry) && typeof entry.km === 'number';
    const full = hasBaselineKm ? entry.coords : entry;
    const km = hasBaselineKm ? entry.km : Math.round(polylineKm(full) * 1000) / 1000;
    if (i === 0) {
      rows.push([km, 0, full.slice()]);
    } else {
      rows.push([km, 1, full.slice(1)]);
    }
  }
  return rows;
}

// --- N02 fragment graph / chaining -----------------------------------------

let fragmentsCache = null;
function loadFragments() {
  if (!fragmentsCache) {
    fragmentsCache = JSON.parse(readFileSync(fragmentsPath, 'utf8'));
  }
  return fragmentsCache;
}

export function n02StationPoint(operator, line, name) {
  const { stations } = loadFragments();
  const row = stations.find((s) => s.operator === operator && s.line === line && s.name === name);
  if (!row) {
    throw new Error(`n02StationPoint: no fragment row for ${operator}|${line}|${name}`);
  }
  return row.display_point;
}

function collectSections(keys) {
  const { sections } = loadFragments();
  const polylines = [];
  for (const key of keys) {
    const list = sections[key];
    if (!list) {
      throw new Error(`chainFromN02: no fragment sections for key ${key}`);
    }
    for (const coords of list) {
      polylines.push(coords);
    }
  }
  return polylines;
}

// union-find over section endpoints, snapping within `snapM` metres. This
// unions endpoints purely by proximity, regardless of which fragment/key
// they came from -- by design, two fragments from *different* N02 keys
// (e.g. two different operator|line pairs passed to chainFromN02) that
// happen to meet at a real-world junction are meant to snap together into
// the same graph node, since that's exactly how a chain spanning several
// keys gets connected end-to-end.
function buildEndpointNodes(sections, snapM) {
  const n = sections.length;
  const parent = new Array(n * 2);
  for (let i = 0; i < n * 2; i += 1) parent[i] = i;
  function find(x) {
    while (parent[x] !== x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }
  function union(a, b) {
    const ra = find(a);
    const rb = find(b);
    if (ra !== rb) parent[ra] = rb;
  }
  const endpoints = [];
  sections.forEach((coords, i) => {
    endpoints.push({ section: i, end: 0, pt: coords[0] });
    endpoints.push({ section: i, end: 1, pt: coords[coords.length - 1] });
  });
  for (let i = 0; i < endpoints.length; i += 1) {
    for (let j = i + 1; j < endpoints.length; j += 1) {
      if (haversineM(endpoints[i].pt, endpoints[j].pt) <= snapM) {
        union(i, j);
      }
    }
  }
  const nodeOf = (sectionIdx, end) => `n${find(sectionIdx * 2 + end)}`;
  return nodeOf;
}

// Dijkstra over an adjacency map: node -> [{to, weight, edgeId}]
function dijkstra(adj, src, dst) {
  const dist = new Map([[src, 0]]);
  const prev = new Map();
  const visited = new Set();
  const queue = [[0, src]];
  while (queue.length) {
    queue.sort((a, b) => a[0] - b[0]);
    const [d, u] = queue.shift();
    if (visited.has(u)) continue;
    visited.add(u);
    if (u === dst) break;
    for (const edge of adj.get(u) || []) {
      const nd = d + edge.weight;
      if (!dist.has(edge.to) || nd < dist.get(edge.to) - 1e-9) {
        dist.set(edge.to, nd);
        prev.set(edge.to, { from: u, edge });
        queue.push([nd, edge.to]);
      }
    }
  }
  if (!dist.has(dst)) return null;
  const edges = [];
  let cur = dst;
  while (cur !== src) {
    const { from, edge } = prev.get(cur);
    edges.push(edge);
    cur = from;
  }
  edges.reverse();
  return edges;
}

function dropCloseDuplicates(coords, minM) {
  const out = [coords[0]];
  for (let i = 1; i < coords.length; i += 1) {
    if (haversineM(out[out.length - 1], coords[i]) >= minM) {
      out.push(coords[i]);
    }
  }
  return out;
}

// Builds a routable chain of N02 fragment sections between fromAnchor and
// toAnchor and returns {coords, km}.
export function chainFromN02({ keys, fromAnchor, toAnchor, fromMaxM, toMaxM, snapM = 15 }) {
  const sections = collectSections(keys);
  const nodeOf = buildEndpointNodes(sections, snapM);

  const fromProj = projectAcross(fromAnchor, sections);
  if (fromProj.distanceM > fromMaxM) {
    throw new Error(
      `chainFromN02: fromAnchor ${JSON.stringify(fromAnchor)} is ${fromProj.distanceM.toFixed(1)}m from the nearest N02 track (max ${fromMaxM}m)`
    );
  }
  const toProj = projectAcross(toAnchor, sections);
  if (toProj.distanceM > toMaxM) {
    throw new Error(
      `chainFromN02: toAnchor ${JSON.stringify(toAnchor)} is ${toProj.distanceM.toFixed(1)}m from the nearest N02 track (max ${toMaxM}m)`
    );
  }

  // Build the graph: edges are whole sections, except sections carrying a
  // projection split, which are broken into sub-edges around the split node(s).
  const adj = new Map();
  function addEdge(a, b, weight, coords) {
    if (!adj.has(a)) adj.set(a, []);
    if (!adj.has(b)) adj.set(b, []);
    adj.get(a).push({ to: b, weight, coords });
    adj.get(b).push({ to: a, weight, coords: coords.slice().reverse() });
  }

  const FROM_NODE = 'F';
  const TO_NODE = 'T';

  sections.forEach((coords, secIdx) => {
    const splitsHere = [];
    if (fromProj.sectionIndex === secIdx) splitsHere.push({ node: FROM_NODE, ...fromProj });
    if (toProj.sectionIndex === secIdx) splitsHere.push({ node: TO_NODE, ...toProj });

    const startNode = nodeOf(secIdx, 0);
    const endNode = nodeOf(secIdx, 1);

    if (splitsHere.length === 0) {
      addEdge(startNode, endNode, polylineKm(coords), coords);
      return;
    }

    splitsHere.sort((a, b) => a.insertIndex + a.t - (b.insertIndex + b.t));

    let cursorNode = startNode;
    let cursorIdx = 0; // index into coords already emitted up to
    let cursorPoint = coords[0];
    for (const split of splitsHere) {
      const segCoords = [cursorPoint, ...coords.slice(cursorIdx + 1, split.insertIndex + 1), split.point];
      addEdge(cursorNode, split.node, polylineKm(segCoords), segCoords);
      cursorNode = split.node;
      cursorIdx = split.insertIndex;
      cursorPoint = split.point;
    }
    const tailCoords = [cursorPoint, ...coords.slice(cursorIdx + 1)];
    addEdge(cursorNode, endNode, polylineKm(tailCoords), tailCoords);
  });

  const path = dijkstra(adj, FROM_NODE, TO_NODE);
  if (!path) {
    throw new Error('chainFromN02: no path found between fromAnchor and toAnchor in the given N02 fragment graph');
  }

  let coords = [];
  for (const edge of path) {
    if (coords.length === 0) {
      coords.push(...edge.coords);
    } else {
      coords.push(...edge.coords.slice(1));
    }
  }
  coords = dropCloseDuplicates(coords, 0.5);

  const distinctCount = new Set(coords.map((c) => `${c[0]},${c[1]}`)).size;
  if (distinctCount < 2) {
    throw new Error(
      `chainFromN02: resulting chain has only ${distinctCount} distinct vertex/vertices (degenerate route between fromAnchor and toAnchor)`
    );
  }

  coords[0] = fromAnchor;
  coords[coords.length - 1] = toAnchor;

  const km = polylineKm(coords);
  const straightKm = haversineKm(fromAnchor, toAnchor);
  if (straightKm > 0.001) {
    if (km > 1.6 * straightKm || km < 0.9 * straightKm) {
      throw new Error(
        `chainFromN02: chain length ${km.toFixed(3)}km is out of the sane [0.9x,1.6x] range of the straight-line distance ${straightKm.toFixed(3)}km`
      );
    }
  }

  return { coords, km: Math.round(km * 1000) / 1000 };
}

// Helper used inside chainFromN02: projects a point across a list of section
// polylines and returns the closest {distanceM, sectionIndex, insertIndex, t, point}.
function projectAcross(point, sections) {
  let best = null;
  sections.forEach((coords, secIdx) => {
    const proj = projectPointOntoPolyline(point, coords);
    if (best === null || proj.distanceM < best.distanceM) {
      // recompute t (fraction along the segment) for split ordering
      const a = coords[proj.insertIndex];
      const b = coords[proj.insertIndex + 1];
      const segLen = haversineM(a, b);
      const t = segLen === 0 ? 0 : haversineM(a, proj.point) / segLen;
      best = { distanceM: proj.distanceM, sectionIndex: secIdx, insertIndex: proj.insertIndex, point: proj.point, t };
    }
  });
  return best;
}

// Projects a point onto the N02 fragment graph for the given keys (used to
// resolve the anchor of a *new* station per the anchor rule). Returns the
// projected point (NOT the raw input) and the distance in metres.
export function projectOntoN02Keys(point, keys, maxM) {
  const sections = collectSections(keys);
  const best = projectAcross(point, sections);
  if (best.distanceM > maxM) {
    throw new Error(
      `projectOntoN02Keys: point ${JSON.stringify(point)} is ${best.distanceM.toFixed(1)}m from the nearest N02 track for keys ${keys.join(',')} (max ${maxM}m)`
    );
  }
  // atChainEnd: whether the closest point falls exactly at the start or end
  // vertex of its matched section (t==0 or t==1), i.e. the anchor projects
  // *beyond* that section's end, rather than laterally alongside its middle.
  const section = sections[best.sectionIndex];
  const atStart = best.insertIndex === 0 && best.t <= 1e-6;
  const atEnd = best.insertIndex === section.length - 2 && best.t >= 1 - 1e-6;
  return { point: best.point, distanceM: best.distanceM, atChainEnd: atStart || atEnd };
}

// Resolves a chain endpoint per the anchor rule's 40m/200m accommodation: if
// the anchor is within `tightM` of the N02 track, use it as-is (chainFromN02
// will force the chain to end exactly there). If it's between `tightM` and
// `looseM` away (the N02 track falls short of the real platform), snap the
// chain to the projected point and report a straight extension out to the
// real anchor instead.
export function resolveChainEndpoint(anchorPoint, keys, tightM, looseM) {
  const proj = projectOntoN02Keys(anchorPoint, keys, looseM);
  if (proj.distanceM <= tightM) {
    return { anchorForChain: anchorPoint, extension: null };
  }
  // The 40-200m accommodation is only valid when the anchor is genuinely
  // beyond the end of the N02 track (the track falls short of the real
  // platform) -- never for a lateral anchor that merely sits off to the
  // side of a section's middle, which would indicate a wrong/mismatched
  // track rather than a legitimate short extension.
  if (!proj.atChainEnd) {
    throw new Error(
      `resolveChainEndpoint: anchor ${JSON.stringify(anchorPoint)} is ${proj.distanceM.toFixed(1)}m from the N02 track for keys ${keys.join(',')} but does not project beyond a chain end (lateral offset) -- refusing to apply the straight-extension accommodation`
    );
  }
  return {
    anchorForChain: proj.point,
    extension: { point: anchorPoint, lengthM: haversineM(proj.point, anchorPoint) },
  };
}

// Builds a chain between two anchors, applying resolveChainEndpoint at both
// ends. Returns {coords, km, fromExtensionM, toExtensionM}.
export function buildChainWithExtensions({ keys, fromAnchor, toAnchor, tightM = 40, looseM = 200, snapM = 15 }) {
  const fromResolved = resolveChainEndpoint(fromAnchor, keys, tightM, looseM);
  const toResolved = resolveChainEndpoint(toAnchor, keys, tightM, looseM);
  const chain = chainFromN02({
    keys,
    fromAnchor: fromResolved.anchorForChain,
    toAnchor: toResolved.anchorForChain,
    fromMaxM: looseM,
    toMaxM: looseM,
    snapM,
  });
  let coords = chain.coords;
  if (fromResolved.extension) coords = [fromResolved.extension.point, ...coords];
  if (toResolved.extension) coords = [...coords, toResolved.extension.point];
  const km = Math.round(polylineKm(coords) * 1000) / 1000;
  return {
    coords,
    km,
    fromExtensionM: fromResolved.extension ? Math.round(fromResolved.extension.lengthM * 10) / 10 : 0,
    toExtensionM: toResolved.extension ? Math.round(toResolved.extension.lengthM * 10) / 10 : 0,
  };
}
