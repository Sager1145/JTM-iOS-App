import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import { repairPackage, repairParts, refreshDependencyReferences, applyPreparedWrites,
  DEPENDENCY_PATHS } from '../repair-three-reversal-extents.mjs';

const require = createRequire(import.meta.url);
const network = require('../../../public/rail-network.js');
const input = JSON.parse(fs.readFileSync(new URL('../../../public/rail/jp-2025.json', import.meta.url)));
const evidence = JSON.parse(fs.readFileSync(new URL('../three-reversal-extents-evidence.json', import.meta.url)));
// Reconstruct the pinned faulty inputs so the regression also runs after the
// candidate is integrated, while retaining the current unrelated package data.
for (const item of evidence.items) {
  const index = input.lines.findIndex(line => line.id === item.lineId);
  if (item.repairPlatformBinding) input.lines[index] = structuredClone(item.originalLine);
  else if (item.originalReversalTails.length) input.lines[index].reversalTails = item.originalReversalTails;
  else delete input.lines[index].reversalTails;
}
const nativeInput = JSON.parse(fs.readFileSync(new URL('../../../public/rail/display-lanes.json', import.meta.url)));
const sources = {
  sections: JSON.parse(fs.readFileSync(new URL('../../../data/rail-sections.json', import.meta.url))),
  stations: JSON.parse(fs.readFileSync(new URL('../../../data/stations.json', import.meta.url)))
};
const same = (a, b) => a?.[0] === b?.[0] && a?.[1] === b?.[1];

for (const item of evidence.items.filter(item => item.protect)) {
  test(`${item.lineId}: complete display retains the real source reversal`, () => {
    const original = input.lines.find(line => line.id === item.lineId);
    const before = network.displayPartsForLine(original);
    assert(!before.flat().some(point => same(point, item.protectedExtent)), 'baseline reproduces lost reversal');
    const proposed = repairPackage(input, evidence, sources);
    const line = proposed.lines.find(line => line.id === item.lineId);
    const after = network.displayPartsForLine(line);
    assert(after.flat().some(point => same(point, item.protectedExtent)), 'real source reversal must survive display grooming');
    assert.deepEqual(after.map(part => part.length), item.afterPartCounts);
    assert.deepEqual(line.stations, original.stations);
    assert.deepEqual(line.segments, original.segments);
    // Only the part carrying the reversal may change; all other ink is identical.
    const changed = before.map((part, i) => JSON.stringify(part) !== JSON.stringify(after[i]));
    assert.equal(changed.filter(Boolean).length, 1);
    assert.deepEqual(repairPackage(proposed, evidence, sources), proposed);
    assert.deepEqual(input.lines.find(row => row.id === item.lineId), original);
  });
}

test('proposal preserves unrelated package data and rejects changed source seams', () => {
  const ids = new Set(evidence.items.map(item => item.lineId));
  const proposed = repairPackage(input, evidence, sources);
  assert.deepEqual(proposed.lines.filter(line => !ids.has(line.id)), input.lines.filter(line => !ids.has(line.id)));
  const withoutLines = pkg => { const copy = structuredClone(pkg); delete copy.lines; return copy; };
  assert.deepEqual(withoutLines(proposed), withoutLines(input));
  const changed = structuredClone(input);
  const item = evidence.items[1];
  changed.lines.find(line => line.id === item.lineId).segments[item.interval][2][3][0] += 0.00001;
  assert.throws(() => repairPackage(changed, evidence, sources), /source changed/);
});

