#!/usr/bin/env node
// 東急新横浜線 i0 (新横浜→新綱島) and i1 (新綱島→日吉 approach) onto the own Apple tunnel glyph; 新綱島 alias.
// Display-only (physical source unchanged); reviewed candidate v2 from railway-evidence/local/proposals/tokyu-shin-yokohama-20261021. Apply only with a candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

const repair = displayCandidateRepair({
  lineID: "jp-東急電鉄-東急新横浜線", key: "tokyu-shin-yokohama-own-glyph-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/tokyu-shin-yokohama-20261021/authority-v2.json"),
  format: "jtm-tokyu-shin-yokohama-own-glyph-display-authority-v2", receiptFormat: "jtm-tokyu-shin-yokohama-own-glyph-display-candidate-review-v2",
  stationIDs: ["010165"], intervalIndices: [0,1],
  baselineSha: '4e9e7a06db1674fa66777d5adcec2b34590311ef3eb22be9bf0d1571ddabc5f7',
  candidateSha: '07932c68fe2d6f17ca1df3eee8a7f9af8eb67817538e72af1fd8df82e5633429',
});
export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  repair.main(process.argv.slice(2), fileURLToPath(import.meta.url));
