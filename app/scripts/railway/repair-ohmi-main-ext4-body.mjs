#!/usr/bin/env node
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {displayCandidateRepair, REPO} from './lib/display-candidate-repair.mjs';
export const SPEC={lineID:'jp-近江鉄道-本線',key:'ohmi-main-ext4-body',authorityPath:path.join(REPO,'railway-evidence/local/proposals/ext4-20261022/authority-ext4-ohmi-body.json'),
  format:'jtm-ext4-ohmi-body-authority-v1',receiptFormat:'jtm-ext4-ohmi-body-candidate-review-v1',
  stationIDs:['005075','005131','005147','005176','005201','005221','005263','005316','005357','005428','005514','005572','005710','005731','005754','005787','005830','005875','005948','006097','006119','006134','006140'],
  intervalIndices:[0,1,2,3,4,5,6,7,8,9,10,13,14,15,16,17,18,19,20,21,22],baselineSha:'ce217fe720dc61d0fdaa255cd8b3ecd0dc26b56b81f01d34bc0263c34bbc6d72',candidateSha:'0972451644ac5338213b09ed7729db3b672369443e9d0ced3b6302066df45d51'};
export const {AUTHORITY_PATH,repairPackage,repairParts,validateCandidateReview,main}=displayCandidateRepair(SPEC);
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2),fileURLToPath(import.meta.url));
