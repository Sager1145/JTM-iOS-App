#!/usr/bin/env node
// jp-西日本旅客鉄道-阪和線-2: display intervals 0 and 2 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-西日本旅客鉄道-阪和線-2", key: "jr-hanwa-hagoromo-r13a-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/repair-13a-20261021/hanwa-2/jr-hanwa-hagoromo-r13a-authority.json"),
  format: "jtm-jr-hanwa-hagoromo-r13a-authority-v1", receiptFormat: "jtm-jr-hanwa-hagoromo-r13a-candidate-review-v1",
  stationIDs: ["007762","007773"], intervalIndices: [0],
  baselineSha: 'bbec498ef60dbb4b1bfaf5c2026978619faea8dbed911da5572c2dc5b53e3778', candidateSha: 'a1f6daf7388bbac716e78a77ae02e462fe80e5260ea4bae0e233e9ecbfe7cb1f'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
