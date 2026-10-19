#!/usr/bin/env node
// Bounded candidate replay. Published package and measured display artifacts
// remain integration-owned; this CLI defaults to a scratch candidate only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { encodeIntervals, projectPointOntoPolyline } from './jp-manual-corrections/geo.mjs';
import { partRowsForLine } from './build-display-lanes.mjs';
import { repairStationSources, STATION_SOURCE_PATHS, stationSourceHashes } from './repair-keiyo-station-source-aliases.mjs';

const network = createRequire(import.meta.url)('../../public/rail-network.js');

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const EVIDENCE = path.join(ROOT, 'scripts/railway/keiyo-passenger-arm-evidence.json');
export const IDENTITY = 'jp-東日本旅客鉄道-京葉線';
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const hash = text => createHash('sha256').update(text).digest('hex');
const pretty = value => JSON.stringify(value, null, 2) + '\n';
export const DEPENDENCY_PATHS = {
  lanes: 'public/rail/display-lanes.json', renderGroups: 'public/rail/jp-render-groups.json',
  names: 'data/station-names.json', english: 'data/station-english.json',
  coverage: 'data/station-names-coverage.json',
  catalog: '../ios/RailKit/Sources/RailCore/Resources/line-service-catalog.json',
  through: '../ios/RailKit/Sources/RailCore/Resources/japan-through-services.json',
};

export function repairThroughServices(input) {
  const result = structuredClone(input);
  const history = 'https://www.jreast.co.jp/youran/pdf/jre_youran_group_p30_35.pdf';
  const routes = [
    ['musashino-keiyo-tokyo', '-3', '003870',
      ['https://timetables.jreast.co.jp/2610/train/130/134601.html', 'https://timetables.jreast.co.jp/2610/train/165/166961.html'],
      '府中本町–西船橋から市川塩浜経由で東京（京葉線ホーム、003785）へ直通。二俣新町はこの支線の停車駅・接続駅ではない。京葉線東京開業は1990-03-10。既存の2005年以降の収録範囲は維持する。'],
    ['musashino-keiyo-makuhari', '-2', '003761',
      ['https://timetables.jreast.co.jp/2610/train/130/132751.html', 'https://timetables.jreast.co.jp/2610/train/165/166891.html'],
      '西船橋から南船橋経由で京葉線蘇我方へ入り海浜幕張まで走る客運系統。二俣新町はこの支線の停車駅・接続駅ではない。JR東日本会社要覧は海浜幕張乗り入れ開始を2000-12-02と記録する。既存の2005年以降の収録範囲は維持する。'],
  ];
  for (const [id, suffix, junction, sources, notes] of routes) {
    const row = result.patterns.find(pattern => pattern.id === id);
    assert(row && row.legs.length === 3 && row.legs[1].fromStationCode === '003547', 'Keiyo through-service source changed');
    const old = row.legs[1].lineID === IDENTITY + '-2' && row.legs[1].toStationCode === '003682' && row.legs[2].fromStationCode === '003682';
    const repaired = row.legs[1].lineID === IDENTITY + suffix && row.legs[1].toStationCode === junction && row.legs[2].fromStationCode === junction;
    assert(old || repaired, 'Keiyo through-service connection changed; review before replacing');
    row.legs[1].lineID = IDENTITY + suffix;
    row.legs[1].toStationCode = junction;
    row.legs[2].fromStationCode = junction;
    row.sourceURLs = [...new Set([...row.sourceURLs, history, ...sources])];
    row.notes = notes;
  }
  return result;
}

