#!/usr/bin/env node
// JR East Kesennuma Line (柳津–前谷地): reviewed v8b whole-line display geometry on Apple track (repair-07 glyph extracts; i4 road-covered curve through the visible glimpse).
// Display-only (physical source unchanged); reviewed r0708 candidate v8b. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-東日本旅客鉄道-気仙沼線", key: "jre-kesennuma-r0708-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/jr-east-kesennuma-20261021/takeover-v8/jre-kesennuma-r0708-authority.json"),
  format: "jtm-r0708-jre-kesennuma-v8b-authority-v1", receiptFormat: "jtm-r0708-jre-kesennuma-v8b-candidate-review-v1",
  stationIDs: ["001043","001044","001049","001057","001064","001067"],
  intervalIndices: [0,1,2,3,4],
  baselineSha: 'a25ebb455ed6e8d69c756c2330b22f62db5dd49b159c989caac8d0e7418602a5',
  candidateSha: '8e5a8e04e7f1e88c14e2d129f29250940029e935b64fd4abd1d7b517bdc1f88d',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
