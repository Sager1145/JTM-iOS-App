#!/usr/bin/env node
// Default is a scratch candidate. --apply explicitly integrates scoped records
// after checking every read input and owned destination against its exact bytes.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { encodeIntervals, projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { partRowsForLine } from './build-display-lanes.mjs';
export const IDENTITY = 'jp-東日本旅客鉄道-鶴見線';
const network = createRequire(import.meta.url)('../../public/rail-network.js');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const EVIDENCE = path.join(ROOT, 'scripts/railway/tsurumi-passenger-arm-evidence.json');
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const same = (a, b) => a[0] === b[0] && a[1] === b[1];
const pretty = value => JSON.stringify(value, null, 2) + '\n';
const hash = value => createHash('sha256').update(value).digest('hex');
export const DEPENDENCY_PATHS = {
  lanes: 'public/rail/display-lanes.json', names: 'data/station-names.json',
  english: 'data/station-english.json', coverage: 'data/station-names-coverage.json',
  englishSource: 'data/station-english-verified-jp-east.json',
  kanaSource: 'data/station-name-sources/jp-kana-evidence.json',
  renderGroups: 'public/rail/jp-render-groups.json',
  catalog: '../ios/RailKit/Sources/RailCore/Resources/line-service-catalog.json',
  through: '../ios/RailKit/Sources/RailCore/Resources/japan-through-services.json',
};

