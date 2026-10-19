import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import { repairPackage, proposeDependencies, applyPreparedWrites, DEPENDENCY_PATHS, IDENTITY } from '../repair-tsurumi-passenger-arms.mjs';
import { decodeIntervals } from '../jp-manual-corrections/geo.mjs';
const network = createRequire(import.meta.url)('../../../public/rail-network.js');
const input = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json', import.meta.url)));
const sections = JSON.parse(fs.readFileSync(new URL('../../../data/rail-sections.json', import.meta.url)));
const stations = JSON.parse(fs.readFileSync(new URL('../../../data/stations.json', import.meta.url)));
const evidence = JSON.parse(fs.readFileSync(new URL('../tsurumi-passenger-arm-evidence.json', import.meta.url)));
const affected = new Set(evidence.arms.map(arm => arm.id));
// Reconstruct the pinned old arms so this regression survives later integration.
for (const [id, line] of Object.entries(evidence.oldBranches)) {
  const index = input.lines.findIndex(row => row.id === id);
  input.stats.structure += (line.structure?.length || 0) - (input.lines[index].structure?.length || 0);
  input.lines[index] = structuredClone(line);
}
const find = (pkg, id) => pkg.lines.find(row => row.id === id);
const repaired = () => repairPackage(input, sections, stations, evidence);

test('Tsurumi passenger arms use Anzen and the surveyed Asano branch platform', () => {
  const result = repaired(), umi = find(result, IDENTITY + '-2'), okawa = find(result, IDENTITY + '-3');
  assert.deepEqual(okawa.stations.map(row => row[0]), ['004522', '004540']);
  assert.deepEqual(umi.stations.map(row => row[0]), ['004531', '004547', '004564']);
  assert.deepEqual(umi.stations[0].slice(2, 4), [139.695745, 35.497285]);
  assert.deepEqual(find(result, IDENTITY), find(input, IDENTITY));
  assert.equal(result.stats.structure, input.stats.structure - 1);
  for (const key of Object.keys(input.stats).filter(key => key !== 'structure'))
    assert.equal(result.stats[key], input.stats[key]);
  assert(!okawa.structure, 'obsolete chainage cannot be carried into the longer Anzen arm');
  for (const arm of [umi, okawa]) {
    assert.equal(arm.railwayIdentity, IDENTITY);
    const intervals = decodeIntervals(arm);
    for (let i = 0; i < intervals.length; i++) {
      assert.deepEqual(intervals[i].coords[0], arm.stations[i].slice(2, 4));
      assert.deepEqual(intervals[i].coords.at(-1), arm.stations[i + 1].slice(2, 4));
    }
    const display = network.displayPartsForLine(arm).flat();
    assert.deepEqual(display[0], arm.stations[0].slice(2, 4));
    assert.deepEqual(display.at(-1), arm.stations.at(-1).slice(2, 4));
  }
});

test('each interior edge and junction remains exactly surveyed without an invented diagonal', () => {
  const result = repaired();
  for (const arm of evidence.arms) {
    const line = find(result, arm.id);
    const intervals = decodeIntervals(line);
    for (let n = 0; n < intervals.length; n++) {
      const edges = new Set(arm.intervals[n].flatMap(([index]) => {
        const points = sections.features[index].geometry.coordinates;
        return points.slice(1).flatMap((point, i) => [JSON.stringify([points[i], point]), JSON.stringify([point, points[i]])]);
      }));
      const points = intervals[n].coords;
      for (let i = 2; i < points.length - 1; i++)
        assert(edges.has(JSON.stringify([points[i - 1], points[i]])), 'exact survey interior edge');
    }
  }
  const okawa = find(result, IDENTITY + '-3').segments[0][2];
  assert(okawa.some(point => JSON.stringify(point) === JSON.stringify([139.70555, 35.50155])));
  assert(!okawa.some(point => JSON.stringify(point) === JSON.stringify([139.70619, 35.50181])));
});

test('bounded replay preserves unrelated records, is idempotent and refuses changed evidence', () => {
  const before = structuredClone(input), result = repaired();
  assert.deepEqual(input, before);
  assert.deepEqual(result.lines.filter(row => !affected.has(row.id)), input.lines.filter(row => !affected.has(row.id)));
  for (const key of Object.keys(input).filter(key => !['lines', 'geometrySource', 'stats'].includes(key)))
    assert.deepEqual(result[key], input[key]);
  assert.deepEqual(repairPackage(result, sections, stations, evidence), result);
  const changedSections = structuredClone(sections);
  changedSections.features[16124].geometry.coordinates.at(-1)[0] += 0.00001;
  assert.throws(() => repairPackage(input, changedSections, stations, evidence), /source changed/);
  const changedStations = structuredClone(stations);
  changedStations.features[7599].properties.display_point[1] += 0.00001;
  assert.throws(() => repairPackage(input, sections, changedStations, evidence), /source changed/);
  const changedInput = structuredClone(input);
  find(changedInput, IDENTITY + '-3').stations[0][0] = 'unknown';
  assert.throws(() => repairPackage(changedInput, sections, stations, evidence), /branch source changed/);
  assert.equal(result.geometrySource.manualOverrides['tsurumi-passenger-arms'].businessIdentity.branch3, '武蔵白石–大川');
  assert.equal(result.geometrySource.manualOverrides['tsurumi-passenger-arms'].businessIdentity.passengerRoutingEffectiveFrom, null);
});

