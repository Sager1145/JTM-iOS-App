#!/usr/bin/env node
// jp-西日本鉄道-甘木線: display intervals 0,1,2,3,4,5,6,7,8,9,10 and 12 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-西日本鉄道-甘木線", key: "nishitetsu-amagi-r13a-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/repair-13a-20261021/amagi/nishitetsu-amagi-r13a-authority.json"),
  format: "jtm-nishitetsu-amagi-r13a-authority-v1", receiptFormat: "jtm-nishitetsu-amagi-r13a-candidate-review-v1",
  stationIDs: ["009296","009306","009311","009321","009329","009348","009351","009360","009364","009369","009374","009375"], intervalIndices: [0,1,2,3,4,5,6,7,8,9,10],
  baselineSha: '0ebe1850425c4ce2be49d51019e6e1810494fae9fab050bec887bac1a37be88a', candidateSha: '9ff213c6f41a08c41757b230d32fcb7ff2c033061cc05f58111e174693bb5dc7'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