export function repairDependencies(pkg, input, evidence = JSON.parse(fs.readFileSync(EVIDENCE))) {
  const result = structuredClone(input);
  if (input.through) result.through = repairThroughServices(input.through);
  const stationSources = repairStationSources(pkg, Object.fromEntries(Object.keys(STATION_SOURCE_PATHS).map(key =>
    [key, JSON.parse(fs.readFileSync(path.join(ROOT, STATION_SOURCE_PATHS[key])))])));
  const sourceHashes = stationSourceHashes(stationSources);
  const east = IDENTITY + '-2', west = IDENTITY + '-3';
  const ids = new Set([east, west]);
  const base = evidence.dependencyBaseline;
  const newParts = evidence.arms.flatMap(arm => {
    const line = pkg.lines.find(row => row.id === arm.id);
    assert(line, 'Keiyo repaired arm missing');
    return partRowsForLine(line, network.displayPartsForLine(line), null, null);
  });
  const oldParts = result.lanes.partsByRegion.jp.filter(row => ids.has(row[0]));
  assert(equal(oldParts, base.nativeParts) || equal(oldParts, newParts),
    'Keiyo native parts changed; review before replacing');
  // No existing lane/window/loop/hub may be silently remeasured. Only the
  // registered obsolete follow is retired; no replacement is guessed.
  for (const key of ['byRegion', 'familyWindowsByRegion', 'loopsByRegion', 'chainBoundariesByRegion', 'hubReportByRegion'])
    assert(!(result.lanes[key]?.jp || []).some(row => JSON.stringify(row).includes(east) || JSON.stringify(row).includes(west)),
      'Keiyo affected measured reference requires review');
  assert(!(result.lanes.reversedLoopParts?.jp || []).some(row => ids.has(row.split('#')[0])), 'Keiyo loop reference requires review');
  const follows = result.lanes.followsByRegion.jp.filter(row => ids.has(row[0]) || ids.has(row[4]));
  assert(!follows.length || equal(follows, base.obsoleteFollows), 'Keiyo affected follow changed; review before removing');
  let inserted = false;
  result.lanes.partsByRegion.jp = result.lanes.partsByRegion.jp.flatMap(row => {
    if (!ids.has(row[0])) return [row];
    if (inserted) return [];
    inserted = true; return newParts;
  });
  assert(inserted, 'Keiyo cached original part missing');
  result.lanes.followsByRegion.jp = result.lanes.followsByRegion.jp.filter(row => !ids.has(row[0]) && !ids.has(row[4]));

  const group = result.renderGroups.byLineId[east];
  assert(group === result.renderGroups.byLineId[IDENTITY], 'Keiyo render identity changed');
  assert(!result.renderGroups.byLineId[west] || result.renderGroups.byLineId[west] === group, 'Keiyo render-group collision');
  result.renderGroups.byLineId[west] = group;
  const reason = result.renderGroups.byLineIdReasons.find(row => row.lineIds.includes(east));
  assert(reason && reason.renderGroupIds.includes(group), 'Keiyo render-group reason absent');
  if (!reason.lineIds.includes(west)) reason.lineIds.splice(reason.lineIds.indexOf(east) + 1, 0, west);
  const family = result.renderGroups.families[group];
  assert(family.why.startsWith('2 rows ') || family.why.startsWith('3 rows '), 'Keiyo render-group description changed');
  family.why = family.why.replace(/^[23] rows /, '3 rows ');

  const key = (line, code) => line + ':' + code;
  const originalNishi = key(east, '003547');
  const assignments = [
    [east, '003761', key(IDENTITY, '003761'), 1],
    [west, '003547', originalNishi, 0],
    [west, '003870', key(IDENTITY, '003870'), 1],
  ];
  const oldNameKeys = new Set([key(east, '003682'), ...assignments.map(([id, code]) => key(id, code))]);
  const beforeNames = Object.entries(result.names.byCode).filter(([k]) => oldNameKeys.has(k)).map(([, row]) => row);
  delete result.names.byCode[key(east, '003682')];
  for (const [id, code, source] of assignments) {
    assert(result.names.byCode[source], 'Keiyo verified station names absent');
    result.names.byCode[key(id, code)] = structuredClone(result.names.byCode[source]);
  }
  const codes = result.english.byCountry.jp.byCode;
  codes['003682'].memberships = codes['003682'].memberships.filter(row => row.lineId !== east);
  for (const [id, code, source, seq] of assignments) {
    const sourceID = source.slice(0, source.lastIndexOf(':'));
    const member = codes[code].memberships.find(row => row.lineId === sourceID);
    assert(member && member.status === 'official_verified' && member.identityEvidence?.length,
      'Keiyo official station identity evidence absent');
    const alias = { ...structuredClone(member), lineId: id, seq };
    const existing = codes[code].memberships.find(row => row.lineId === id);
    assert(!existing || equal(existing, alias), 'Keiyo English membership changed');
    if (!existing) codes[code].memberships.push(alias);
  }

  const membershipRows = result.coverage.regions.jp.memberships;
  const originalCoverage = membershipRows.find(row => row.key === originalNishi);
  assert(originalCoverage, 'Keiyo original station coverage absent');
  const desired = assignments.map(([id, code, source]) => {
    const row = membershipRows.find(row => row.key === source);
    assert(row, 'Keiyo existing station coverage absent');
    // Reuse the actual existing station-specific kana locator, rather than
    // inventing a byLineStation key for the new geometric branch row.
    return { ...structuredClone(row), key: key(id, code) };
  });
  const beforeCoverage = membershipRows.filter(row => oldNameKeys.has(row.key));
  const retained = membershipRows.filter(row => !oldNameKeys.has(row.key));
  const nishiIndex = retained.findIndex(row => row.key === originalNishi);
  retained.splice(nishiIndex + 1, 0, ...desired);
  result.coverage.regions.jp.memberships = retained;
  const fields = { withEnglish: 'en', withKana: 'kana', withTraditionalChinese: 'zh_Hant', withSimplifiedChinese: 'zh_Hans' };
  const afterNames = assignments.map(([id, code]) => result.names.byCode[key(id, code)]);
  const stats = result.coverage.regions.jp.stats;
  stats.memberships += desired.length - beforeCoverage.length;
  for (const [field, name] of Object.entries(fields))
    stats[field] += afterNames.filter(row => Boolean(row[name])).length - beforeNames.filter(row => Boolean(row[name])).length;

  const catalogRow = result.catalog.lines.find(row => row.lineID === east);
  assert(catalogRow && catalogRow.coverage === 'unknown', 'Keiyo service catalog baseline changed');
  const westCatalog = { ...structuredClone(catalogRow), lineID: west };
  const oldWest = result.catalog.lines.find(row => row.lineID === west);
  assert(!oldWest || equal(oldWest, westCatalog), 'Keiyo branch-3 service catalog changed');
  if (!oldWest) result.catalog.lines.splice(result.catalog.lines.indexOf(catalogRow) + 1, 0, westCatalog);

  const packageHash = hash(JSON.stringify(pkg));
  result.english.inputSha256['public/rail/jp-2025.json'] = packageHash;
  result.english.inputSha256[STATION_SOURCE_PATHS.english] = sourceHashes[STATION_SOURCE_PATHS.english];
  result.coverage.inputSha256[STATION_SOURCE_PATHS.kana] = sourceHashes[STATION_SOURCE_PATHS.kana];
  result.coverage.inputSha256['public/rail/jp-2025.json'] = packageHash;
  result.coverage.inputSha256['data/station-english.json'] = hash(pretty(result.english));
  if ('data/station-names.json' in result.coverage.inputSha256)
    result.coverage.inputSha256['data/station-names.json'] = hash(pretty(result.names));

  // Equality checks are scoped to the actual affected records, and also
  // prove that every unrelated list/dictionary value remains intact.
  const withoutIDs = rows => rows.filter(row => !ids.has(row[0]));
  assert.deepEqual(withoutIDs(result.lanes.partsByRegion.jp), withoutIDs(input.lanes.partsByRegion.jp));
  assert.deepEqual(result.lanes.followsByRegion.jp,
    input.lanes.followsByRegion.jp.filter(row => !ids.has(row[0]) && !ids.has(row[4])));
  for (const k of Object.keys(input.lanes).filter(k => !['partsByRegion', 'followsByRegion'].includes(k)))
    assert.deepEqual(result.lanes[k], input.lanes[k]);
  const withoutKeys = obj => Object.fromEntries(Object.entries(obj).filter(([k]) => !oldNameKeys.has(k)));
  assert.deepEqual(withoutKeys(result.names.byCode), withoutKeys(input.names.byCode));
  assert.deepEqual(result.names.byName, input.names.byName);
  assert.deepEqual(result.coverage.regions.jp.memberships.filter(row => !oldNameKeys.has(row.key)),
    input.coverage.regions.jp.memberships.filter(row => !oldNameKeys.has(row.key)));
  assert.deepEqual(result.catalog.lines.filter(row => row.lineID !== west), input.catalog.lines.filter(row => row.lineID !== west));
  assert.deepEqual(result.catalog.trips, input.catalog.trips);
  for (const [code, row] of Object.entries(input.english.byCountry.jp.byCode))
    if (!['003547', '003682', '003761', '003870'].includes(code)) assert.deepEqual(codes[code], row);
  for (const country of Object.keys(input.english.byCountry).filter(country => country !== 'jp'))
    assert.deepEqual(result.english.byCountry[country], input.english.byCountry[country]);
  for (const region of Object.keys(input.coverage.regions).filter(region => region !== 'jp'))
    assert.deepEqual(result.coverage.regions[region], input.coverage.regions[region]);
  for (const key of ['groups']) assert.equal(result.coverage.regions.jp.stats[key], input.coverage.regions.jp.stats[key]);
  assert.deepEqual(result.coverage.regions.jp.missingKana, input.coverage.regions.jp.missingKana);
  const byLineWithoutWest = groups => Object.fromEntries(Object.entries(groups.byLineId).filter(([id]) => id !== west));
  assert.deepEqual(byLineWithoutWest(result.renderGroups), byLineWithoutWest(input.renderGroups));
  assert.deepEqual(result.renderGroups.byLineIdReasons.map(row => ({ ...row, lineIds: row.lineIds.filter(id => id !== west) })),
    input.renderGroups.byLineIdReasons.map(row => ({ ...row, lineIds: row.lineIds.filter(id => id !== west) })));
  for (const [id, family] of Object.entries(input.renderGroups.families))
    if (id !== group) assert.deepEqual(result.renderGroups.families[id], family);
  return result;
}

