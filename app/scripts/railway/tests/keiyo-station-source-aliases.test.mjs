import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { repairStationSources } from '../repair-keiyo-station-source-aliases.mjs';

const id = 'jp-東日本旅客鉄道-京葉線';
const east = id + '-2', west = id + '-3';
const key = (line, code) => line + ':' + code;
const pkg = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json', import.meta.url)));
const english = JSON.parse(fs.readFileSync(new URL('../../../data/station-english-verified-jp-east.json', import.meta.url)));
const kana = JSON.parse(fs.readFileSync(new URL('../../../data/station-name-sources/jp-kana-evidence.json', import.meta.url)));
// Always exercise the historical wrong membership, even after publication.
const input = structuredClone({ english, kana });
if (input.english.byLineStation[key(west, '003547')]) {
  input.english.coverage.jrEastMemberships -= 2;
  input.english.coverage.verifiedMemberships -= 2;
  input.kana.coverage.verifiedMemberships -= 2;
  input.kana.coverage.byOperator['東日本旅客鉄道'] -= 2;
}
for (const doc of Object.values(input)) {
  delete doc.byLineStation[key(east, '003761')];
  delete doc.byLineStation[key(west, '003547')];
  delete doc.byLineStation[key(west, '003870')];
  doc.byLineStation[key(east, '003682')] = { ...structuredClone(doc.byLineStation[key(id, '003682')]), lineId: east };
}

test('Keiyo source aliases preserve exact official identity evidence and retire the false branch membership', () => {
  const before = structuredClone(input);
  const result = repairStationSources(pkg, input);
  assert.deepEqual(input, before);
  for (const type of ['english', 'kana']) {
    assert(!result[type].byLineStation[key(east, '003682')]);
    for (const [line, code, sourceLine] of [[east, '003761', id], [west, '003547', east], [west, '003870', id]]) {
      const expected = { ...structuredClone(input[type].byLineStation[key(sourceLine, code)]), lineId: line };
      assert.deepEqual(result[type].byLineStation[key(line, code)], expected);
    }
    const affected = new Set([key(east, '003682'), key(east, '003761'), key(west, '003547'), key(west, '003870')]);
    const unrelated = doc => Object.fromEntries(Object.entries(doc.byLineStation).filter(([k]) => !affected.has(k)));
    assert.deepEqual(unrelated(result[type]), unrelated(input[type]));
    assert.deepEqual(result[type].unresolved, input[type].unresolved);
  }
  assert.equal(result.english.coverage.verifiedMemberships, input.english.coverage.verifiedMemberships + 2);
  assert.equal(result.kana.coverage.verifiedMemberships, input.kana.coverage.verifiedMemberships + 2);
  assert.deepEqual(result.english.sourceCoverage, input.english.sourceCoverage);
  assert.deepEqual(repairStationSources(pkg, result), result);
});
