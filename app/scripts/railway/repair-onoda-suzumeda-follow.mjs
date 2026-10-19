#!/usr/bin/env node
// Retire the reviewed non-exact Suzumeda branch follow. Package geometry and native parts stay unchanged.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const REPO = path.dirname(ROOT);
const PACKAGE = 'public/rail/jp-2025.json';
const LANES = 'public/rail/display-lanes.json';
const EVIDENCE = 'scripts/railway/onoda-suzumeda-follow-evidence.json';
const CURVE_EVIDENCE = 'scripts/railway/onoda-suzumeda-west-curve-display-evidence.json';
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const read = relative => JSON.parse(fs.readFileSync(path.join(ROOT, relative)));
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function reviewedObsoleteFollows(evidence) {
  const base = evidence.packageLines.find(item => item.line.id === evidence.baseLineID)?.line;
  const curve = read(CURVE_EVIDENCE);
  assert.equal(curve.lineID, evidence.baseLineID);
  assert.equal(curve.branchLineID, evidence.branchLineID);
  assert(['candidate-only', curve.policy.acceptanceGate].includes(curve.status));
  const artifact = curve.candidate.artifacts.find(item => path.basename(item.path) === 'candidate.json');
  assert(artifact, 'Reviewed Onoda curve candidate missing');
  const file = path.join(REPO, artifact.path);
  assert.equal(sha256(file), artifact.sha256, 'Reviewed Onoda curve candidate changed');
  const candidate = JSON.parse(fs.readFileSync(file));
  if (base?.displayIntervalCoordinates?.['4'])
    assert.deepEqual(base.displayIntervalCoordinates['4'], candidate.candidateIntervalCoordinates,
      'Onoda curve display interval changed');
  return [evidence.obsoleteFollow, curve.producer.obsoleteFollowAfterCurve];
}

function lineReferences(lanes, evidence) {
  const ids = [evidence.baseLineID, evidence.branchLineID];
  const contains = value => ids.some(id => JSON.stringify(value).includes(id));
  const references = {};
  for (const [key, value] of Object.entries(lanes)) {
    if (key === 'partsByRegion' || key === 'followsByRegion') continue;
    const region = value?.jp;
    if (Array.isArray(region)) {
      const rows = region.filter(contains);
      if (rows.length) references[key] = rows;
    } else if (region && typeof region === 'object') {
      const rows = Object.fromEntries(Object.entries(region).filter(([name, row]) =>
        ids.includes(name) || contains(row)));
      if (Object.keys(rows).length) references[key] = rows;
    }
  }
  return references;
}

function validate(pkg, lanes, evidence) {
  assert.equal(evidence.format, 'jtm-onoda-suzumeda-follow-v1');
  assert(['candidate-only', evidence.policy.acceptanceGate].includes(evidence.status),
    'Unknown Onoda follow review status');
  assert.deepEqual(evidence.packageLines.map(item => item.line.id),
    [evidence.baseLineID, evidence.branchLineID]);
  for (const item of evidence.packageLines)
    assert.deepEqual(pkg.lines[item.index], item.line, `Onoda package line changed: ${item.line.id}`);
  for (const source of evidence.sources)
    assert.equal(sha256(path.join(REPO, source.path)), source.sha256,
      `Reviewed Onoda source changed: ${source.path}`);
  const native = lanes.partsByRegion?.jp?.filter(row =>
    row[0] === evidence.baseLineID || row[0] === evidence.branchLineID);
  assert.deepEqual(native, evidence.nativeParts, 'Onoda native part changed');
  assert.deepEqual(lineReferences(lanes, evidence), evidence.otherReferences,
    'Onoda measured reference changed');
  const follows = lanes.followsByRegion?.jp?.filter(row =>
    row[0] === evidence.baseLineID || row[0] === evidence.branchLineID ||
    row[4] === evidence.baseLineID || row[4] === evidence.branchLineID);
  const obsolete = reviewedObsoleteFollows(evidence);
  const matched = obsolete.find(row => equal(follows, [row]));
  assert(follows && (matched || equal(follows, [])),
    'Onoda reviewed follow changed');
  return follows.length ? matched : null;
}

export function repairLanes(pkg, lanes, evidence = read(EVIDENCE)) {
  const remove = validate(pkg, lanes, evidence);
  if (!remove) return lanes;
  lanes.followsByRegion.jp = lanes.followsByRegion.jp.filter(row =>
    !equal(row, remove));
  validate(pkg, lanes, evidence);
  return lanes;
}

function main(args = process.argv.slice(2)) {
  const candidate = args[0] === '--candidate-root' && args.length === 2;
  const apply = equal(args, ['--apply']);
  assert(candidate || apply,
    'Usage: node repair-onoda-suzumeda-follow.mjs (--candidate-root /private/tmp/<dir> | --apply)');
  const evidence = read(EVIDENCE);
  if (apply) assert.equal(evidence.status, evidence.policy.acceptanceGate,
    'Onoda follow candidate requires accepted production comparison before apply');
  const pkg = read(PACKAGE), beforePath = path.join(ROOT, LANES);
  const before = fs.readFileSync(beforePath, 'utf8');
  const input = JSON.parse(before);
  const removedFollow = validate(pkg, input, evidence);
  const lanes = repairLanes(pkg, input, evidence);
  const after = `${JSON.stringify(lanes)}\n`;
  if (candidate) {
    const target = path.resolve(args[1]);
    assert(target.startsWith('/private/tmp/'), 'Candidate root must be under /private/tmp');
    fs.mkdirSync(target, { recursive: true });
    fs.writeFileSync(path.join(target, 'display-lanes.json'), after);
    fs.writeFileSync(path.join(target, 'onoda-suzumeda-follow-candidate.json'), `${JSON.stringify({
      format: evidence.format, status: evidence.status, baseLineID: evidence.baseLineID,
      branchLineID: evidence.branchLineID, removedFollow,
      packageChanged: false, nativePartsChanged: false,
    }, null, 2)}\n`);
  } else if (before !== after) {
    const temporary = `${beforePath}.onoda-suzumeda-${process.pid}.tmp`;
    fs.writeFileSync(temporary, after);
    try {
      assert.equal(fs.readFileSync(beforePath, 'utf8'), before,
        'display-lanes.json changed during Onoda follow preparation');
      fs.renameSync(temporary, beforePath);
    } catch (error) {
      if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
      throw error;
    }
  }
  console.log(JSON.stringify({ mode: apply ? 'applied' : 'candidate', status: evidence.status,
    branchLineID: evidence.branchLineID, removedFollow,
    packageChanged: false, nativePartsChanged: false }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
