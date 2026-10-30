#!/usr/bin/env node
// repair-09 bounded display repair: jp-東京都-日暮里・舎人ライナー display intervals 2,3, aliases 003266.
// Evidence: railway-evidence/local/proposals/toei-toneri-20261021/bounded-toei-toneri-kumanomae-z20-authority-v1.json. Candidate only until --apply --candidate-review <receipt>; never run by repair chats.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {makeRepair, REPO} from './repair09-display-common.mjs';

export const CONFIG = Object.freeze({...{"key":"repair09-toei-toneri-kumanomae-z20","lineID":"jp-東京都-日暮里・舎人ライナー","format":"jtm-repair09-toei-toneri-kumanomae-z20-authority-v1","receiptFormat":"jtm-repair09-toei-toneri-kumanomae-z20-candidate-review-v1","stationIDs":["003266"],"intervalIndices":[2,3],"displayIntervals":[2,3],"baselineSha":"0cefa2e5e245fb5fb345cc3a972441b5b49b1a79092fa0c708e0cc49bf809daa","candidateSha":"338008aa6c18766ded27ebe759526f23b8c58972dfcf5b6e9aca23a3e7257d44","nativeSha":"9430eee00833cc82001c461cee0166a4f9c5f0ad5550c466128a11cd3c1d9204","parts":{"baseline":[239],"candidate":[239],"prefix":91,"suffix":147},"supportCount":0,"script":"repair-toei-toneri-kumanomae-z20.mjs"}, authorityPath: path.join(REPO, "railway-evidence/local/proposals/toei-toneri-20261021/bounded-toei-toneri-kumanomae-z20-authority-v1.json")});
export const AUTHORITY_PATH = CONFIG.authorityPath;
const repair = makeRepair(CONFIG);
export const {repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) repair.main(process.argv.slice(2));
