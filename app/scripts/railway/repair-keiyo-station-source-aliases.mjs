#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const ID = 'jp-東日本旅客鉄道-京葉線';
const EAST = ID + '-2', WEST = ID + '-3';
const key = (id, code) => id + ':' + code;
const pretty = value => JSON.stringify(value, null, 2) + '\n';
const hash = text => createHash('sha256').update(text).digest('hex');

export const STATION_SOURCE_PATHS = {
  english: 'data/station-english-verified-jp-east.json',
  kana: 'data/station-name-sources/jp-kana-evidence.json',
};

export function repairStationSources(pkg, input) {
  const result = structuredClone(input);
  const assignments = [[EAST, '003761', ID], [WEST, '003547', EAST], [WEST, '003870', ID]];
  const affected = new Set([key(EAST, '003682'), ...assignments.map(([id, code]) => key(id, code))]);
  const deltas = {};
  for (const [type, doc] of Object.entries(result)) {
    const beforeCount = Object.keys(doc.byLineStation).filter(k => affected.has(k)).length;
    delete doc.byLineStation[key(EAST, '003682')];
    for (const [lineId, code, sourceId] of assignments) {
      const station = pkg.lines.find(line => line.id === lineId)?.stations.find(row => row[0] === code);
      const source = doc.byLineStation[key(sourceId, code)];
      assert(station && source && source.stationCode === code && source.name === station[1]
        && source.operator === '東日本旅客鉄道' && source.identityEvidence?.length,
      'Keiyo station source identity changed');
      const alias = { ...structuredClone(source), lineId };
      const existing = doc.byLineStation[key(lineId, code)];
      assert(!existing || JSON.stringify(existing) === JSON.stringify(alias), 'Keiyo station source alias changed');
      doc.byLineStation[key(lineId, code)] = alias;
    }
    deltas[type] = Object.keys(doc.byLineStation).filter(k => affected.has(k)).length - beforeCount;
    const withoutAffected = rows => Object.fromEntries(Object.entries(rows).filter(([k]) => !affected.has(k)));
    assert.deepEqual(withoutAffected(doc.byLineStation), withoutAffected(input[type].byLineStation));
    assert.deepEqual(doc.unresolved, input[type].unresolved);
  }
  result.english.coverage.jrEastMemberships += deltas.english;
  result.english.coverage.verifiedMemberships += deltas.english;
  result.kana.coverage.verifiedMemberships += deltas.kana;
  result.kana.coverage.byOperator['東日本旅客鉄道'] += deltas.kana;
  result.english.inputSha256['public/rail/jp-2025.json'] = hash(JSON.stringify(pkg));
  result.kana.inputSha256[STATION_SOURCE_PATHS.english] = hash(pretty(result.english));
  assert.deepEqual(result.english.sourceCoverage, input.english.sourceCoverage);
  return result;
}

export function stationSourceHashes(input) {
  return Object.fromEntries(Object.entries(STATION_SOURCE_PATHS).map(([key, relative]) => [relative, hash(pretty(input[key]))]));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert(process.argv.length === 3 && process.argv[2] === '--apply', 'Usage: node repair-keiyo-station-source-aliases.mjs --apply');
  const before = Object.fromEntries(Object.entries(STATION_SOURCE_PATHS).map(([key, relative]) =>
    [key, fs.readFileSync(path.join(ROOT, relative), 'utf8')]));
  const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, 'public/rail/jp-2025.json')));
  const result = repairStationSources(pkg, Object.fromEntries(Object.entries(before).map(([key, text]) => [key, JSON.parse(text)])));
  for (const [key, relative] of Object.entries(STATION_SOURCE_PATHS))
    assert.equal(fs.readFileSync(path.join(ROOT, relative), 'utf8'), before[key], 'Keiyo source file changed during replay');
  for (const [key, relative] of Object.entries(STATION_SOURCE_PATHS)) {
    const text = pretty(result[key]);
    if (text !== before[key]) fs.writeFileSync(path.join(ROOT, relative), text);
  }
  console.log('Applied only the exact Keiyo membership aliases in the JR East English and kana source tables');
}
