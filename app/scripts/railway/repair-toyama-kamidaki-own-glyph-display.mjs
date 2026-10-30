#!/usr/bin/env node
// 富山地方鉄道上滝線 i0-i5 onto the own Apple rail glyph; aliases 大川寺/上滝/大庄/月岡/開発.
// Display-only (physical source unchanged); reviewed candidate v1 from railway-evidence/local/proposals/toyama-kamidaki-20261021. Apply only with a candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

const repair = displayCandidateRepair({
  lineID: "jp-富山地方鉄道-上滝線", key: "toyama-kamidaki-own-glyph-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/toyama-kamidaki-20261021/authority-v1.json"),
  format: "jtm-toyama-kamidaki-own-glyph-display-authority-v1", receiptFormat: "jtm-toyama-kamidaki-own-glyph-display-candidate-review-v1",
  stationIDs: ["002066","002063","002055","002050","002042"], intervalIndices: [0,1,2,3,4,5],
  baselineSha: '263b9756d15510cb5d1db118793742c7c70e25041470d922d6322b932a386eaa',
  candidateSha: '144a141955d23b1605ff97acb776c1b2c886f5935c08e792d3abbddb0fa5f73e',
});
export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  repair.main(process.argv.slice(2), fileURLToPath(import.meta.url));
