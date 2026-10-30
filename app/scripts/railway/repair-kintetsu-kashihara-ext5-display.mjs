#!/usr/bin/env node
// Kintetsu Kashihara Line: reviewed v9 whole-line trace; 橿原神宮前 approach follows the ticked curve onto its own platform track.
// Display-only (physical source unchanged); reviewed ext5 candidate v9. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-近畿日本鉄道-橿原線", key: "kintetsu-kashihara-ext5-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/ext5-20261022/kashihara-v9/kintetsu-kashihara-ext5-authority.json"),
  format: "jtm-ext5-kintetsu-kashihara-v9-authority-v1", receiptFormat: "jtm-ext5-kintetsu-kashihara-v9-candidate-review-v1",
  stationIDs: ["007117","007208","007282","007374","007448","007585","007612","007645","007681","007725","007749","007811","007822","007855","007878","007548","007787"],
  intervalIndices: [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],
  baselineSha: '9f9dc63cf26403994958fb7e0b9d9d8137f56987145f60f7ff97ee5c882ba24c',
  candidateSha: 'fe92794b70d61fe1a6fe577945402dc4e1791e17a9a463df0b6d95a6b7ecae87',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
