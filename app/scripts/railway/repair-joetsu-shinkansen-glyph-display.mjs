#!/usr/bin/env node
// jp-東日本旅客鉄道-上越新幹線: display intervals 0,1,2,3,4,5,6,7,8 and 10 aliases on Apple's own rail glyph (repair-06).
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';

export const SPEC = {lineID: "jp-東日本旅客鉄道-上越新幹線", key: "joetsu-shinkansen-glyph-display",
  authorityPath: path.join(REPO, "railway-evidence/local/proposals/joetsu-shinkansen-20261021/joetsu-shinkansen-glyph-authority-v3.json"),
  format: "jtm-joetsu-shinkansen-glyph-authority-v1", receiptFormat: "jtm-joetsu-shinkansen-glyph-candidate-review-v1",
  stationIDs: ["001296","001406","001489","001603","001717","001952","002389","002525","002589","002914"], intervalIndices: [0,1,2,3,4,5,6,7,8],
  baselineSha: 'e90c323561107bd2fd9fb58d267a4f569e284fff3376e6ac6c6fcfa05958fc0b', candidateSha: 'ea730574e7d615176682cd8e23683a6eecf60a889cb03611245804cc464097a2'};
export const {AUTHORITY_PATH, repairPackage, repairParts, validateCandidateReview, main} = displayCandidateRepair(SPEC);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2), fileURLToPath(import.meta.url));
