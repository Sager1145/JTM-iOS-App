import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import { repairPackage, repairParts } from '../repair-hakone-source-reversal.mjs';
const network = createRequire(import.meta.url)('../../../public/rail-network.js');
const read = relative => JSON.parse(fs.readFileSync(new URL('../../../' + relative, import.meta.url)));
const input = read('public/rail/jp-2025.json'), native = read('public/rail/display-lanes.json');
const evidence = JSON.parse(fs.readFileSync(new URL('../hakone-source-reversal-evidence.json', import.meta.url)));
const sources = { sections: read('data/rail-sections.json'), stations: read('data/stations.json') };
const line = input.lines.find(row => row.id === evidence.id);
if (evidence.originalReversalTails.length) line.reversalTails = evidence.originalReversalTails;
else delete line.reversalTails;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

test('Hakone outgoing passenger reversal survives complete display grooming without changing physical source', () => {
  const before = network.displayPartsForLine(line);
  assert(!before.flat().some(point => same(point, evidence.protectedExtent)), 'baseline must reproduce the lost tip');
  const pkg = repairPackage(input, sources, evidence), repaired = pkg.lines.find(row => row.id === evidence.id);
  const after = network.displayPartsForLine(repaired);
  assert(after[2].some(point => same(point, evidence.protectedExtent)));
  assert.deepEqual(after.map(part => part.length), [8, 300, 198]);
  assert.deepEqual(after.slice(0, 2), before.slice(0, 2));
  assert.deepEqual(after[2].filter(point => !same(point, evidence.protectedExtent)), before[2]);
  assert.deepEqual(repaired.segments, line.segments);
  assert.deepEqual(repaired.stations, line.stations);
  const strip = value => { const copy = structuredClone(value); delete copy.reversalTails; return copy; };
  assert.deepEqual(strip(repaired), strip(line));
  assert.deepEqual(pkg.lines.filter(row => row.id !== evidence.id), input.lines.filter(row => row.id !== evidence.id));
  assert.deepEqual(repairPackage(pkg, sources, evidence), pkg);
});

test('Hakone cache replay remaps only the complete lane endpoint and retains exact-prefix follows', () => {
  const pkg = repairPackage(input, sources, evidence), after = repairParts(pkg, native, evidence);
  const rows = after.partsByRegion.jp.filter(row => row[0] === evidence.id);
  assert.deepEqual(rows.map(row => row[4]), [8, 300, 198]);
  assert.equal(after.byRegion.jp.find(row => row[0] === evidence.id && row[1] === 2)[3], 4728.361924522782);
  assert.deepEqual(after.followsByRegion, native.followsByRegion);
  assert.deepEqual(after.chainBoundariesByRegion, native.chainBoundariesByRegion);
  for (const key of Object.keys(native).filter(key => !['partsByRegion', 'byRegion'].includes(key)))
    assert.deepEqual(after[key], native[key]);
  for (const key of ['partsByRegion', 'byRegion'])
    assert.deepEqual(after[key].jp.filter(row => row[0] !== evidence.id), native[key].jp.filter(row => row[0] !== evidence.id));
  assert.deepEqual(repairParts(pkg, after, evidence), after);
});

test('Hakone replay refuses altered ordered raw geometry or a follow beyond unchanged prefix', () => {
  const changed = structuredClone(sources.sections);
  changed.features[18337].geometry.coordinates[30][0] += 0.00001;
  assert.throws(() => repairPackage(input, { ...sources, sections: changed }, evidence), /outgoing railway survey/);
  const changedPackage = structuredClone(input);
  changedPackage.lines.find(row => row.id === evidence.id).segments[6][2][24][0] += 0.00001;
  assert.throws(() => repairPackage(changedPackage, sources, evidence), /compiled Hakone outgoing chain/);
  const measured = structuredClone(native);
  measured.followsByRegion.jp.push([evidence.id, 2, 250, 350, evidence.id, 1, 0, 100]);
  assert.throws(() => repairParts(repairPackage(input, sources, evidence), measured, evidence), /Hakone follows/);
});
