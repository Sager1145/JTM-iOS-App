import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { repairPackage, repairDependencies } from '../repair-keiyo-passenger-arms.mjs';

const input = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json', import.meta.url)));
const raw = JSON.parse(fs.readFileSync(new URL('../../../data/rail-sections.json', import.meta.url)));
const evidence = JSON.parse(fs.readFileSync(new URL('../keiyo-passenger-arm-evidence.json', import.meta.url)));
const identity = 'jp-東日本旅客鉄道-京葉線';
const affected = new Set([identity + '-2', identity + '-3']);
if (input.lines.some(line => line.id === identity + '-3')) {
  input.lines = input.lines.filter(line => line.id !== identity + '-3');
  input.lines[input.lines.findIndex(line => line.id === identity + '-2')] = structuredClone(evidence.oldBranch);
  input.stats.lines--; input.stats.intervals--; input.stats.stations -= 2; input.stats.structure += 5;
  delete input.geometrySource.manualOverrides['keiyo-passenger-arms'];
}
const find = (pkg, id) => pkg.lines.find(line => line.id === id);
const repaired = () => repairPackage(input, raw, evidence);

test('Keiyo has both passenger arms without a false Futamata branch stop', () => {
  const result = repaired();
  for (const [suffix, destination] of [['-2', '003761'], ['-3', '003870']]) {
    const arm = find(result, identity + suffix);
    assert(arm, 'both passenger arms must exist');
    assert.deepEqual(arm.stations.map(row => row[0]), ['003547', destination]);
    assert.equal(arm.railwayIdentity, identity);
    assert(!arm.stations.some(row => row[0] === '003682'));
    assert.equal(arm.segments[0][1], 0);
    assert.deepEqual(arm.segments[0][2][0], arm.stations[0].slice(2, 4));
    assert.deepEqual(arm.segments[0][2].at(-1), arm.stations[1].slice(2, 4));
    assert(!arm.structure, 'invalid old terminal structure measures cannot carry forward');
  }
  assert.deepEqual(find(result, identity), find(input, identity));
});

test('the two arms retain exact surveyed limbs and introduce no interior seams', () => {
  const result = repaired();
  const east = find(result, identity + '-2').segments[0][2];
  const west = find(result, identity + '-3').segments[0][2];
  const northFork = [139.95631, 35.69447];
  const eastFork = [139.9611, 35.69164];
  const westFork = [139.95346, 35.68953];
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  assert(east.some(point => same(point, eastFork)));
  assert(west.some(point => same(point, westFork)));
  assert(!west.some(point => same(point, eastFork)));
  const north = east.findIndex(point => same(point, northFork));
  assert.deepEqual(east.slice(0, north + 1), west.slice(0, north + 1));
  for (const [points, features] of [[east, [14124,14126,14132,14135,14127]], [west, [14124,14126,14147,14150,14152]]]) {
    const edges = new Set(features.flatMap(index => {
      const path = raw.features[index].geometry.coordinates;
      return path.slice(1).flatMap((point, i) => [JSON.stringify([path[i], point]), JSON.stringify([point, path[i]])]);
    }));
    for (let i = 2; i < points.length - 1; i++)
      assert(edges.has(JSON.stringify([points[i-1], points[i]])), 'every interior edge must be an exact source survey edge');
  }
});

test('replay preserves unrelated data and is idempotent without mutating input', () => {
  const before = structuredClone(input), result = repaired();
  assert.deepEqual(input, before);
  assert.deepEqual(result.lines.filter(line => !affected.has(line.id)), input.lines.filter(line => !affected.has(line.id)));
  for (const key of Object.keys(input).filter(key => !['lines', 'geometrySource', 'stats'].includes(key)))
    assert.deepEqual(result[key], input[key]);
  assert.equal(result.stats.lines, input.stats.lines + 1);
  assert.equal(result.stats.intervals, input.stats.intervals + 1);
  assert.equal(result.stats.stations, input.stats.stations + 2);
  assert.equal(result.stats.structure, input.stats.structure - 5);
  assert.deepEqual(result.geometrySource.providers, input.geometrySource.providers);
  assert.deepEqual(result.geometrySource.osmGeometry, input.geometrySource.osmGeometry);
  assert.deepEqual(repairPackage(result, raw, evidence), result);
});

test('changed survey joins or unrelated branch-3 identities stop the replay', () => {
  const changed = structuredClone(raw);
  changed.features[14132].geometry.coordinates[0][0] += 0.00001;
  assert.throws(() => repairPackage(input, changed, evidence), /source changed/);
  const collision = structuredClone(input);
  collision.lines.push({ id: identity + '-3', stations: [] });
  assert.throws(() => repairPackage(collision, raw, evidence), /branch.*changed|collision/);
});

test('scoped dependency replay refreshes native parts and reuses existing verified station identity', () => {
  const paths = {
    lanes: '../../../public/rail/display-lanes.json', renderGroups: '../../../public/rail/jp-render-groups.json',
    names: '../../../data/station-names.json', english: '../../../data/station-english.json',
    coverage: '../../../data/station-names-coverage.json',
    catalog: '../../../../ios/RailKit/Sources/RailCore/Resources/line-service-catalog.json',
  };
  const deps = Object.fromEntries(Object.entries(paths).map(([key, value]) => [key,
    JSON.parse(fs.readFileSync(new URL(value, import.meta.url)))]));
  const result = repairDependencies(repaired(), deps, evidence);
  const rows = result.lanes.partsByRegion.jp.filter(row => affected.has(row[0]));
  assert.equal(rows.length, 2);
  assert.deepEqual(rows.map(row => row[4]), [65, 74]);
  assert(rows.every(row => row[1] === 0 && row[2] === 0 && row[3] === 0));
  assert(!result.lanes.followsByRegion.jp.some(row => affected.has(row[0]) || affected.has(row[4])));
  assert.equal(result.renderGroups.byLineId[identity + '-3'], result.renderGroups.byLineId[identity]);
  const key = (id, code) => id + ':' + code;
  assert(!result.names.byCode[key(identity + '-2', '003682')]);
  assert.deepEqual(result.names.byCode[key(identity + '-2', '003761')], result.names.byCode[key(identity, '003761')]);
  assert.deepEqual(result.names.byCode[key(identity + '-3', '003870')], result.names.byCode[key(identity, '003870')]);
  const codes = result.english.byCountry.jp.byCode;
  assert(!codes['003682'].memberships.some(row => affected.has(row.lineId)));
  for (const [code, id] of [['003761', identity + '-2'], ['003547', identity + '-3'], ['003870', identity + '-3']]) {
    const member = codes[code].memberships.find(row => row.lineId === id);
    assert(member && member.status === 'official_verified');
    const source = codes[code].memberships.find(row => row.lineId === (code === '003547' ? identity + '-2' : identity));
    assert.deepEqual(member.identityEvidence, source.identityEvidence);
  }
  assert.equal(result.catalog.lines.find(row => row.lineID === identity + '-3').coverage, 'unknown');
  const unrelated = row => !affected.has(row[0]);
  assert.deepEqual(result.lanes.partsByRegion.jp.filter(unrelated), deps.lanes.partsByRegion.jp.filter(unrelated));
  assert.deepEqual(result.names.byName, deps.names.byName);
  assert.deepEqual(result.catalog.trips, deps.catalog.trips);
  assert.deepEqual(repairDependencies(repaired(), result, evidence), result);
  const stale = structuredClone(deps);
  stale.lanes.byRegion.jp.push([identity + '-2', 0, 100, 200, 0.5]);
  assert.throws(() => repairDependencies(repaired(), stale, evidence), /measured reference/);
});
