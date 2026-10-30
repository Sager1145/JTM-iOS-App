#!/usr/bin/env node
// repair-09 bounded display repair: jp-東京都-日暮里・舎人ライナー display intervals 0,1,2,3,4,5,6, aliases 003298,003266,003235,003209,003368,003196.
// Evidence: railway-evidence/local/proposals/toei-toneri-20261021/bounded-toei-toneri-20261021-z20-authority-v1.json. Candidate only until --apply --candidate-review <receipt>; never run by repair chats.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {makeRepair, REPO} from './repair09-display-common.mjs';

export const CONFIG = Object.freeze({...{"key":"repair09-toei-toneri-20261021-z20","lineID":"jp-東京都-日暮里・舎人ライナー","format":"jtm-repair09-toei-toneri-20261021-z20-authority-v1","receiptFormat":"jtm-repair09-toei-toneri-20261021-z20-candidate-review-v1","stationIDs":["003298","003266","003235","003209","003368","003196"],"intervalIndices":[0,1,2,3,4,5,6],"displayIntervals":[0,1,2,3,4,5,6],"baselineSha":"d9a3a6e76da142d2ce1cf1b52bb777449fbb6ba46533c00577c794c717149916","candidateSha":"0cefa2e5e245fb5fb345cc3a972441b5b49b1a79092fa0c708e0cc49bf809daa","nativeSha":"befc83332c41bf5aa20afad63922b640c3be4f34b680806adcf75beb7a3ec352","parts":{"baseline":[66],"candidate":[239],"prefix":7,"suffix":26},"supportCount":224,"script":"repair-toei-toneri-20261021-z20.mjs"}, authorityPath: path.join(REPO, "railway-evidence/local/proposals/toei-toneri-20261021/bounded-toei-toneri-20261021-z20-authority-v1.json")});
export const AUTHORITY_PATH = CONFIG.authorityPath;
const repair = makeRepair(CONFIG);
export const {repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) repair.main(process.argv.slice(2));
