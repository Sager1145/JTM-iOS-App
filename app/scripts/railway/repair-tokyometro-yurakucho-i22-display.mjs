#!/usr/bin/env node
// repair-09 bounded display repair: jp-東京地下鉄-8号線有楽町線 display intervals 21,22, aliases 003999.
// Evidence: railway-evidence/local/proposals/tokyometro-yurakucho-20261021/bounded-tokyometro-yurakucho-i22-display-authority-v1.json. Candidate only until --apply --candidate-review <receipt>; never run by repair chats.
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {makeRepair, REPO} from './repair09-display-common.mjs';

export const CONFIG = Object.freeze({...{"key":"repair09-tokyometro-yurakucho-i22-display","lineID":"jp-東京地下鉄-8号線有楽町線","format":"jtm-repair09-tokyometro-yurakucho-i22-display-authority-v1","receiptFormat":"jtm-repair09-tokyometro-yurakucho-i22-display-candidate-review-v1","stationIDs":["003999"],"intervalIndices":[21,22],"displayIntervals":[21,22],"baselineSha":"459ad56cc384751ccb00c5326fe087329cc1463d1b30034e408303bbdcd56499","candidateSha":"0d7e0722973606ed6fd87773c861b8bcb5faf727639480bbd3fd159e94f0eca9","nativeSha":"a600634a2ed6e2da78ee6c2e5cc5e5c3b3408446f1184bee09c84cf6b62683c5","parts":{"baseline":[367],"candidate":[398],"prefix":352,"suffix":1},"supportCount":45,"script":"repair-tokyometro-yurakucho-i22-display.mjs"}, authorityPath: path.join(REPO, "railway-evidence/local/proposals/tokyometro-yurakucho-20261021/bounded-tokyometro-yurakucho-i22-display-authority-v1.json")});
export const AUTHORITY_PATH = CONFIG.authorityPath;
const repair = makeRepair(CONFIG);
export const {repairPackage, repairParts, validateCandidateReview} = repair;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) repair.main(process.argv.slice(2));
