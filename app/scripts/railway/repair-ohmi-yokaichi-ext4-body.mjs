#!/usr/bin/env node
// ext4: reviewed 八日市線 body and 近江八幡 end; interval 0 / shared 八日市 remain baseline.
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: 'jp-近江鉄道-八日市線', key: 'ohmi-yokaichi-ext4-body',
  authorityPath: path.join(REPO, 'railway-evidence/local/proposals/ext4-20261022/authority-ext4-yokaichi-body.json'),
  format: 'jtm-ext4-yokaichi-body-authority-v1', receiptFormat: 'jtm-ext4-yokaichi-body-candidate-review-v1',
  stationIDs: ['005665', '005669', '005687', '005666', '005647', '005619'], intervalIndices: [1, 2, 3, 4, 5],
  baselineSha: 'dfb3e786dffea3352b3bddabbeb65c17825aa7491cea4b3811a0ab6218e7402d', candidateSha: 'f77111d5aae04c5398a5b122c6425f53e8d487b0f39b698e96a12bb680621514'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