test('native replay replaces only affected embedded parts and preserves all existing measured spans', () => {
  const proposed = repairPackage(input, evidence, sources);
  const after = repairParts(proposed, nativeInput, evidence);
  const item = evidence.items.find(item => item.lineId.includes('木次'));
  const rows = after.partsByRegion.jp.filter(row => row[0] === item.lineId);
  assert(rows.flatMap(row => row[7]).some(point => same(point, item.protectedExtent)));
  assert.deepEqual(rows.map(row => row[4]), item.afterPartCounts);
  const ids = new Set(evidence.items.map(item => item.lineId));
  const unrelated = row => !ids.has(row[0]);
  assert.deepEqual(after.partsByRegion.jp.filter(unrelated), nativeInput.partsByRegion.jp.filter(unrelated));
  for (const key of Object.keys(nativeInput).filter(key => !['partsByRegion', 'followsByRegion'].includes(key))) {
    assert.deepEqual(after[key], nativeInput[key], `${key}: no measured spans or unrelated metadata move`);
  }
  assert.deepEqual(repairParts(proposed, after, evidence), after);
});

test('Tateishi paired alignment ends at its own south passenger platform without the east-fork return', () => {
  const item = evidence.items.find(item => item.repairPlatformBinding);
  const proposed = repairPackage(input, evidence, sources);
  const line = proposed.lines.find(line => line.id === item.lineId);
  assert.deepEqual(line.stations[1].slice(2, 4), item.newStationAnchor);
  assert.deepEqual(line.stations[0], item.originalLine.stations[0]);
  assert.deepEqual(line.stations.map(row => row[0]), item.originalLine.stations.map(row => row[0]));
  assert.equal(line.alignmentDirection, 'up');
  assert.equal(line.stationOrderDirection, 'down');
  assert.equal(line.railwayIdentity, item.originalLine.railwayIdentity);
  assert(!line.reversalTails?.length, 'a platform binding must not be marked as a real reversal');
  const path = network.decodeIntervals(line)[0];
  assert(!path.some(point => same(point, item.protectedExtent)), 'no east-fork excursion to the other platform');
  assert.deepEqual(path.at(-1), item.newStationAnchor);
  assert(line.segments[0][0] < 6.0, 'source mileage excludes the artificial platform return');
  assert.deepEqual(proposed.lines.find(row => row.id === line.alignmentOf), input.lines.find(row => row.id === line.alignmentOf));
  const after = repairParts(proposed, nativeInput, evidence);
  assert.deepEqual(after.followsByRegion.jp, nativeInput.followsByRegion.jp.filter(row => JSON.stringify(row) !== JSON.stringify(item.obsoleteTerminalFollow)));
  assert(after.followsByRegion.jp.some(row => JSON.stringify(row) === JSON.stringify(item.preservedInitialFollow)));
});

test('changed raw platform evidence or a new measure on repaired geometry stops replay', () => {
  const item = evidence.items.find(item => item.repairPlatformBinding);
  const changedStations = structuredClone(sources.stations);
  changedStations.features[item.endStationFeature].properties.display_point[0] += 0.00001;
  assert.throws(() => repairPackage(input, evidence, { ...sources, stations: changedStations }), /source changed/);
  const proposed = repairPackage(input, evidence, sources);
  const measured = structuredClone(nativeInput);
  measured.byRegion.jp.push([item.lineId, 0, 5600, 5700, 0.5]);
  assert.throws(() => repairParts(proposed, measured, evidence), /measured span requires review/);
});

test('Okoba outgoing reversal proof requires its complete ordered passenger survey to Yatake', () => {
  const changed = structuredClone(sources.sections);
  // Interior of the ordered outgoing feature, outside the local extent window.
  changed.features[3766].geometry.coordinates[100][0] += 0.00001;
  assert.throws(() => repairPackage(input, evidence, { ...sources, sections: changed }), /ordered outgoing/);
});

