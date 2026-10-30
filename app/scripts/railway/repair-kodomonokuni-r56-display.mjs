#!/usr/bin/env node
// Tokyu Kodomonokuni Line: whole-line rebuild on an independent Apple trace (z18 body, z20 ends); line-local dots.
// Display-only (physical source unchanged); reviewed r56 candidate v4. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-東急電鉄-こどもの国線", key: "kodomonokuni-r56-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/r56-takeover-20261023/kodomonokuni/kodomonokuni-r56-authority.json"),
  format: "jtm-r56-kodomonokuni-v4-authority-v1", receiptFormat: "jtm-r56-kodomonokuni-v4-candidate-review-v1",
  stationIDs: ["004377","004341","004430"],
  intervalIndices: [0,1],
  baselineSha: '91226c77779dce4425cb87f58e1fee288450d22e830bad7365536b208db3b017',
  candidateSha: '542280cc932dd1a907e59cbcc8852c7b62dd5f9bcba302cbaa618e93f3646349',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
