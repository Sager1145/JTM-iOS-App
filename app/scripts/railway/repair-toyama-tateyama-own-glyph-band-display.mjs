#!/usr/bin/env node
// Tateyama Line own Apple glyph band-centre display re-trace
// Display-only (physical source unchanged); reviewed candidate v2 from railway-evidence/local/proposals/toyama-tateyama-20261021. Apply only with a candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

const repair = displayCandidateRepair({
  lineID: "jp-富山地方鉄道-立山線", key: "toyama-tateyama-own-glyph-band-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/toyama-tateyama-20261021/authority-v2.json"),
  format: "jtm-toyama-tateyama-own-glyph-band-display-authority-v2", receiptFormat: "jtm-toyama-tateyama-own-glyph-band-display-candidate-review-v2",
  stationIDs: ["002064","002054","002044","002027","002012"], intervalIndices: [4,5,6,7,8,9],
  baselineSha: '2467c39471a3df1db4fe2dde624cb35136de799bf9f387a9dc0207e228f0eadb',
  candidateSha: '124e4ed30365fdeda77588ff7f1ed4ca86c02d97494548f037423df75f7944d7',
});
export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  repair.main(process.argv.slice(2), fileURLToPath(import.meta.url));
