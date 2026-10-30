#!/usr/bin/env node
// jp-名古屋鉄道-津島線: display intervals 0,1,2,3,4,5,6 and 8 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-名古屋鉄道-津島線", key: "meitetsu-tsushima-r12j-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/tsushima-r12j-20261021/meitetsu-tsushima-r12j-authority.json"),
  format: "jtm-meitetsu-tsushima-r12j-authority-v1", receiptFormat: "jtm-meitetsu-tsushima-r12j-candidate-review-v1",
  stationIDs: ["005352","005355","005368","005370","005372","005375","005396","005420"], intervalIndices: [0,1,2,3,4,5,6],
  baselineSha: '2341b2c8b4df53a48a15f3e799fc317928c89d35359622344f34cf37deb26dfd', candidateSha: '1d7365a582459d3c1d13bddf207048f857ff04a686256f249be0f5c591886684'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
