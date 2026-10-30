#!/usr/bin/env node
// jp-伊予鉄道-本町線: display intervals 0,1,2,3 and 5 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-伊予鉄道-本町線", key: "iyotetsu-honmachi-r12j-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/honmachi-r12j-20261021/iyotetsu-honmachi-r12j-authority.json"),
  format: "jtm-iyotetsu-honmachi-r12j-authority-v1", receiptFormat: "jtm-iyotetsu-honmachi-r12j-candidate-review-v1",
  stationIDs: ["008719","008727","008735","008748","008756"], intervalIndices: [0,1,2,3],
  baselineSha: '7a9364a4a22414d76319134d45a4498f692d9e4f65d60c2efd3251b651ba947c', candidateSha: '56dc02b029917651ee5c8c0857015002ca605d0852e7325d29206f5ee00e8177'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
