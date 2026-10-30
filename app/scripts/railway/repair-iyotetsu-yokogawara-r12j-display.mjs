#!/usr/bin/env node
// jp-伊予鉄道-横河原線: display intervals 0,1,2,3,4,5,6,7,8,9,10,11,12,13 and 15 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-伊予鉄道-横河原線", key: "iyotetsu-yokogawara-r12j-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/yokogawara-r12j-20261021/iyotetsu-yokogawara-r12j-authority.json"),
  format: "jtm-iyotetsu-yokogawara-r12j-authority-v1", receiptFormat: "jtm-iyotetsu-yokogawara-r12j-candidate-review-v1",
  stationIDs: ["008773","008780","008784","008791","008795","008801","008802","008805","008812","008813","008816","008818","008821","008823","008824"], intervalIndices: [0,1,2,3,4,5,6,7,8,9,10,11,12,13],
  baselineSha: '29b1ddd2594df8cb3efb3ed8e156612b5c2ea1080516cbf148936eb2b168a766', candidateSha: 'eab7603e45709b652e237b855ffaabd44db69b9c5cec64590f69c8c3061ac7a8'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