// Produces scoped dependency candidates in memory. No published writes, no
// guessed replacement follows, and no permission inferred from render identity.
export function proposeDependencies(pkg, input, evidence = JSON.parse(fs.readFileSync(EVIDENCE))) {
  const result = structuredClone(input), umi = IDENTITY + '-2', okawa = IDENTITY + '-3';
  const ids = new Set([umi, okawa]);
  const parts = evidence.arms.flatMap(arm => {
    const line = pkg.lines.find(row => row.id === arm.id);
    assert(line, 'Tsurumi repaired arm missing');
    return partRowsForLine(line, network.displayPartsForLine(line), null, null);
  });
  const currentParts = result.lanes.partsByRegion.jp.filter(row => ids.has(row[0]));
  assert(equal(currentParts, evidence.dependencyBaseline.nativeParts) || equal(currentParts, parts),
    'Tsurumi cached parts changed; review before replacing');
  for (const key of ['byRegion', 'familyWindowsByRegion', 'loopsByRegion', 'chainBoundariesByRegion', 'hubReportByRegion'])
    assert(!(result.lanes[key]?.jp || []).some(row => [...ids].some(id => JSON.stringify(row).includes(id))),
      'Tsurumi affected measured reference requires review');
  assert(!(result.lanes.reversedLoopParts?.jp || []).some(row => ids.has(row.split('#')[0])),
    'Tsurumi affected loop reference requires review');
  const follows = result.lanes.followsByRegion.jp.filter(row => ids.has(row[0]) || ids.has(row[4]));
  assert(!follows.length || equal(follows, evidence.dependencyBaseline.obsoleteFollows),
    'Tsurumi affected follow changed; review before removing');
  result.lanes.partsByRegion.jp = result.lanes.partsByRegion.jp.map(row =>
    ids.has(row[0]) ? parts.find(part => part[0] === row[0]) : row);
  result.lanes.followsByRegion.jp = result.lanes.followsByRegion.jp.filter(row => !ids.has(row[0]) && !ids.has(row[4]));

  const oldKey = okawa + ':004517', newKey = okawa + ':004522', sourceKey = IDENTITY + ':004522';
  assert(result.names.byCode[sourceKey]?.name === '安善', 'Tsurumi verified Anzen name missing');
  assert(!result.names.byCode[newKey] || equal(result.names.byCode[newKey], result.names.byCode[sourceKey]),
    'Tsurumi Anzen membership name changed');
  delete result.names.byCode[oldKey];
  result.names.byCode[newKey] = structuredClone(result.names.byCode[sourceKey]);
  const codes = result.english.byCountry.jp.byCode;
  const sourceMember = codes['004522'].memberships.find(row => row.lineId === IDENTITY);
  assert(sourceMember?.status === 'official_verified' && sourceMember.identityEvidence?.length,
    'Tsurumi official Anzen identity evidence missing');
  codes['004517'].memberships = codes['004517'].memberships.filter(row => row.lineId !== okawa);
  const desiredMember = { ...structuredClone(sourceMember), lineId: okawa, seq: 0 };
  const existingMember = codes['004522'].memberships.find(row => row.lineId === okawa);
  assert(!existingMember || equal(existingMember, desiredMember), 'Tsurumi English Anzen membership changed');
  if (!existingMember) codes['004522'].memberships.push(desiredMember);

  for (const key of ['englishSource', 'kanaSource']) {
    const source = result[key].byLineStation[sourceKey];
    assert(source?.stationCode === '004522' && source.identityEvidence?.length,
      'Tsurumi verified Anzen source identity missing');
    const desired = { ...structuredClone(source), lineId: okawa };
    assert(!result[key].byLineStation[newKey] || equal(result[key].byLineStation[newKey], desired),
      'Tsurumi source alias changed');
    delete result[key].byLineStation[oldKey];
    result[key].byLineStation[newKey] = desired;
  }
  const membershipRows = result.coverage.regions.jp.memberships;
  const sourceCoverage = membershipRows.find(row => row.key === sourceKey);
  assert(sourceCoverage?.group === '004522', 'Tsurumi Anzen coverage missing');
  const desiredCoverage = { ...structuredClone(sourceCoverage), key: newKey,
    kanaEvidence: DEPENDENCY_PATHS.kanaSource + '#byLineStation/' + newKey };
  const index = membershipRows.findIndex(row => row.key === oldKey || row.key === newKey);
  assert(index >= 0, 'Tsurumi original passenger membership coverage missing');
  membershipRows[index] = desiredCoverage;

  const packageHash = hash(JSON.stringify(pkg));
  result.englishSource.inputSha256['public/rail/jp-2025.json'] = packageHash;
  // Hash the final source (including its updated package dependency), then
  // update only already established input paths on the dependent artifacts.
  const finalSourceHash = hash(pretty(result.englishSource));
  if (DEPENDENCY_PATHS.englishSource in result.kanaSource.inputSha256)
    result.kanaSource.inputSha256[DEPENDENCY_PATHS.englishSource] = finalSourceHash;
  if ('public/rail/jp-2025.json' in result.kanaSource.inputSha256)
    result.kanaSource.inputSha256['public/rail/jp-2025.json'] = packageHash;
  result.english.inputSha256['public/rail/jp-2025.json'] = packageHash;
  result.english.inputSha256[DEPENDENCY_PATHS.englishSource] = finalSourceHash;
  result.coverage.inputSha256['public/rail/jp-2025.json'] = packageHash;
  result.coverage.inputSha256[DEPENDENCY_PATHS.kanaSource] = hash(pretty(result.kanaSource));
  result.coverage.inputSha256['data/station-english.json'] = hash(pretty(result.english));
  if ('data/station-names.json' in result.coverage.inputSha256)
    result.coverage.inputSha256['data/station-names.json'] = hash(pretty(result.names));

  // Same existing IDs/identity/service coverage require no catalog, rendering
  // or through-service edits. One passenger membership moves between two
  // existing station groups, leaving all coverage counts unchanged.
  assert.deepEqual(result.renderGroups, input.renderGroups);
  assert.deepEqual(result.catalog, input.catalog);
  assert.deepEqual(result.through, input.through);
  for (const key of ['englishSource', 'kanaSource']) {
    assert.deepEqual(result[key].coverage, input[key].coverage);
    const omit = rows => Object.fromEntries(Object.entries(rows).filter(([key]) => key !== oldKey && key !== newKey));
    assert.deepEqual(omit(result[key].byLineStation), omit(input[key].byLineStation));
  }
  for (const region of Object.keys(input.coverage.regions))
    if (region !== 'jp') assert.deepEqual(result.coverage.regions[region], input.coverage.regions[region]);
  assert.deepEqual(result.coverage.regions.jp.stats, input.coverage.regions.jp.stats);
  assert.deepEqual(result.names.byName, input.names.byName);
  const omitNames = rows => Object.fromEntries(Object.entries(rows).filter(([key]) => key !== oldKey && key !== newKey));
  assert.deepEqual(omitNames(result.names.byCode), omitNames(input.names.byCode));
  for (const [code, row] of Object.entries(input.english.byCountry.jp.byCode))
    if (!['004517', '004522'].includes(code)) assert.deepEqual(codes[code], row);
  assert.deepEqual(result.coverage.regions.jp.memberships.filter(row => row.key !== oldKey && row.key !== newKey),
    input.coverage.regions.jp.memberships.filter(row => row.key !== oldKey && row.key !== newKey));
  assert.deepEqual(result.lanes.partsByRegion.jp.filter(row => !ids.has(row[0])),
    input.lanes.partsByRegion.jp.filter(row => !ids.has(row[0])));
  for (const key of Object.keys(input.lanes).filter(key => !['partsByRegion', 'followsByRegion'].includes(key)))
    assert.deepEqual(result.lanes[key], input.lanes[key]);
  return result;
}

