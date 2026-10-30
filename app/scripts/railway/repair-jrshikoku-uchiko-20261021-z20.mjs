#!/usr/bin/env node
// repair-09 bounded display repair: jp-四国旅客鉄道-内子線 display intervals 0,1,2, aliases 009213,009215,009206,009179.
// Evidence: railway-evidence/local/proposals/jrshikoku-uchiko-20261021/bounded-jrshikoku-uchiko-20261021-z20-authority-v1.json. Candidate only until --apply --candidate-review <receipt>; never run by repair chats.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {makeRepair, REPO} from './repair09-display-common.mjs';

export const CONFIG = Object.freeze({...{"key":"repair09-jrshikoku-uchiko-20261021-z20","lineID":"jp-四国旅客鉄道-内子線","format":"jtm-repair09-jrshikoku-uchiko-20261021-z20-authority-v1","receiptFormat":"jtm-repair09-jrshikoku-uchiko-20261021-z20-candidate-review-v1","stationIDs":["009213","009215","009206","009179"],"intervalIndices":[0,1,2],"displayIntervals":[0,1,2],"baselineSha":"3ad6ffbb7ba048561346d5fe50fec00d2d8c208a05cdace845e01d811b4bb8c6","candidateSha":"1179d2c55964c0a2e0f5d5447f6a55c4550a0b5a757c63342d9de5cfe89269a0","nativeSha":"986d937fe05140663a545cff764b36e2f7ad735849984fed337dd025cbfa472e","parts":{"baseline":[96],"candidate":[229],"prefix":0,"suffix":0},"supportCount":168,"script":"repair-jrshikoku-uchiko-20261021-z20.mjs"}, authorityPath: path.join(REPO, "railway-evidence/local/proposals/jrshikoku-uchiko-20261021/bounded-jrshikoku-uchiko-20261021-z20-authority-v1.json")});
export const AUTHORITY_PATH = CONFIG.authorityPath;
const repair = makeRepair(CONFIG);
export const {repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) repair.main(process.argv.slice(2));
