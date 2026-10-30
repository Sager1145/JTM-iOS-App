#!/usr/bin/env node
// jp-西武鉄道-国分寺線: display intervals 0,1,2,3 and 5 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-西武鉄道-国分寺線", key: "seibu-kokubunji-r13a-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/repair-13a-20261021/seibu-kokubunji/seibu-kokubunji-r13a-authority.json"),
  format: "jtm-seibu-kokubunji-r13a-authority-v1", receiptFormat: "jtm-seibu-kokubunji-r13a-candidate-review-v1",
  stationIDs: ["003220","003333","003450","003520","003606"], intervalIndices: [0,1,2,3],
  baselineSha: '046673521d2b56cb6b151670c6e6b4ac9eb2cc6c290848cc3d684fd5ccf8ff31', candidateSha: 'a171ff4a7afd2a9eb58a86161ebd19c4afc5f373593017fe1a832ff33eb42e06'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
