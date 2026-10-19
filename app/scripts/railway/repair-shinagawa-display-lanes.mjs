#!/usr/bin/env node
// Replay only the derived rulers affected by the Shinagawa display repair.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { partRowsForLine, applyStationLanePins } from './build-display-lanes.mjs';

const require = createRequire(import.meta.url);
const RailNetwork = require('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const SOBU = 'jp-東日本旅客鉄道-総武線-3';
const TOKAIDO = 'jp-東日本旅客鉄道-東海道線';
const TOHOKU = 'jp-東日本旅客鉄道-東北新幹線';
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const distance = (a, b) => Math.hypot((b[0]-a[0])*111320*Math.cos((a[1]+b[1])*Math.PI/360), (b[1]-a[1])*111320);
const measures = points => {
  const result = [0];
  for (let i = 1; i < points.length; i++) result.push(result.at(-1) + distance(points[i-1], points[i]));
  return result;
};

function repairTokyoTerminalLanes(lanes, beforePackage, afterPackage) {
  const line = afterPackage.lines.find(row => row.id === TOHOKU);
  if (!line) return lanes; // bounded Shinagawa-only callers
  assert.deepEqual(line.displayStationCoordinates?.['003766'], [139.7676701, 35.681109]);
  const parts = RailNetwork.displayPartsForLine(line);
  assert.equal(parts.length, 1);
  const updated = partRowsForLine(line, parts);
  const current = lanes.partsByRegion.jp.filter(row => row[0] === TOHOKU);
  if (equal(current, updated)) return lanes;
  assert.ok(beforePackage, 'A first Tokyo terminal replay requires the pre-repair package');
  const oldLine = beforePackage.lines.find(row => row.id === TOHOKU);
  const oldParts = RailNetwork.displayPartsForLine(oldLine);
  assert.deepEqual(current, partRowsForLine(oldLine, oldParts));
  assert.deepEqual(line.stations, oldLine.stations, 'Tokyo physical stations changed');
  assert.deepEqual(line.segments, oldLine.segments, 'Tokyo physical intervals or mileage changed');
  const source = RailNetwork.decodeIntervals(oldLine)[21];
  assert.deepEqual(line.displayIntervalCoordinates['21'], source.slice(0, -1));
  // Moving the station anchor disables the old runtime centroid warp. Its
  // synthetic supports occupy only the final 214 m; the restored source
  // supports and every earlier displayed vertex must survive unchanged.
  const oldPoints = oldParts[0], newPoints = parts[0];
  let prefix = 0;
  while (prefix < Math.min(oldPoints.length, newPoints.length) && equal(oldPoints[prefix], newPoints[prefix])) prefix++;
  assert.ok(prefix > 1);
  assert.deepEqual(oldPoints[prefix-1], [139.7680131, 35.6830091], 'Tokyo terminal approach moved beyond the reviewed source support');
  assert.deepEqual(newPoints.slice(prefix-1), source.slice(-5, -1));
  assert.ok(measures(oldPoints.slice(prefix-1)).at(-1) < 220 && measures(newPoints.slice(prefix-1)).at(-1) < 220,
    'Tokyo terminal regeneration exceeds the reviewed approach');
  const oldTotal = current[0][5], newTotal = updated[0][5];
  const end = value => {
    if (value === oldTotal) return newTotal;
    assert.ok(value <= measures(oldPoints)[prefix-1],
      'An interior Tokyo terminal lane boundary needs re-review');
    return value;
  };
  for (const row of lanes.byRegion.jp) if (row[0] === TOHOKU) {
    assert.equal(row[1], 0); row[2] = end(row[2]); row[3] = end(row[3]);
  }
  assert.equal(lanes.followsByRegion.jp.some(row => row[0] === TOHOKU || row[4] === TOHOKU), false,
    'A Tokyo terminal follow needs explicit scoped repair');
  for (const hub of lanes.hubReportByRegion?.jp || []) {
    // This excluded overlap diagnostic was sampled on the old centroid warp
    // inside the regenerated terminal approach. It does not drive runtime
    // lanes and has no exact retained support from which to remap its start.
    // Remove only that stale diagnostic; package provenance records why.
    hub.members = (hub.members || []).filter(member => !(hub.hubId === 'jp-tokyo' &&
      member.lineId === TOHOKU && member.excluded === 'separate-alignment' &&
      member.alongsideFrom === 676075 && member.alongsideTo === oldTotal));
    for (const member of hub.members || []) if (member.lineId === TOHOKU) {
      for (const key of ['from', 'to', 'alongsideFrom', 'alongsideTo'])
        if (Number.isFinite(member[key])) member[key] = end(member[key]);
    }
  }
  assert.equal((lanes.familyWindowsByRegion?.jp || []).some(row => JSON.stringify(row).includes(TOHOKU)), false);
  lanes.partsByRegion.jp = lanes.partsByRegion.jp.flatMap(row => row[0] === TOHOKU ? updated : [row]);
  return lanes;
}

export function repairShinagawaLanes(lanes, beforePackage, afterPackage) {
  const line = afterPackage.lines.find(row => row.id === SOBU);
  assert.ok(line, 'Missing Shinagawa passenger line');
  const passengerPairReview = afterPackage.geometrySource?.manualOverrides?.['shinagawa-normal-passenger-pair'];
  if (!passengerPairReview)
    assert.equal(line.displayStationCoordinates?.['004095'], undefined, 'Repair the package before its derived lanes');
  assert.equal(line.stationCircleOwnerByCode?.['004095'], undefined);
  assert.equal(line.stationLaneByCode?.['004095'], 0);
  const parts = RailNetwork.displayPartsForLine(line);
  assert.equal(parts.length, 1, 'Shinagawa part topology changed; re-review ruler repair');
  const updatedParts = partRowsForLine(line, parts);
  const currentParts = lanes.partsByRegion.jp.filter(row => row[0] === SOBU);
  assert.equal(currentParts.length, 1);
  // A replay with the already-updated part must never add the delta again.
  if (equal(currentParts, updatedParts)) return repairTokyoTerminalLanes(structuredClone(lanes), beforePackage, afterPackage);
  assert.ok(beforePackage, 'A first replay requires the pre-repair package (--before-package)');
  const oldLine = beforePackage.lines.find(row => row.id === SOBU);
  const oldParts = RailNetwork.displayPartsForLine(oldLine);
  assert.equal(oldParts.length, 1);
  assert.deepEqual(currentParts, partRowsForLine(oldLine, oldParts), 'Derived Sobu ruler does not match the supplied pre-repair package');
  const oldPoints = oldParts[0], newPoints = parts[0];
  const oldMeasures = measures(oldPoints), newMeasures = measures(newPoints);
  let prefix = 0, suffix = 0;
  while (prefix < Math.min(oldPoints.length, newPoints.length) && equal(oldPoints[prefix], newPoints[prefix])) prefix++;
  while (suffix < Math.min(oldPoints.length, newPoints.length)-prefix &&
    equal(oldPoints.at(-suffix-1), newPoints.at(-suffix-1))) suffix++;
  assert.ok(prefix > 1 && suffix > 1, 'No exact retained prefix/tail for the Shinagawa ruler repair');
  const oldTail = oldPoints.length-suffix, newTail = newPoints.length-suffix;
  const delta = newMeasures[newTail]-oldMeasures[oldTail];
  // Compare every shared support's ruler shift, rather than assuming that a
  // nearby source curve or a changed fork has the same downstream measure.
  for (let i = 0; i < suffix; i++)
    assert.ok(Math.abs(newMeasures[newTail+i]-oldMeasures[oldTail+i]-delta) < 1e-6);
  const remap = value => {
    if (value <= oldMeasures[prefix-1]+0.1) return value;
    assert.ok(value >= oldMeasures[oldTail]-0.1, `Measure ${value} falls inside the changed Shinagawa approach; re-review it`);
    return value+delta;
  };
  const result = structuredClone(lanes);
  const follows = result.followsByRegion.jp;
  const obsolete = follows.filter(row => row[0] === SOBU && row[1] === 0 &&
    row[2] === 6675 && row[3] === 7875 && row[4] === TOKAIDO && row[5] === 0);
  assert.equal(obsolete.length, passengerPairReview ? 0 : 1,
    'Unexpected Shinagawa surface-follow repair stage');
  result.followsByRegion.jp = follows.filter(row => !obsolete.includes(row)).map(row => {
    if (row[0] === SOBU && row[1] === 0) { row[2] = remap(row[2]); row[3] = remap(row[3]); }
    if (row[4] === SOBU && row[5] === 0) { row[6] = remap(row[6]); row[7] = remap(row[7]); }
    return row;
  });
  let sourceRows = result.byRegion.jp.filter(row => row[0] === SOBU);
  if (passengerPairReview) {
    // Remove the previously applied station pin before measuring its new
    // representative centre. Rejoin only the two surrounding equal lanes;
    // their outer limits lie on the retained prefix and southern tail.
    const anchor = oldLine.displayStationCoordinates?.['004095'] ||
      oldLine.stations.find(row => row[0] === '004095').slice(2, 4);
    const vertex = oldPoints.findIndex(point => equal(point, anchor));
    assert.ok(vertex >= 0);
    const from = Number((oldMeasures[vertex]-300).toFixed(1));
    const to = Number((oldMeasures[vertex]+300).toFixed(1));
    const pin = sourceRows.findIndex(row => row[2] === from && row[3] === to && row[4] === 0);
    assert.ok(pin > 0 && pin+1 < sourceRows.length, 'Missing previous Shinagawa station pin');
    const left = sourceRows[pin-1], right = sourceRows[pin+1];
    assert.equal(left[3], from); assert.equal(right[2], to); assert.equal(left[4], right[4]);
    sourceRows.splice(pin-1, 3, [SOBU, 0, left[2], right[3], left[4]]);
  }
  let rows = sourceRows.map(row => {
    assert.equal(row[1], 0);
    row[2] = remap(row[2]); row[3] = remap(row[3]);
    return row;
  });
  // Apply only this newly reviewed station pin. Tokyo/Shimbashi and every
  // unrelated line retain their existing lane windows byte for byte.
  rows = applyStationLanePins({ lines: [{ ...line, stationLaneByCode: { '004095': 0 } }] }, updatedParts, rows);
  let inserted = false;
  result.byRegion.jp = result.byRegion.jp.flatMap(row => {
    if (row[0] !== SOBU) return [row];
    if (inserted) return [];
    inserted = true;
    return rows;
  });
  result.partsByRegion.jp = result.partsByRegion.jp.flatMap(row => row[0] === SOBU ? updatedParts : [row]);
  // Hub rows outside the changed throat keep exact prefix measures; fail
  // closed if a future policy puts a hub edge inside the changed geometry.
  for (const hub of result.hubReportByRegion?.jp || []) {
    if (passengerPairReview) hub.members = (hub.members || []).filter(member =>
      !(member.lineId === SOBU && member.partIndex === 0 && member.slot === -0.5 &&
        member.from === 5225 && Math.abs(member.to-8383.462605357669) < 1e-6));
    for (const member of hub.members || []) if (member.lineId === SOBU && member.partIndex === 0) {
      member.from = remap(member.from); member.to = remap(member.to);
    }
  }
  const sobuFamilies = (result.familyWindowsByRegion?.jp || []).filter(row => row[0] === SOBU);
  assert.ok(sobuFamilies.length <= 1, 'Unexpected Sobu family window count');
  for (const row of sobuFamilies) {
    // The later Nakamagome display window is south of this accepted Osaki
    // owner span. Reuse this ruler, but admit only the known unchanged prefix
    // family; an interior or new family still requires its own review.
    assert.deepEqual(row, [SOBU, 0, 9430.79295925673, 10309.280524222238, 0,
      '東日本旅客鉄道:東海道線'], 'Unexpected Sobu family window');
    const from = remap(row[2]), to = remap(row[3]);
    assert.equal(from, row[2], 'Sobu family must remain on the retained prefix');
    assert.equal(to, row[3], 'Sobu family must remain on the retained prefix');
    row[2] = from; row[3] = to;
  }
  return repairTokyoTerminalLanes(result, beforePackage, afterPackage);
}

// Only reviewed Osaki passenger display inputs are used here. Physical source
// intervals and traversal rights are never read back from these derived rows.
export function repairOsakiLanes(lanes, beforePackage, afterPackage) {
  const base = 'jp-東日本旅客鉄道-大崎支線', pair = base+'-p1';
  const electric = 'jp-東日本旅客鉄道-山手線';
  const rinkai = 'jp-東京臨海高速鉄道-臨海副都心線';
  const affected = new Set([base, pair, electric, rinkai]);
  const lines = new Map(afterPackage.lines.map(line => [line.id, line]));
  assert.ok(lines.has(base) && lines.has(pair) && lines.has(SOBU), 'Missing Osaki reviewed passenger rows');
  const parts = new Map([...affected, SOBU].filter(id => lines.has(id))
    .map(id => [id, RailNetwork.displayPartsForLine(lines.get(id))]));
  const metric = (id, part = 0) => measures(parts.get(id)[part]);
  const total = (id, part = 0) => metric(id, part).at(-1);
  assert.deepEqual(lanes.partsByRegion.jp.filter(row => row[0] === SOBU),
    partRowsForLine(lines.get(SOBU), parts.get(SOBU)),
    'Replay the canonical Sobu ruler before consuming Osaki shared tails');
  const at = (id, part, coordinate) => {
    const index = parts.get(id)[part].findIndex(point => equal(point, coordinate));
    assert.ok(index >= 0, `Reviewed Osaki support missing from ${id}#${part}`);
    return metric(id, part)[index];
  };
  const tails = new Map([base, pair].map(id => {
    const definition = lines.get(id).southernBranchTopology?.displaySharedTail;
    assert.equal(definition?.canonicalLineId, SOBU);
    assert.equal(definition.canonicalIntervalIndex, 2);
    assert.equal(definition.branchPartIndex, 0);
    assert.equal(definition.lanePolicy, 'inherit-canonical-shared-span');
    assert.equal(definition.routing, false);
    assert.equal(parts.get(id).length, 1, 'Local station representative retires both dangling display leads');
    assert.deepEqual(parts.get(id)[0][0], lines.get(electric).stations[1].slice(2,4));
    const ownFrom = at(id, 0, definition.fromCoordinate), ownTo = at(id, 0, definition.toCoordinate);
    const canonFrom = at(SOBU, 0, definition.fromCoordinate), canonTo = at(SOBU, 0, definition.toCoordinate);
    const ownPoints = parts.get(id)[0], canonical = parts.get(SOBU)[0];
    assert.deepEqual(ownPoints.slice(ownPoints.findIndex(point => equal(point, definition.fromCoordinate))),
      canonical.slice(canonical.findIndex(point => equal(point, definition.fromCoordinate)),
        canonical.findIndex(point => equal(point, definition.toCoordinate))+1),
      'Shared tail must be the exact reviewed canonical suffix');
    assert.ok(ownFrom > 600 && ownTo > ownFrom);
    const covering = lanes.byRegion.jp.filter(row => row[0] === SOBU && row[1] === 0 &&
      row[2] <= canonFrom && row[3] >= canonTo);
    assert.equal(covering.length, 1, 'Shared Sobu tail must have one existing owner lane');
    assert.equal(covering[0][4], -0.5, 'Retain the reviewed Sobu owner offset');
    return [id, { ownFrom, ownTo, canonFrom, canonTo, lane: covering[0][4] }];
  }));
  const updated = [...affected].filter(id => lines.has(id)).flatMap(id => partRowsForLine(lines.get(id), parts.get(id)));
  const current = lanes.partsByRegion.jp.filter(row => affected.has(row[0]));
  const alreadyUpdated = [...affected].every(id =>
    equal(current.filter(row => row[0] === id), updated.filter(row => row[0] === id)));
  if (!alreadyUpdated) {
    assert.ok(beforePackage, 'A first Osaki lane repair requires --before-package');
    for (const id of affected) {
      const before = beforePackage.lines.find(line => line.id === id);
      const after = lines.get(id);
      if (!before || !after) continue;
      assert.deepEqual(before.stations, after.stations, `${id} physical stations changed`);
      assert.deepEqual(before.segments, after.segments, `${id} physical intervals changed`);
      assert.deepEqual(lanes.partsByRegion.jp.filter(row => row[0] === id),
        partRowsForLine(before, RailNetwork.displayPartsForLine(before)), `${id} old native ruler mismatch`);
    }
  }
  const result = structuredClone(lanes);
  // Replace affected rows in their original position, preserving every
  // unrelated ruler / region and producing stable order on repeated replay.
  const replace = (rows, ids, replacements) => {
    const emitted = new Set();
    const output = rows.flatMap(row => {
      if (!ids.has(row[0])) return [row];
      if (emitted.has(row[0])) return [];
      emitted.add(row[0]);
      return replacements.filter(candidate => candidate[0] === row[0]);
    });
    for (const row of replacements) if (!emitted.has(row[0])) output.push(row);
    return output;
  };
  result.partsByRegion.jp = replace(result.partsByRegion.jp, affected, updated);
  // Removing two collinear electric-line aliases changes vertex references,
  // not the corridor or its ruler. Reject an unrelated electric shape edit.
  if (!alreadyUpdated && lines.has(electric)) {
    const before = beforePackage.lines.find(line => line.id === electric);
    const oldParts = RailNetwork.displayPartsForLine(before), newParts = parts.get(electric);
    assert.equal(oldParts.length, newParts.length);
    for (let part = 0; part < oldParts.length; part++) {
      const oldMeasures = measures(oldParts[part]), newMeasures = measures(newParts[part]);
      for (const [index, point] of newParts[part].entries()) {
        const oldIndex = oldParts[part].findIndex(candidate => equal(candidate, point));
        assert.ok(oldIndex >= 0 && Math.abs(oldMeasures[oldIndex]-newMeasures[index]) < 0.01,
          'Electric alias removal changed the retained ruler');
      }
    }
  }
  // Rinkai keeps its separate company/lane profile. Only its short terminal
  // transition changed; map every downstream boundary on the retained tail.
  if (!alreadyUpdated && lines.has(rinkai)) {
    const before = beforePackage.lines.find(line => line.id === rinkai);
    const oldPoints = RailNetwork.displayPartsForLine(before)[0], newPoints = parts.get(rinkai)[0];
    const oldMeasures = measures(oldPoints), newMeasures = measures(newPoints);
    let suffix = 0;
    while (suffix < Math.min(oldPoints.length, newPoints.length) && equal(oldPoints.at(-suffix-1), newPoints.at(-suffix-1))) suffix++;
    assert.ok(suffix > 1, 'Rinkai transition has no exact retained tail');
    const oldStart = oldPoints.length-suffix, newStart = newPoints.length-suffix;
    // A long retained edge can put the first unchanged support well beyond
    // 200 m. Bound the final changed support, not that following edge's end.
    assert.ok(oldMeasures[Math.max(0, oldStart-1)] < 200 && newMeasures[Math.max(0, newStart-1)] < 215,
      'Rinkai display change exceeds the bounded station transition');
    const delta = newMeasures[newStart]-oldMeasures[oldStart];
    const remap = value => {
      if (value === 0) return 0;
      assert.ok(value >= oldMeasures[oldStart], 'Rinkai boundary inside changed approach needs review');
      return value+delta;
    };
    for (const row of result.byRegion.jp) if (row[0] === rinkai) {
      assert.equal(row[1], 0); row[2] = remap(row[2]); row[3] = remap(row[3]);
    }
    assert.equal(result.followsByRegion.jp.some(row => row[0] === rinkai || row[4] === rinkai), false,
      'A Rinkai follow needs separate ruler repair');
  }
  const branches = new Set([base, pair]);
  const stems = new Map([base, pair].map(id => {
    const stem = lines.get(id).southernBranchTopology.displayStationStem;
    assert.equal(stem.canonicalLineId, electric);
    assert.equal(stem.routing, false);
    return [id, { ownTo: at(id, 0, stem.toCoordinate),
      canonFrom: at(electric, 0, stem.toCoordinate), canonTo: at(electric, 0, stem.fromCoordinate) }];
  }));
  const branchRows = [base, pair].flatMap(id => {
    // The final stroke applies a 300 m lane ramp before family clipping.
    // Keep that ramp between the two owner handoffs, rather than allowing
    // it to reopen the common Yamanote merge at only 215 m from the station.
    const transition = (stems.get(id).ownTo + tails.get(id).ownFrom) / 2;
    return [[id, 0, 0, transition, 0],
      [id, 0, transition, total(id), tails.get(id).lane]];
  });
  result.byRegion.jp = replace(result.byRegion.jp, branches, branchRows);
  const baseTail = tails.get(base), pairTail = tails.get(pair);
  const branchFollows = [
    ...[base, pair].map(id => { const stem = stems.get(id); return [id, 0, 0, stem.ownTo, electric, 0, stem.canonTo, stem.canonFrom]; }),
    [pair, 0, stems.get(pair).ownTo, pairTail.ownFrom, base, 0, stems.get(base).ownTo, baseTail.ownFrom],
    ...[base, pair].map(id => { const tail = tails.get(id); return [id, 0, tail.ownFrom, tail.ownTo, SOBU, 0, tail.canonFrom, tail.canonTo]; }),
  ];
  result.followsByRegion.jp = result.followsByRegion.jp.filter(row => !branches.has(row[0]) && !branches.has(row[4]));
  result.followsByRegion.jp.push(...branchFollows);
  const branchGroup = '東日本旅客鉄道:大崎支線';
  const sharedGroup = '東日本旅客鉄道:東海道線';
  const family = result.familyWindowsByRegion.jp.filter(row => !branches.has(row[0]) &&
    !(row[0] === electric && row[5] === branchGroup) && row[5] !== '東日本旅客鉄道:大崎駅代表');
  // Two independently surveyed directions are one JR display corridor. The
  // northern base body owns its ink; both southern tails belong directly to
  // Sobu. No recursive follow or cross-company family collapse is required.
  const stationGroup = branchGroup;
  family.push([electric, 0, stems.get(base).canonFrom, stems.get(base).canonTo, 0, stationGroup],
    ...[base, pair].map(id => [id, 0, 0, stems.get(id).ownTo, 1, stationGroup]),
    [base, 0, stems.get(base).ownTo, baseTail.ownFrom, 0, branchGroup],
    [pair, 0, stems.get(pair).ownTo, pairTail.ownFrom, 1, branchGroup],
    ...[base, pair].map(id => { const tail = tails.get(id); return [id, 0, tail.ownFrom, tail.ownTo, 1, sharedGroup]; }));
  // Reconcile the new owner span with existing same-group Sobu owner windows,
  // preserving other roles/groups. Avoid overlapping landlord records.
  const sharedOwners = family.filter(row => row[0] === SOBU && row[1] === 0 && row[4] === 0 && row[5] === sharedGroup);
  const spans = sharedOwners.map(row => [row[2], row[3]]);
  spans.push([Math.min(baseTail.canonFrom, pairTail.canonFrom), Math.max(baseTail.canonTo, pairTail.canonTo)]);
  spans.sort((a, b) => a[0]-b[0]);
  const merged = [];
  for (const span of spans) {
    const previous = merged.at(-1);
    if (previous && span[0] <= previous[1]) previous[1] = Math.max(previous[1], span[1]);
    else merged.push(span.slice());
  }
  result.familyWindowsByRegion.jp = family.filter(row => !sharedOwners.includes(row));
  result.familyWindowsByRegion.jp.push(...merged.map(span => [SOBU, 0, ...span, 0, sharedGroup]));
  return result;
}

function main(args = process.argv.slice(2)) {
  const option = name => {
    const index = args.indexOf(name);
    if (index < 0) return undefined;
    assert.ok(args[index+1] && !args[index+1].startsWith('--'), `Missing ${name} value`);
    return args[index+1];
  };
  const packagePath = option('--package') || path.join(ROOT, 'public/rail/jp-2025.json');
  const lanesPath = option('--lanes') || path.join(ROOT, 'public/rail/display-lanes.json');
  const beforePath = option('--before-package');
  const lanesText = fs.readFileSync(lanesPath, 'utf8');
  const before = beforePath ? JSON.parse(fs.readFileSync(beforePath, 'utf8')) : null;
  const after = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
  let result = repairShinagawaLanes(JSON.parse(lanesText), before, after);
  if (args.includes('--osaki')) result = repairOsakiLanes(result, before, after);
  const output = `${JSON.stringify(result)}\n`;
  if (option('--output') || output !== lanesText) fs.writeFileSync(option('--output') || lanesPath, output);
  console.log(`Shinagawa${args.includes('--osaki') ? ' / Osaki' : ''} derived display lanes are current`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
