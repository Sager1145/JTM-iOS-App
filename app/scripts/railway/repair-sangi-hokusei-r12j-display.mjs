#!/usr/bin/env node
// jp-三岐鉄道-北勢線: display intervals 0,1,2,3,4,5,6,7,8,9,10,11 and 13 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-三岐鉄道-北勢線", key: "sangi-hokusei-r12j-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/hokusei-r12j-20261021/sangi-hokusei-r12j-authority.json"),
  format: "jtm-sangi-hokusei-r12j-authority-v1", receiptFormat: "jtm-sangi-hokusei-r12j-candidate-review-v1",
  stationIDs: ["005540","005575","005664","005711","005747","005758","005769","005785","005789","005797","005798","005801","005802"], intervalIndices: [0,1,2,3,4,5,6,7,8,9,10,11],
  baselineSha: '5caa99a35cd81ac9ab3226c488d776bbeb67adda6146ff6860b19e4bbfb31aa7', candidateSha: '79fbd845f17bbf8f6b7284f9bffdaae3caac959678350e94b1d30da2eb6c7554'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
