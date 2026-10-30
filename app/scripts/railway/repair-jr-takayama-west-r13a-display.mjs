#!/usr/bin/env node
// jp-西日本旅客鉄道-高山線: display intervals 0,1,2,3,4,5,6,7,8 and 10 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-西日本旅客鉄道-高山線", key: "jr-takayama-west-r13a-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/repair-13a-20261021/takayama-w/jr-takayama-west-r13a-authority.json"),
  format: "jtm-jr-takayama-west-r13a-authority-v1", receiptFormat: "jtm-jr-takayama-west-r13a-candidate-review-v1",
  stationIDs: ["001925","001932","001981","002002","002043","002077","002080","002111","002158","002200"], intervalIndices: [0,1,2,3,4,5,6,7,8],
  baselineSha: '85a7393d8c7747a4a0968105d4d4db2d936ba61b073d1d80228e4ee95bda7d6b', candidateSha: 'dfc5cf3526fd3655b00d9e8da70283f941199d1cb1674365826a43bad3278a01'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
