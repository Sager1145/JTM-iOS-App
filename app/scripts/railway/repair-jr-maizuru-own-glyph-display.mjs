#!/usr/bin/env node
// Maizuru Line own Apple glyph display re-trace
// Display-only (physical source unchanged); reviewed candidate v4 from railway-evidence/local/proposals/jr-maizuru-20261021. Apply only with a candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

const repair = displayCandidateRepair({
  lineID: "jp-西日本旅客鉄道-舞鶴線", key: "jr-maizuru-own-glyph-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/jr-maizuru-20261021/authority-v4.json"),
  format: "jtm-jr-maizuru-own-glyph-display-authority-v4", receiptFormat: "jtm-jr-maizuru-own-glyph-display-candidate-review-v4",
  stationIDs: ["004792","004705"], intervalIndices: [1,2,3,4],
  baselineSha: '52e690098f2d48c520286a884f0c0c574e6717e5e73944b57081863f2dadaa10',
  candidateSha: '4192a6f5c8972f2418b0f97c9f3aae947a2c2318da97f461002c568db2528915',
});
export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  repair.main(process.argv.slice(2), fileURLToPath(import.meta.url));
