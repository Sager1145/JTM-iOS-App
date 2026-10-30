#!/usr/bin/env node
// Mizushima Main Line i8 own Apple glyph display re-trace
// Display-only (physical source unchanged); reviewed candidate v1 from railway-evidence/local/proposals/mizushima-main-20261021. Apply only with a candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

const repair = displayCandidateRepair({
  lineID: "jp-水島臨海鉄道-水島本線", key: "mizushima-main-own-glyph-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/mizushima-main-20261021/authority-v1.json"),
  format: "jtm-mizushima-main-own-glyph-display-authority-v1", receiptFormat: "jtm-mizushima-main-own-glyph-display-candidate-review-v1",
  stationIDs: ["007627","007604"], intervalIndices: [8],
  baselineSha: '71302ef13cdffc226dd6de4efe60004a8fedf269821681a369c4232b027fc531',
  candidateSha: '965b9dcb7ff6513fa7b35bd1224d8da58363c7fb50cdba7ef564ead3f9e183a4',
});
export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  repair.main(process.argv.slice(2), fileURLToPath(import.meta.url));
