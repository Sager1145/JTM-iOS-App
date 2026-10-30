#!/usr/bin/env node
// Meitetsu Chikko Line: whole-line rebuild on an independent z20 Apple trace; line-local termini on the last visible own rail.
// Display-only (physical source unchanged); reviewed r56 candidate v3. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-名古屋鉄道-築港線", key: "chikko-r56-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/r56-takeover-20261023/chikko/chikko-r56-authority.json"),
  format: "jtm-r56-chikko-v3-authority-v1", receiptFormat: "jtm-r56-chikko-v3-candidate-review-v1",
  stationIDs: ["005727","005714"],
  intervalIndices: [0],
  baselineSha: '2afd6692865c13961c5c52706fe5ef73266fc2edab81837a25185ade43ae4c16',
  candidateSha: '2d0932936063f99e16a01e15a33f0a12b3c49d503fce82e57a6ba61fe83b8881',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