function armCoordinates(arm, sections, evidence) {
  const survey = [];
  for (const [index, reverse] of arm.featureChain) {
    const feature = sections.features[index];
    assert.deepEqual(feature, evidence.sourceFeatures[index], 'Keiyo source changed: selected survey feature');
    const p = feature.properties;
    assert(p.N02_001 === '11' && p.N02_003 === '京葉線' && p.N02_004 === '東日本旅客鉄道');
    assert.equal(feature.geometry.type, 'LineString');
    const points = structuredClone(feature.geometry.coordinates);
    if (reverse) points.reverse();
    if (survey.length) assert(same(survey.at(-1), points[0]), 'Keiyo source changed: disconnected exact survey seam');
    survey.push(...points.slice(survey.length ? 1 : 0));
  }
  const from = evidence.stationRows['003547'].slice(2, 4);
  const to = evidence.stationRows[arm.toStationID].slice(2, 4);
  const first = projectPointOntoPolyline(from, survey);
  const last = projectPointOntoPolyline(to, survey);
  assert(first.distanceM < 2 && last.distanceM < 2 && first.insertIndex < last.insertIndex,
    'Keiyo source changed: station does not lie on its reviewed arm');
  // Only the two canonical station anchors replace projections. Every
  // interior vertex and every inter-feature seam stays exactly surveyed.
  return [from, ...survey.slice(first.insertIndex + 1, last.insertIndex + 1), to];
}

