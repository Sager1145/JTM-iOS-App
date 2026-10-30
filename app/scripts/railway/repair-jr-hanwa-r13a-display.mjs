#!/usr/bin/env node
// jp-西日本旅客鉄道-阪和線: display intervals 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32 and 34 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-西日本旅客鉄道-阪和線", key: "jr-hanwa-r13a-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/repair-13a-20261021/hanwa/jr-hanwa-r13a-authority.json"),
  format: "jtm-jr-hanwa-r13a-authority-v1", receiptFormat: "jtm-jr-hanwa-r13a-candidate-review-v1",
  stationIDs: ["007475","007531","007556","007576","007595","007623","007641","007660","007693","007709","007735","007746","007773","007791","007821","007841","007871","007913","007928","007939","007950","007973","007989","008008","008072","008097","008120","008142","008173","008217","008305","008315","008348","008365"], intervalIndices: [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32],
  baselineSha: '95224abf92ea8d052b7fb3320df930a7ca3c37a093e0849ad674001cd93477ca', candidateSha: '54afd1b5a8ebd8e3c6567a6fc428d576ba1cecf6434ef3dafbaa2ce9993af6b9'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
