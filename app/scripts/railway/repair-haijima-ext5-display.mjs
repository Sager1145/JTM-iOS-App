#!/usr/bin/env node
// Seibu Haijima Line: reviewed v13 whole-line trace on Apple's own rail; 小平 ends on the last visible own rail.
// Display-only (physical source unchanged); reviewed ext5 candidate v13. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-西武鉄道-拝島線", key: "haijima-ext5-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/ext5-20261022/haijima-v13/haijima-ext5-authority.json"),
  format: "jtm-ext5-haijima-v13-authority-v1", receiptFormat: "jtm-ext5-haijima-v13-candidate-review-v1",
  stationIDs: ["003462","003428","003404","003333","003312","003340","003365","003371"],
  intervalIndices: [0,1,2,3,4,5,6],
  baselineSha: 'e54626a0c890b73e36c2b4508991947c84e52bd5da07c84a119c0e003f1f452c',
  candidateSha: 'd32f02f307329f466bcd0568408c3be73151367f8fe3b71ff7869ac5b62a0ac4',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
