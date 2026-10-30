#!/usr/bin/env node
// repair-09 bounded display repair: jp-山万-ユーカリが丘線-2 display intervals 0,1, aliases 003386,003429,003452.
// Evidence: railway-evidence/local/proposals/yamaman-yukarigaoka-2-20261021/bounded-yamaman-yukarigaoka-2-z20-authority-v1.json. Candidate only until --apply --candidate-review <receipt>; never run by repair chats.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {makeRepair, REPO} from './repair09-display-common.mjs';

export const CONFIG = Object.freeze({...{"key":"repair09-yamaman-yukarigaoka-2-z20","lineID":"jp-山万-ユーカリが丘線-2","format":"jtm-repair09-yamaman-yukarigaoka-2-z20-authority-v1","receiptFormat":"jtm-repair09-yamaman-yukarigaoka-2-z20-candidate-review-v1","stationIDs":["003386","003429","003452"],"intervalIndices":[0,1],"displayIntervals":[0,1],"baselineSha":"a1c9c97e2b6e5a7da3e24d0575c882ceedae5e943226e82617cc6d0c02c5ad31","candidateSha":"5dfd377ae4fb5de92c3b0d1552b562ed8a5a85774373e40ae1e776ad55c928a6","nativeSha":"a748f2ae453a543ccd2be99d3f75447d6df7c4c5ad85d9a9809c4ead0262c6ac","parts":{"baseline":[29],"candidate":[118],"prefix":0,"suffix":0},"supportCount":6,"script":"repair-yamaman-yukarigaoka-2-z20.mjs"}, authorityPath: path.join(REPO, "railway-evidence/local/proposals/yamaman-yukarigaoka-2-20261021/bounded-yamaman-yukarigaoka-2-z20-authority-v1.json")});
export const AUTHORITY_PATH = CONFIG.authorityPath;
const repair = makeRepair(CONFIG);
export const {repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) repair.main(process.argv.slice(2));
