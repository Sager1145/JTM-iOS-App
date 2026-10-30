#!/usr/bin/env node
// JR West Sakurai Line (高田–奈良): reviewed v6 whole-line display geometry on Apple track (repair-07 glyph extracts + 桜井 north JR track + 天理 yard/station on the labelled track).
// Display-only (physical source unchanged); reviewed r0708 candidate v6. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-西日本旅客鉄道-桜井線", key: "jrw-sakurai-r0708-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/jr-west-sakurai-20261021/takeover-v6/jrw-sakurai-r0708-authority.json"),
  format: "jtm-r0708-jrw-sakurai-v6-authority-v1", receiptFormat: "jtm-r0708-jrw-sakurai-v6-candidate-review-v1",
  stationIDs: ["007802","007823","007827","007820","007810","007783","007742","007708","007671","007601","007545","007458","007286","007210"],
  intervalIndices: [0,1,2,3,4,5,6,7,8,9,10,11,12],
  baselineSha: '63bba943f7e28f3be344a44bd139f99b9add8594af013ddb04b3ca88dd39405c',
  candidateSha: '3c25a547da894eead36bb75a06db3e43b401e4eb8f10095d528b322e490fb56e',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
