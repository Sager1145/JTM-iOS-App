#!/usr/bin/env node
// Tarumi Line own Apple glyph display re-trace
// Display-only (physical source unchanged); reviewed candidate v1 from railway-evidence/local/proposals/tarumi-20261021. Apply only with a candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

const repair = displayCandidateRepair({
  lineID: "jp-樽見鉄道-樽見線", key: "tarumi-own-glyph-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/tarumi-20261021/authority-v1.json"),
  format: "jtm-tarumi-own-glyph-display-authority-v1", receiptFormat: "jtm-tarumi-own-glyph-display-candidate-review-v1",
  stationIDs: ["004233","004280","004871"], intervalIndices: [2,3,15,16],
  baselineSha: '89a1eb45a377dba9c09939a47d86511006c744051f862478d3d132fb6cc7ffb5',
  candidateSha: '5b0aed325db0a3c16e336bc6df8970d49f0d1fec71f87fd4c1fca203450efe9e',
});
export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  repair.main(process.argv.slice(2), fileURLToPath(import.meta.url));