function surveyedInterval(chain, from, to, sections, evidence) {
  const points = [];
  for (const [index, reverse] of chain) {
    const feature = sections.features[index];
    assert.deepEqual(feature, evidence.sourceFeatures[index], 'Tsurumi source changed: selected survey feature');
    const properties = feature.properties;
    assert(properties.N02_001 === '11' && properties.N02_003 === '鶴見線' && properties.N02_004 === '東日本旅客鉄道',
      'Tsurumi source changed: passenger railway identity');
    assert.equal(feature.geometry.type, 'LineString');
    const next = structuredClone(feature.geometry.coordinates);
    if (reverse) next.reverse();
    if (points.length) assert(same(points.at(-1), next[0]), 'Tsurumi source changed: disconnected exact survey seam');
    points.push(...next.slice(points.length ? 1 : 0));
  }
  const first = projectPointOntoPolyline(from, points), last = projectPointOntoPolyline(to, points);
  assert(first.distanceM < 2 && last.distanceM < 2 && first.insertIndex < last.insertIndex,
    'Tsurumi source changed: reviewed station anchor does not lie on its passenger arm');
  // Interior coordinates and seams stay surveyed; only the two station-edge
  // projections use their pinned canonical station/platform anchor.
  return [from, ...points.slice(first.insertIndex + 1, last.insertIndex + 1), to];
}

export function repairPackage(input, sections, stations, evidence = JSON.parse(fs.readFileSync(EVIDENCE))) {
  assert.equal(evidence.format, 'jtm-tsurumi-passenger-arms-v1');
  assert.equal(evidence.identity, IDENTITY);
  const pkg = structuredClone(input), trunk = pkg.lines.find(row => row.id === IDENTITY);
  assert(trunk && trunk.railwayIdentity === IDENTITY, 'Tsurumi source changed: trunk identity');
  for (const code of ['004531', '004522', '004517'])
    assert.deepEqual(trunk.stations.find(row => row[0] === code), evidence.stationRows[code],
      'Tsurumi source changed: trunk station anchor or identity');
  for (const [index, feature] of Object.entries(evidence.stationFeatures))
    assert.deepEqual(stations.features[index], feature, 'Tsurumi source changed: pinned station platform');
  let structureDelta = 0;
  for (const arm of evidence.arms) {
    const original = evidence.oldBranches[arm.id], line = structuredClone(original);
    line.stations = arm.stationCodes.map(code => structuredClone(evidence.stationRows[code]));
    if (arm.platformFeature !== undefined) {
      const feature = stations.features[arm.platformFeature];
      assert.equal(feature.properties.n02_group_code, line.stations[0][0], 'Tsurumi source changed: branch platform identity');
      line.stations[0].splice(2, 2, ...feature.properties.display_point);
    }
    line.segments = encodeIntervals(arm.intervals.map((chain, n) =>
      surveyedInterval(chain, line.stations[n].slice(2, 4), line.stations[n + 1].slice(2, 4), sections, evidence)));
    // The old Okawa chainage belongs to a backtracking Musashi-Shiraishi
    // interval. Raw N02 has no structure tags to reconstruct its new measure.
    delete line.structure;
    const index = pkg.lines.findIndex(row => row.id === arm.id);
    assert(index >= 0, 'Tsurumi branch source changed: original branch absent');
    const old = pkg.lines[index];
    assert(equal(old, original) || equal(old, line), 'Tsurumi branch source changed; review before replacing');
    structureDelta += (line.structure?.length || 0) - (old.structure?.length || 0);
    pkg.lines[index] = line;
  }
  if (pkg.stats) pkg.stats.structure += structureDelta;
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['tsurumi-passenger-arms'] = {
    reviewedAt: evidence.reviewedAt, crs: evidence.crs,
    script: 'app/scripts/railway/repair-tsurumi-passenger-arms.mjs',
    evidence: 'app/scripts/railway/tsurumi-passenger-arm-evidence.json',
    source: evidence.source, stationSource: evidence.stationSource,
    dataset: evidence.dataset, license: evidence.license,
    passengerEvidence: evidence.passengerEvidence, businessIdentity: evidence.businessIdentity,
    transformation: 'Use the surveyed Asano branch-platform anchor for the Umi-Shibaura arm; replace the false Musashi-Shiraishi passenger endpoint of the Okawa arm with Anzen. Exact source joins, unchanged trunk and original railway identity.',
    structurePolicy: evidence.structurePolicy, sourceOwner: evidence.sourceOwner,
  };
  assert.deepEqual(pkg.lines.filter(row => !evidence.arms.some(arm => arm.id === row.id)),
    input.lines.filter(row => !evidence.arms.some(arm => arm.id === row.id)));
  return pkg;
}

