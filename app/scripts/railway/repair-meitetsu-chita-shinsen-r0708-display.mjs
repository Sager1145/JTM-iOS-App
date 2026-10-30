#!/usr/bin/env node
// Meitetsu Chita New Line (富貴–内海): reviewed v7 whole-line display geometry on Apple's drawn track (repair-07 glyph-extract build; 富貴 junction hand picks; i0 label stretch off the river glyph).
// Display-only (physical source unchanged); reviewed r0708 candidate v7. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-名古屋鉄道-知多新線", key: "meitetsu-chita-shinsen-r0708-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/meitetsu-chita-shinsen-20261021/takeover-v6/meitetsu-chita-shinsen-r0708-authority.json"),
  format: "jtm-r0708-meitetsu-chita-shinsen-v7-authority-v1", receiptFormat: "jtm-r0708-meitetsu-chita-shinsen-v7-candidate-review-v1",
  stationIDs: ["006857","006735","006690","006628","006599","006492"],
  intervalIndices: [0,1,2,3,4],
  baselineSha: 'd6eddad6acea42e5c8290e104eb6c5305870c6a75bd1b8d68b0cfdca25095da5',
  candidateSha: 'df5926dfb9b08160a5396fa39e2cfe531f0f630ca0cc1c940d3a077a45deaeea',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
