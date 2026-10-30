#!/usr/bin/env node
// Jukkoku cable: whole-line rebuild on the Apple cable glyph; termini at the visible glyph ends at the platform edges.
// Display-only (physical source unchanged); reviewed r56 candidate v3. Apply only with the candidate-review receipt.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {
  lineID: "jp-十国峠-十国鋼索線", key: "jukkoku-r56-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/r56-takeover-20261023/jukkoku/jukkoku-r56-authority.json"),
  format: "jtm-r56-jukkoku-v3-authority-v1", receiptFormat: "jtm-r56-jukkoku-v3-candidate-review-v1",
  stationIDs: ["005594","005595"],
  intervalIndices: [0],
  baselineSha: '6820f57e046bac6ec1a65792660a96659eb8c111576ddad53c84acd912e30687',
  candidateSha: '95c14111adc514852790a5427646db8736d7545845cee47cd4a9216c29b8b778',
};

export const {AUTHORITY_PATH, proposedLine, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2), fileURLToPath(import.meta.url));
