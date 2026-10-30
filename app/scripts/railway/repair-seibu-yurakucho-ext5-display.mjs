#!/usr/bin/env node
// Seibu Yurakucho Line: reviewed v6 whole-line trace on Apple's pale subway line; 練馬 starts where the own line becomes visible.
// Display-only (physical source unchanged); reviewed ext5 candidate v6. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-西武鉄道-西武有楽町線", key: "seibu-yurakucho-ext5-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/ext5-20261022/yurakucho-v6/seibu-yurakucho-ext5-authority.json"),
  format: "jtm-ext5-seibu-yurakucho-v6-authority-v1", receiptFormat: "jtm-ext5-seibu-yurakucho-v6-candidate-review-v1",
  stationIDs: ["003328","003294","003311"],
  intervalIndices: [0,1],
  baselineSha: '4ecdb1bc2a9d0f1c416b4998350f365940cb2af694ee03e19b22fc8602f64e15',
  candidateSha: '93965f6cee0350b9e21cb9be55830a7ae15ce31227e2c9b037e00751612a76da',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