test('dependency candidates retire only stale follows and reuse exact Anzen identity evidence', () => {
  const deps = Object.fromEntries(Object.entries(DEPENDENCY_PATHS).map(([key, relative]) =>
    [key, JSON.parse(fs.readFileSync(new URL('../../../' + relative, import.meta.url)))]));
  const before = structuredClone(deps), result = proposeDependencies(repaired(), deps, evidence);
  assert.deepEqual(deps, before);
  const okawa = IDENTITY + '-3', oldKey = okawa + ':004517', newKey = okawa + ':004522', sourceKey = IDENTITY + ':004522';
  assert(!result.lanes.followsByRegion.jp.some(row => affected.has(row[0]) || affected.has(row[4])));
  const newParts = result.lanes.partsByRegion.jp.filter(row => affected.has(row[0]));
  assert.equal(newParts.length, 2);
  assert.deepEqual(newParts.map(row => row.slice(1, 5)), [[0, 0, 1, 29], [0, 0, 0, 36]]);
  assert(!result.names.byCode[oldKey]);
  assert.deepEqual(result.names.byCode[newKey], result.names.byCode[sourceKey]);
  assert(!result.english.byCountry.jp.byCode['004517'].memberships.some(row => row.lineId === okawa));
  const member = result.english.byCountry.jp.byCode['004522'].memberships.find(row => row.lineId === okawa);
  assert.equal(member.seq, 0);
  assert.deepEqual(member.identityEvidence, deps.english.byCountry.jp.byCode['004522'].memberships.find(row => row.lineId === IDENTITY).identityEvidence);
  for (const key of ['englishSource', 'kanaSource']) {
    assert(!result[key].byLineStation[oldKey]);
    assert.deepEqual(result[key].byLineStation[newKey].identityEvidence, deps[key].byLineStation[sourceKey].identityEvidence);
    assert.deepEqual(result[key].coverage, deps[key].coverage);
  }
  assert.equal(result.coverage.regions.jp.memberships.find(row => row.key === newKey).group, '004522');
  assert.deepEqual(result.catalog, deps.catalog);
  assert.deepEqual(result.renderGroups, deps.renderGroups);
  assert.deepEqual(proposeDependencies(repaired(), result, evidence), result);
  const stale = structuredClone(deps);
  stale.lanes.byRegion.jp.push([okawa, 0, 100, 200, 0.5]);
  assert.throws(() => proposeDependencies(repaired(), stale, evidence), /measured reference/);
});

test('apply checks all owned destination and raw-source bytes before the first write', () => {
  const directory = fs.mkdtempSync('/private/tmp/jtm-tsurumi-apply-test-');
  try {
    const packagePath = directory + '/package.json', lanesPath = directory + '/lanes.json', sourcePath = directory + '/source.json';
    fs.writeFileSync(packagePath, 'old package\n');
    fs.writeFileSync(lanesPath, 'old lanes\n');
    fs.writeFileSync(sourcePath, 'pinned source\n');
    const writes = [{ path: packagePath, before: 'old package\n', after: 'new package\n' },
                    { path: lanesPath, before: 'old lanes\n', after: 'new lanes\n' }];
    const inputs = [...writes.map(({ path, before }) => ({ path, before })),
                    { path: sourcePath, before: 'pinned source\n' }];
    fs.writeFileSync(sourcePath, 'concurrent source edit\n');
    assert.throws(() => applyPreparedWrites(writes, inputs), /input changed before apply/);
    assert.equal(fs.readFileSync(packagePath, 'utf8'), 'old package\n');
    assert.equal(fs.readFileSync(lanesPath, 'utf8'), 'old lanes\n');
    fs.writeFileSync(sourcePath, 'pinned source\n');
    fs.writeFileSync(lanesPath, 'concurrent lane edit\n');
    assert.throws(() => applyPreparedWrites(writes, inputs), /input changed before apply/);
    assert.equal(fs.readFileSync(packagePath, 'utf8'), 'old package\n');
    assert.equal(fs.readFileSync(lanesPath, 'utf8'), 'concurrent lane edit\n');
    fs.writeFileSync(lanesPath, 'old lanes\n');
    assert.throws(() => applyPreparedWrites(writes, inputs.filter(row => row.path !== lanesPath)), /missing its exact input snapshot/);
    assert.equal(fs.readFileSync(packagePath, 'utf8'), 'old package\n');
    applyPreparedWrites(writes, inputs);
    assert.equal(fs.readFileSync(packagePath, 'utf8'), 'new package\n');
    assert.equal(fs.readFileSync(lanesPath, 'utf8'), 'new lanes\n');
    assert.equal(fs.readFileSync(sourcePath, 'utf8'), 'pinned source\n');
  } finally { fs.rmSync(directory, { recursive: true }); }
});
