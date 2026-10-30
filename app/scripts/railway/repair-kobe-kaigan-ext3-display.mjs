#!/usr/bin/env node
// Kobe Municipal Subway Kaigan Line i2-i5: reviewed v12 on Apple's pale line; 92.8 m covered span at ハーバーランド north on one G1 curve (rule 14); 和田岬 line-local dot.
// Display-only (physical source unchanged); reviewed ext3 candidate v12c. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-神戸市-海岸線", key: "kobe-kaigan-ext3-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/ext3-20261022/rule1-reopened/kaigan-i2-5-rule1-v12c/kobe-kaigan-ext3-authority.json"),
  format: "jtm-ext3-kobe-kaigan-v12c-authority-v1", receiptFormat: "jtm-ext3-kobe-kaigan-v12c-candidate-review-v1",
  stationIDs: ["007238","007324","007385"],
  intervalIndices: [2,3,4,5],
  baselineSha: 'a4d76c571edbe0c5b6b8d8271bf9ab8cef8376ad7457bf1984e6639cc11b45d9',
  candidateSha: '1ae0c19eaa0e72c9dc95e3685bbc20638ae9ce1e25031bb7649b20ee2981a67e',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
