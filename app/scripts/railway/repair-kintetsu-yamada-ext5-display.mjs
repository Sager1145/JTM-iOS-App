#!/usr/bin/env node
// Kintetsu Yamada Line: reviewed v12 whole-line trace; i11 follows Apple's drawn north rail under the label.
// Display-only (physical source unchanged); reviewed ext5 candidate v12. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-近畿日本鉄道-山田線", key: "kintetsu-yamada-ext5-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/ext5-20261022/yamada-v12/kintetsu-yamada-ext5-authority.json"),
  format: "jtm-ext5-kintetsu-yamada-v12-authority-v1", receiptFormat: "jtm-ext5-kintetsu-yamada-v12-candidate-review-v1",
  stationIDs: ["007488","007566","007620","007695","007737","007753","007757","007814","007857","007869","007664","007774","007793","007844"],
  intervalIndices: [0,1,2,3,4,5,6,7,8,9,10,11,12],
  baselineSha: 'fa490a46559eefb138bdc31af733af54b1c93d9b20ce87cae016df57349b2d39',
  candidateSha: '0af330ec9b5399d2562582cb7b27d561f38e06bbb0cab23855d1fcba8d4e63c9',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
