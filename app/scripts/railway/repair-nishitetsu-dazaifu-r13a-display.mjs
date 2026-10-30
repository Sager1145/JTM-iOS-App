#!/usr/bin/env node
// jp-西日本鉄道-太宰府線: display intervals 0,1 and 3 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-西日本鉄道-太宰府線", key: "nishitetsu-dazaifu-r13a-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/repair-13a-20261021/dazaifu/nishitetsu-dazaifu-r13a-authority.json"),
  format: "jtm-nishitetsu-dazaifu-r13a-authority-v1", receiptFormat: "jtm-nishitetsu-dazaifu-r13a-candidate-review-v1",
  stationIDs: ["009225","009235","009245"], intervalIndices: [0,1],
  baselineSha: 'baebd36b01858c3cf2790287bc145c78b9ede4cf349f5861fc651e1ce27c7b4b', candidateSha: 'f58628fba70545ae4273ea49a2164f5888292b2c9ff4ed7f31e804b319ed2b11'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