test('declared station dependency references match final bytes without changing station entries', () => {
  const dependencies = Object.fromEntries(Object.entries(DEPENDENCY_PATHS).map(([key, relative]) =>
    [key, JSON.parse(fs.readFileSync(new URL('../../../' + relative, import.meta.url)))]));
  const pkg = repairPackage(input, evidence, sources);
  const after = refreshDependencyReferences(pkg, dependencies);
  const hash = value => createHash('sha256').update(value).digest('hex');
  const pretty = value => JSON.stringify(value, null, 2) + '\n';
  const packageHash = hash(JSON.stringify(pkg));
  for (const key of Object.keys(dependencies)) {
    const strip = object => { const copy = structuredClone(object); delete copy.inputSha256; return copy; };
    assert.deepEqual(strip(after[key]), strip(dependencies[key]), key + ': station contents stay unchanged');
    assert.deepEqual(Object.keys(after[key].inputSha256), Object.keys(dependencies[key].inputSha256),
      key + ': no undeclared dependency added');
    if ('public/rail/jp-2025.json' in after[key].inputSha256)
      assert.equal(after[key].inputSha256['public/rail/jp-2025.json'], packageHash);
  }
  assert.equal(after.kanaSource.inputSha256[DEPENDENCY_PATHS.englishSource], hash(pretty(after.englishSource)));
  assert.equal(after.english.inputSha256[DEPENDENCY_PATHS.englishSource], hash(pretty(after.englishSource)));
  assert.equal(after.coverage.inputSha256[DEPENDENCY_PATHS.kanaSource], hash(pretty(after.kanaSource)));
  assert.equal(after.coverage.inputSha256[DEPENDENCY_PATHS.english], hash(pretty(after.english)));
  assert.deepEqual(refreshDependencyReferences(pkg, after), after);
});

test('apply refuses changed inputs before the first destination write', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'jtm-three-repair-snapshot-'));
  try {
    const destination = path.join(directory, 'destination.json'), dependency = path.join(directory, 'input.json');
    fs.writeFileSync(destination, 'original destination');
    fs.writeFileSync(dependency, 'new input');
    const write = { path: destination, before: 'original destination', after: 'repaired destination' };
    assert.throws(() => applyPreparedWrites([write], [write, { path: dependency, before: 'old input' }]),
      /input changed before apply/);
    assert.equal(fs.readFileSync(destination, 'utf8'), write.before);
    assert.throws(() => applyPreparedWrites([write], [{ path: dependency, before: 'new input' }]),
      /destination is missing/);
    assert.equal(fs.readFileSync(destination, 'utf8'), write.before);
  } finally {
    fs.rmSync(directory, { recursive: true });
  }
});

test('apply compares binary snapshots byte-for-byte and preflights every input before writing', () => {
  const run = changed => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'jtm-three-repair-binary-'));
    try {
      const text = path.join(directory, 'destination.txt');
      const binary = path.join(directory, 'destination.bin');
      const textBefore = 'original text';
      const binaryBefore = Buffer.from([0, 255, 13, 10, 128]);
      fs.writeFileSync(text, textBefore);
      fs.writeFileSync(binary, binaryBefore);
      const writes = [
        { path: text, before: textBefore, after: 'repaired text' },
        { path: binary, before: Buffer.from(binaryBefore), after: Buffer.from([1, 2, 3]) },
      ];
      const inputs = [
        { path: text, before: textBefore },
        { path: binary, before: Buffer.from(binaryBefore) },
      ];
      if (changed === 'text') fs.writeFileSync(text, 'concurrent text');
      if (changed === 'binary') fs.writeFileSync(binary, Buffer.from([0, 255, 13, 10, 129]));
      if (changed) {
        const textAtApply = fs.readFileSync(text), binaryAtApply = fs.readFileSync(binary);
        assert.throws(() => applyPreparedWrites(writes, inputs), /input changed before apply/);
        assert(fs.readFileSync(text).equals(textAtApply), 'text destination changed after failed preflight');
        assert(fs.readFileSync(binary).equals(binaryAtApply), 'binary destination changed after failed preflight');
      } else {
        applyPreparedWrites(writes, inputs);
        assert.equal(fs.readFileSync(text, 'utf8'), 'repaired text');
        assert(fs.readFileSync(binary).equals(Buffer.from([1, 2, 3])));
      }
    } finally {
      fs.rmSync(directory, { recursive: true });
    }
  };
  run(null);
  run('binary');
  run('text');
});
