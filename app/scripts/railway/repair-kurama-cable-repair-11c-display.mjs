#!/usr/bin/env node
// Kurama-dera cable car (鞍馬山鋼索鉄道): Apple draws no cable glyph; straight stroke between the two Apple station frames, dots inside the frames (no-track platform frame, Decision 2026-10-22 (b)).
// Display-only (physical source unchanged); reviewed repair-11c candidate v2. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-鞍馬寺-鞍馬山鋼索鉄道", key: "kurama-cable-repair-11c-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/r1112ab-20261023/kurama/kurama-cable-repair-11c-authority.json"),
  format: "jtm-repair-11c-kurama-cable-v2-authority-v1", receiptFormat: "jtm-repair-11c-kurama-cable-v2-candidate-review-v1",
  stationIDs: ["005650","005641"],
  intervalIndices: [0],
  baselineSha: '038063f8ba6f9a68c0d8075ba54873dc73bed3e989590c8dde5c36c74c0c1b6b',
  candidateSha: '47969f6377867e72f4080f2c6f363e0ac1b295ea61162a1fe32d2b6b73282eb7',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
