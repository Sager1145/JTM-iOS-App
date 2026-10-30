#!/usr/bin/env node
// jp-とさでん交通-桟橋線: display intervals 0,1,2,3,4,5,6 and 8 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-とさでん交通-桟橋線", key: "tosaden-sanbashi-r12j-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/sanbashi-r12j-20261021/tosaden-sanbashi-r12j-authority.json"),
  format: "jtm-tosaden-sanbashi-r12j-authority-v1", receiptFormat: "jtm-tosaden-sanbashi-r12j-candidate-review-v1",
  stationIDs: ["009117","009155","009176","009182","009192","009195","009200","009201"], intervalIndices: [0,1,2,3,4,5,6],
  baselineSha: 'fa11e07035afe4ae243cfa76a2103cbc2f6cc5916cc8154405edbe294dac1fcc', candidateSha: 'd6294aa86a2aa369cbf65fbe17e2c600f18b265572cadcdfdf80ebcfed64b78e'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
