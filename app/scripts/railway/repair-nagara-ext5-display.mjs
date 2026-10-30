#!/usr/bin/env node
// Nagaragawa Railway Etsumi-Nan Line: reviewed v10 whole-line trace on Apple's own rail; 美濃太田 ends on the last visible own rail.
// Display-only (physical source unchanged); reviewed ext5 candidate v10. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-長良川鉄道-越美南線", key: "nagara-ext5-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/ext5-20261022/nagara-v10/nagara-ext5-authority.json"),
  format: "jtm-ext5-nagara-v10-authority-v1", receiptFormat: "jtm-ext5-nagara-v10-candidate-review-v1",
  stationIDs: ["004693","004681","004651","004592","004588","004573","004552","004526","004477","004442","004369","004311","004265","004243","004211","004134","004100","004046","003994","003912","003825","003720","003494","003185","003122","003079","003057","003031","003013","002996","002944","002896","002882","002864","002973","003308","004402","004605"],
  intervalIndices: [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36],
  baselineSha: 'e1d0117a9a510aee56f596c576d58f30be2eb91718098a2683f24d8e1f781026',
  candidateSha: '2e8ecf77e4279061871450347ae5b7fcb029c8d707aa98403b3dd157664e7d21',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