export function repairPackage(input, sections, evidence = JSON.parse(fs.readFileSync(EVIDENCE))) {
  assert.equal(evidence.format, 'jtm-keiyo-passenger-arms-v1');
  assert.equal(evidence.identity, IDENTITY);
  const pkg = structuredClone(input);
  const trunk = pkg.lines.find(line => line.id === IDENTITY);
  assert(trunk && trunk.railwayIdentity === IDENTITY, 'Keiyo source changed: trunk identity');
  for (const code of ['003761', '003870'])
    assert.deepEqual(trunk.stations.find(row => row[0] === code), evidence.stationRows[code],
      'Keiyo source changed: trunk station identity or anchor');
  const rebuilt = evidence.arms.map(arm => {
    const line = structuredClone(evidence.oldBranch);
    line.id = arm.id;
    line.stations = [evidence.stationRows['003547'], evidence.stationRows[arm.toStationID]].map(row => row.slice());
    line.segments = encodeIntervals([armCoordinates(arm, sections, evidence)]);
    // Raw N02 has no structural tags. The old annotations measure a false
    // terminal return and must not be attached to either passenger arm.
    delete line.structure;
    return line;
  });
  let addedLines = 0, addedIntervals = 0, addedStations = 0, removedStructure = 0;
  for (let i = 0; i < rebuilt.length; i++) {
    const line = rebuilt[i];
    const index = pkg.lines.findIndex(row => row.id === line.id);
    if (index >= 0) {
      const old = pkg.lines[index];
      if (i === 0) assert(JSON.stringify(old) === JSON.stringify(evidence.oldBranch)
        || JSON.stringify(old) === JSON.stringify(line), 'Keiyo branch source changed');
      else assert.deepEqual(old, line, 'Keiyo branch-3 collision or source changed');
      addedIntervals += line.segments.length - old.segments.length;
      addedStations += line.stations.length - old.stations.length;
      removedStructure += (old.structure?.length || 0) - (line.structure?.length || 0);
      pkg.lines[index] = line;
    } else {
      assert(i > 0, 'Keiyo source changed: original branch absent');
      const eastIndex = pkg.lines.findIndex(row => row.id === rebuilt[0].id);
      pkg.lines.splice(eastIndex + 1, 0, line);
      addedLines++; addedIntervals += line.segments.length; addedStations += line.stations.length;
    }
  }
  if (pkg.stats) {
    pkg.stats.lines += addedLines;
    pkg.stats.intervals += addedIntervals;
    pkg.stats.stations += addedStations;
    pkg.stats.structure -= removedStructure;
  }
  pkg.geometrySource.manualOverrides ||= {};
  pkg.geometrySource.manualOverrides['keiyo-passenger-arms'] = {
    reviewedAt: evidence.reviewedAt, crs: evidence.crs,
    script: 'app/scripts/railway/repair-keiyo-passenger-arms.mjs',
    evidence: 'app/scripts/railway/keiyo-passenger-arm-evidence.json',
    source: evidence.source, dataset: evidence.dataset, license: evidence.license,
    passengerEvidence: evidence.passengerEvidence,
    transformation: 'Replace the false Nishi-Funabashi–Futamata-Shinmachi branch interval with two evidenced passenger arms to Minami-Funabashi and Ichikawa-Shiohama; exact survey joins, canonical station anchors and unchanged trunk.',
    structurePolicy: evidence.structurePolicy,
  };
  return pkg;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const apply = args.length === 1 && args[0] === '--apply';
  assert(apply || !args.length || (args.length === 2 && args[0] === '--output'),
    'Usage: node repair-keiyo-passenger-arms.mjs [--output /path/candidate.json | --apply]');
  const output = path.resolve(args[1] || '/private/tmp/jtm-keiyo-passenger-candidate.json');
  const inputPath = path.join(ROOT, 'public/rail/jp-2025.json');
  assert(output !== inputPath, 'Candidate output must differ from the published input');
  const beforePackage = fs.readFileSync(inputPath, 'utf8');
  const pkg = repairPackage(JSON.parse(beforePackage),
    JSON.parse(fs.readFileSync(path.join(ROOT, 'data/rail-sections.json'))));
  fs.writeFileSync(output, JSON.stringify(pkg));
  console.log(output);
  if (apply) {
    const before = Object.fromEntries(Object.entries(DEPENDENCY_PATHS).map(([key, relative]) =>
      [key, fs.readFileSync(path.join(ROOT, relative), 'utf8')]));
    const sourceBefore = Object.fromEntries(Object.entries(STATION_SOURCE_PATHS).map(([key, relative]) =>
      [key, fs.readFileSync(path.join(ROOT, relative), 'utf8')]));
    const sources = repairStationSources(pkg, Object.fromEntries(Object.entries(sourceBefore).map(([key, text]) => [key, JSON.parse(text)])));
    const deps = repairDependencies(pkg, Object.fromEntries(Object.entries(before).map(([key, raw]) => [key, JSON.parse(raw)])));
    const writes = [[inputPath, beforePackage, JSON.stringify(pkg)], ...Object.entries(DEPENDENCY_PATHS).map(([key, relative]) =>
      [path.join(ROOT, relative), before[key], key === 'lanes' ? JSON.stringify(deps[key]) + '\n' : pretty(deps[key])]),
      ...Object.entries(STATION_SOURCE_PATHS).map(([key, relative]) => [path.join(ROOT, relative), sourceBefore[key], pretty(sources[key])])];
    // Check the exact files we own again before any publication. This avoids
    // overwriting a same-session edit made while preparing the candidate.
    for (const [file, original] of writes) assert.equal(fs.readFileSync(file, 'utf8'), original, 'Owned input changed during replay');
    for (const [file, original, replacement] of writes) if (original !== replacement) fs.writeFileSync(file, replacement);
    console.log('Applied the package and scoped display/station/catalog/through-service dependencies');
  }
}
