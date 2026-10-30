#!/usr/bin/env node
// repair-09 bounded display repair: jp-山万-ユーカリが丘線-2 display intervals 0,1, aliases 003386,003429,003452.
// Evidence: railway-evidence/local/proposals/yamaman-yukarigaoka-2-20261021/bounded-yamaman-yukarigaoka-2-display-authority-v1.json. Candidate only until --apply --candidate-review <receipt>; never run by repair chats.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {makeRepair, REPO} from './repair09-display-common.mjs';

export const CONFIG = Object.freeze({...{"key":"repair09-yamaman-yukarigaoka-2-display","lineID":"jp-山万-ユーカリが丘線-2","format":"jtm-repair09-yamaman-yukarigaoka-2-display-authority-v1","receiptFormat":"jtm-repair09-yamaman-yukarigaoka-2-display-candidate-review-v1","stationIDs":["003386","003429","003452"],"intervalIndices":[0,1],"displayIntervals":[0,1],"baselineSha":"dd5700ded47a23e20ed25962bac80d4f3fc8d4375cd428bf98095f593d584c3d","candidateSha":"a1c9c97e2b6e5a7da3e24d0575c882ceedae5e943226e82617cc6d0c02c5ad31","nativeSha":"8e6e77d5942ba749413cb9f067c741fa5144f5f30e59e0f2434d719491107461","parts":{"baseline":[28],"candidate":[29],"prefix":0,"suffix":0},"supportCount":29,"script":"repair-yamaman-yukarigaoka-2-display.mjs"}, authorityPath: path.join(REPO, "railway-evidence/local/proposals/yamaman-yukarigaoka-2-20261021/bounded-yamaman-yukarigaoka-2-display-authority-v1.json")});
export const AUTHORITY_PATH = CONFIG.authorityPath;
const repair = makeRepair(CONFIG);
export const {repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) repair.main(process.argv.slice(2));
