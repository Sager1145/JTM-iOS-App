#!/usr/bin/env node
// jp-西日本鉄道-天神大牟田線: display intervals 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48 and 50 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-西日本鉄道-天神大牟田線", key: "nishitetsu-tenjin-omuta-r13a-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/repair-13a-20261021/tenjin-omuta/nishitetsu-tenjin-omuta-r13a-authority.json"),
  format: "jtm-nishitetsu-tenjin-omuta-r13a-authority-v1", receiptFormat: "jtm-nishitetsu-tenjin-omuta-r13a-candidate-review-v1",
  stationIDs: ["009036","009049","009082","009097","009125","009162","009189","009207","009219","009222","009234","009245","009252","009261","009267","009269","009277","009285","009292","009302","009315","009325","009349","009375","009389","009397","009402","009404","009409","009417","009438","009451","009462","009485","009508","009531","009551","009554","009562","009566","009572","009577","009581","009585","009590","009597","009601","009608","009609","010185"], intervalIndices: [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48],
  baselineSha: '7df8f5f1bbd79f6e0e7c627418b47fc57beb64f60aefe6238eab40d8b24163c5', candidateSha: '4bfb80a31a963bcf0b922d552f114078ca6f16c279cac4df9cb8f05722edd0a9'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
