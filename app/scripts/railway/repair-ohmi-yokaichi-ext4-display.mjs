#!/usr/bin/env node
// Ohmi Railway Yokaichi Line: reviewed v12 whole-line trace built from an independent Apple z18 trace (rule-12 rework of v11); line-local 八日市 dot.
// Display-only (physical source unchanged); reviewed ext4 candidate v12. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-近江鉄道-八日市線", key: "ohmi-yokaichi-ext4-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/ext-takeover-20261023/yokaichi-v12/ohmi-yokaichi-ext4-authority.json"),
  format: "jtm-ext4-ohmi-yokaichi-v12-authority-v1", receiptFormat: "jtm-ext4-ohmi-yokaichi-v12-candidate-review-v1",
  stationIDs: ["005652","005669","005687","005666","005647","005619","005665"],
  intervalIndices: [0,1,2,3,4,5],
  baselineSha: 'dfb3e786dffea3352b3bddabbeb65c17825aa7491cea4b3811a0ab6218e7402d',
  candidateSha: '0259e9f75bbf885e890c8e43e57d0a48726c58c1f311bd4a8b82949f2ad8fdc4',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
