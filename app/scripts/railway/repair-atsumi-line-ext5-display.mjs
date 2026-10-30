#!/usr/bin/env node
// Toyohashi Railroad Atsumi Line: reviewed v13 whole-line display trace on Apple's own labelled rail.
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: 'jp-豊橋鉄道-渥美線',
  key: 'atsumi-line-ext5-display',
  authorityPath: path.join(REPO, 'railway-evidence/local/proposals/ext5-20261022/atsumi-v13/atsumi-ext5-authority.json'),
  format: 'jtm-ext5-atsumi-v13-authority-v1',
  receiptFormat: 'jtm-ext5-atsumi-v13-candidate-review-v1',
  stationIDs: ['006789', '006816', '006839', '006864', '006899', '006938', '006984', '007017', '007045', '007101', '007134', '007214', '007270', '007302', '007299', '007314'],
  intervalIndices: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14],
  baselineSha: '295bb5ea55f28cd6cf0ab3f59285fe62ef5915b33a0e4ad44dc7b648ae10b807',
  candidateSha: '225f99f9ca635fcc4a858ee52e6587a8386a96f1e6c5a0f7f742145d11bf7a33',
};

export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
