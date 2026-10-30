#!/usr/bin/env node
// jp-西武鉄道-多摩川線: display intervals 0,1,2,3,4 and 6 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-西武鉄道-多摩川線", key: "seibu-tamagawa-r13a-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/repair-13a-20261021/seibu-tamagawa/seibu-tamagawa-r13a-authority.json"),
  format: "jtm-seibu-tamagawa-r13a-authority-v1", receiptFormat: "jtm-seibu-tamagawa-r13a-candidate-review-v1",
  stationIDs: ["003590","003653","003790","003873","003943","003944"], intervalIndices: [0,1,2,3,4],
  baselineSha: '743c4b73fa56412c81dd6143ce4875393828785aad810ec4d9d09bf14cfaf91b', candidateSha: 'a11deb298610f8980e5e8247387e889718ec8a9bda1d7b8ae90ec5b15e2ebb72'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
