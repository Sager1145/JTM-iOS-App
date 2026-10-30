#!/usr/bin/env node
// jp-函館市-宝来・谷地頭線: display intervals 0,1,2 and 4 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-函館市-宝来・谷地頭線", key: "hakodate-horai-yachigashira-r12j-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/hourai-r12j-20261021/hakodate-horai-yachigashira-r12j-authority.json"),
  format: "jtm-hakodate-horai-yachigashira-r12j-authority-v1", receiptFormat: "jtm-hakodate-horai-yachigashira-r12j-candidate-review-v1",
  stationIDs: ["000467","000469","000470","000471"], intervalIndices: [0,1,2],
  baselineSha: '96b3d211f0c40eaedb387afdcbc5b1ea6683a3adbe29047c0aa9a8994847c7ba', candidateSha: '4b11b0c4de132351fa190b496d7c8f2ff51d217ba83e2842b62a4b50d958106b'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
