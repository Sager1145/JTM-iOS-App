#!/usr/bin/env node
// jp-九州旅客鉄道-鹿児島線-p1: display intervals 0 and 2 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-九州旅客鉄道-鹿児島線-p1", key: "jrkyushu-kagoshima-p1-r12j-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/kagoshimap1-r12j-20261021/jrkyushu-kagoshima-p1-r12j-authority.json"),
  format: "jtm-jrkyushu-kagoshima-p1-r12j-authority-v1", receiptFormat: "jtm-jrkyushu-kagoshima-p1-r12j-candidate-review-v1",
  stationIDs: ["009664","009670"], intervalIndices: [0],
  baselineSha: 'c5a45f9b223bc34df7282dcc1ca9029ef9bfcee4e1f392bac0460c3089c840dd', candidateSha: '5ee39b9cca2f50faaaaad5e69ea6baed18741d2e209f62e93ede203df72dbb9e'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
