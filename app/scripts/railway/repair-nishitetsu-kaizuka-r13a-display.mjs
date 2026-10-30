#!/usr/bin/env node
// jp-西日本鉄道-貝塚線: display intervals 0,1,2,3,4,5,6,7,8 and 10 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-西日本鉄道-貝塚線", key: "nishitetsu-kaizuka-r13a-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/repair-13a-20261021/kaizuka/nishitetsu-kaizuka-r13a-authority.json"),
  format: "jtm-nishitetsu-kaizuka-r13a-authority-v1", receiptFormat: "jtm-nishitetsu-kaizuka-r13a-candidate-review-v1",
  stationIDs: ["008885","008891","008902","008911","008921","008930","008936","008947","008958","008967"], intervalIndices: [0,1,2,3,4,5,6,7,8],
  baselineSha: '34a687ea34a8f2139a3f26acf22e43d3c8ed82557194a3d6eeb014161e9a7a93', candidateSha: '263113591c9e91e99fab63da13a43460580539ec6b3a89165954d877e991beae'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