export function applyPreparedWrites(writes, inputs) {
  // Check all inputs before the first write; a concurrent source/package/lane
  // edit stops this replay instead of overwriting mixed work in the checkout.
  for (const input of inputs)
    assert.equal(fs.readFileSync(input.path, 'utf8'), input.before,
      'Tsurumi replay input changed before apply: ' + input.path);
  for (const write of writes)
    assert(inputs.some(input => input.path === write.path && input.before === write.before),
      'Tsurumi apply destination is missing its exact input snapshot');
  for (const write of writes)
    if (write.before !== write.after) fs.writeFileSync(write.path, write.after);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const apply = args.length === 1 && args[0] === '--apply';
  const dryRun = !args.length || (args.length === 1 && args[0] === '--dry-run');
  assert(apply || dryRun || (args.length === 2 && args[0] === '--output'),
    'Usage: node repair-tsurumi-passenger-arms.mjs [--dry-run | --output /private/tmp/candidate.json | --apply]');
  const output = path.resolve(args[1] || '/private/tmp/jtm-tsurumi-passenger-candidate.json');
  assert(output.startsWith('/private/tmp/') || output.startsWith('/tmp/'), 'Candidate output must be scratch-only');
  const paths = { package: 'public/rail/jp-2025.json', sections: 'data/rail-sections.json',
    stations: 'data/stations.json', evidence: 'scripts/railway/tsurumi-passenger-arm-evidence.json',
    ...DEPENDENCY_PATHS };
  const snapshots = Object.fromEntries(Object.entries(paths).map(([key, relative]) => {
    const file = path.resolve(ROOT, relative);
    return [key, { path: file, before: fs.readFileSync(file, 'utf8') }];
  }));
  const read = key => JSON.parse(snapshots[key].before);
  const evidence = read('evidence');
  const result = repairPackage(read('package'), read('sections'), read('stations'), evidence);
  const dependencies = Object.fromEntries(Object.keys(DEPENDENCY_PATHS).map(key => [key, read(key)]));
  const candidateDependencies = proposeDependencies(result, dependencies, evidence);
  const dependencyOutput = output.replace(/\.json$/, '') + '.dependencies.json';
  fs.writeFileSync(output, JSON.stringify(result));
  fs.writeFileSync(dependencyOutput, JSON.stringify(candidateDependencies));
  console.log(output);
  console.log(dependencyOutput);
  if (apply) {
    const ownedKeys = ['package', 'lanes', 'names', 'english', 'coverage', 'englishSource', 'kanaSource'];
    const writes = ownedKeys.map(key => ({ ...snapshots[key], after:
      key === 'package' ? JSON.stringify(result) : key === 'lanes'
        ? JSON.stringify(candidateDependencies[key]) + '\n' : pretty(candidateDependencies[key]) }));
    applyPreparedWrites(writes, Object.values(snapshots));
    console.log('Applied scoped Tsurumi package, parts/follows and station memberships; unrelated resources preserved');
  }
}
