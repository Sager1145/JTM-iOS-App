#!/usr/bin/env node
// repair-09 bounded display repair: jp-四日市あすなろう鉄道-八王子線 display intervals 0, aliases 006182,006174.
// Evidence: railway-evidence/local/proposals/asunarou-hachioji-20261021/bounded-asunarou-hachioji-z20-authority-v1.json. Candidate only until --apply --candidate-review <receipt>; never run by repair chats.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {makeRepair, REPO} from './repair09-display-common.mjs';

export const CONFIG = Object.freeze({...{"key":"repair09-asunarou-hachioji-z20","lineID":"jp-四日市あすなろう鉄道-八王子線","format":"jtm-repair09-asunarou-hachioji-z20-authority-v1","receiptFormat":"jtm-repair09-asunarou-hachioji-z20-candidate-review-v1","stationIDs":["006182","006174"],"intervalIndices":[0],"displayIntervals":[0],"baselineSha":"e0e8129c76987b55082544d60b00ebaa2e31112f54589f655c48614317a9a48d","candidateSha":"b75855a3c8f3dcd351d82b3c48dfcd13b280fc4787bb4cd8b39c5f10c591acd5","nativeSha":"0b39f3454d2b0cea10c78b17a45f5bfa56c5c5e40bb441bd7c64919cd2876fcb","parts":{"baseline":[14],"candidate":[72],"prefix":0,"suffix":0},"supportCount":6,"script":"repair-asunarou-hachioji-z20.mjs"}, authorityPath: path.join(REPO, "railway-evidence/local/proposals/asunarou-hachioji-20261021/bounded-asunarou-hachioji-z20-authority-v1.json")});
export const AUTHORITY_PATH = CONFIG.authorityPath;
const repair = makeRepair(CONFIG);
export const {repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) repair.main(process.argv.slice(2));
