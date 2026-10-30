#!/usr/bin/env node
// Ohmi Railway Main Line: reviewed v9 whole-line stroke on an independent Apple z18 trace (rule-12 rework of v8); every reviewed v8 station dot kept byte-identical.
// Display-only (physical source unchanged); reviewed ext4 candidate v9. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-近江鉄道-本線", key: "ohmi-main-ext4-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/ext-takeover-20261023/ohmi-v9/ohmi-main-ext4-authority.json"),
  format: "jtm-ext4-ohmi-main-v9-authority-v1", receiptFormat: "jtm-ext4-ohmi-main-v9-candidate-review-v1",
  stationIDs: ["005075","005131","005147","005201","005263","005316","005357","005428","005514","005572","005652","005710","005731","005754","005787","005830","005875","005948","006097","006119","006134","006140","006188","005221","005176"],
  intervalIndices: [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23],
  baselineSha: 'ce217fe720dc61d0fdaa255cd8b3ecd0dc26b56b81f01d34bc0263c34bbc6d72',
  candidateSha: '3b0c656c5d52bbd735657b58c0bb83c942c5f190ef40960bc79754dd94e10790',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
