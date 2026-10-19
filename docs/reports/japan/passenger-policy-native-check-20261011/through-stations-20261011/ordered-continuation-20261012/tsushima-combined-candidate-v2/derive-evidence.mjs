// Scoped candidate-only evidence derivation; never writes a production input.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { LINE_IDS, INTERVAL_INDEXES, INTERVAL_IDS, physicalLine, jsonSha256,
  validateCandidate, repairPackage, deriveNativeRows, measuredReferences,
  deriveCandidateMeasuredReferences, candidateGeoJSON }
  from '../../../../../../../app/scripts/railway/repair-tsushima-sukaguchi-display.mjs';
const own = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(own, '../../../../../../..');
const candidateFile = path.join(own, 'candidate.json');
const candidateBytes = fs.readFileSync(candidateFile);
const candidate = JSON.parse(candidateBytes);
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'app/public/rail/jp-2025.json')));
const lanes = JSON.parse(fs.readFileSync(path.join(root, 'app/public/rail/display-lanes.json')));
const baseline = { packageIndices: {}, lineSha256: {}, displayIntervals: {}, displayStations: {},
  nativeRowsSha256: {}, measuredReferences: measuredReferences(lanes) };
const owners = {};
for (const id of LINE_IDS) {
  const index = pkg.lines.findIndex(l => l.id === id); assert(index >= 0);
  const line = pkg.lines[index]; const intervals = INTERVAL_INDEXES[id];
  baseline.packageIndices[id] = index;
  baseline.lineSha256[id] = jsonSha256(physicalLine(line));
  baseline.displayIntervals[id] = line.displayIntervalCoordinates || {};
  baseline.displayStations[id] = line.displayStationCoordinates || {};
  baseline.nativeRowsSha256[id] = jsonSha256(lanes.partsByRegion.jp.filter(row => row[0] === id));
  owners[id] = { intervalIndexes: [...intervals],
    stationIDs: line.stations.slice(intervals[0], intervals.at(-1) + 2).map(s => s[0]) };
}
const evidence = { format: 'jtm-tsushima-sukaguchi-display-v1', status: 'candidate-only',
  reviewedAt: fs.existsSync(path.join(own, 'evidence.json')) ? JSON.parse(fs.readFileSync(path.join(own, 'evidence.json'))).reviewedAt : new Date().toISOString(),
  candidate: { file: candidateFile, sha256: crypto.createHash('sha256').update(candidateBytes).digest('hex') },
  owners, baseline };
validateCandidate(candidate, evidence);
const repaired = repairPackage(pkg, evidence);
const rows = deriveNativeRows(repaired, evidence);
const mapped = deriveCandidateMeasuredReferences(pkg, repaired, lanes, evidence);
evidence.nativeReplay = { candidateRowsSha256: Object.fromEntries(LINE_IDS.map(id => [id, jsonSha256(rows[id])])),
  candidateMeasuredReferences: mapped };
const network = createRequire(import.meta.url)(path.join(root, 'app/public/rail-network.js'));
const mainID = LINE_IDS[1], mainIndex = baseline.packageIndices[mainID];
const beforeMain = pkg.lines[mainIndex], afterMain = repaired.lines[mainIndex];
const oldParts = network.displayPartsForLine(beforeMain), newParts = network.displayPartsForLine(afterMain);
assert(oldParts.length === 1 && newParts.length === 1);
const oldPoints = oldParts[0], newPoints = newParts[0];
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const stationPoint = (line,i) => line.displayStationCoordinates?.[line.stations[i][0]] || line.stations[i].slice(2,4);
const vertex = (points,p) => { const indexes=points.flatMap((q,i)=>equal(p,q)?[i]:[]);assert(indexes.length===1);return indexes[0]; };
const cumulative = points => {const out=[0];for(let i=1;i<points.length;i++){const a=points[i-1],b=points[i];out.push(out.at(-1)+Math.hypot((b[0]-a[0])*111320*Math.cos((a[1]+b[1])*Math.PI/360),(b[1]-a[1])*111320));}return out;};
const om=cumulative(oldPoints),nm=cumulative(newPoints),oldStart=vertex(oldPoints,stationPoint(beforeMain,16)),oldEnd=vertex(oldPoints,stationPoint(beforeMain,24)),newStart=vertex(newPoints,stationPoint(afterMain,16)),newEnd=vertex(newPoints,stationPoint(afterMain,24));
const oldMeasure=29575,interval=INTERVAL_INDEXES[mainID].find(i=>oldMeasure>=om[vertex(oldPoints,stationPoint(beforeMain,i))]&&oldMeasure<=om[vertex(oldPoints,stationPoint(beforeMain,i+1))]);
assert(interval===22,'29575 witness no longer belongs to Main#22');
const oldEdgeEnd=om.findIndex(v=>v>=oldMeasure),fraction=(oldMeasure-om[oldEdgeEnd-1])/(om[oldEdgeEnd]-om[oldEdgeEnd-1]);
const oldGeo=oldPoints[oldEdgeEnd-1].map((v,axis)=>v+(oldPoints[oldEdgeEnd][axis]-v)*fraction);
const from=vertex(newPoints,stationPoint(afterMain,interval)),to=vertex(newPoints,stationPoint(afterMain,interval+1)),cos=Math.cos(oldGeo[1]*Math.PI/180),local=p=>[(p[0]-oldGeo[0])*111320*cos,(p[1]-oldGeo[1])*111320];let best;
for(let i=from+1;i<=to;i++){const a=local(newPoints[i-1]),b=local(newPoints[i]),dx=b[0]-a[0],dy=b[1]-a[1],d2=dx*dx+dy*dy;if(!d2)continue;const t=Math.max(0,Math.min(1,-(a[0]*dx+a[1]*dy)/d2)),residual=Math.hypot(a[0]+t*dx,a[1]+t*dy);if(!best||residual<best.residual)best={edgeEnd:i,fraction:t,residual,newMeasure:nm[i-1]+t*(nm[i]-nm[i-1]),newGeo:newPoints[i-1].map((v,axis)=>v+(newPoints[i][axis]-v)*t)};}
assert(best);
const witness={lineID:mainID,intervalIndex:interval,oldMeasure,oldGeo,oldEdgeEnd,oldEdgeFraction:fraction,newGeo:best.newGeo,newMeasure:Number(best.newMeasure.toFixed(1)),unroundedNewMeasure:best.newMeasure,newEdgeEnd:best.edgeEnd,newEdgeFraction:best.fraction,projectionResidualMetres:best.residual,ownedCandidateIntervalMeasures:[nm[from],nm[to]],suffixDeltaMetres:nm[newEnd]-om[oldEnd],prefixExact:equal(newPoints.slice(0,newStart+1),oldPoints.slice(0,oldStart+1)),suffixExact:equal(newPoints.slice(newEnd),oldPoints.slice(oldEnd)),warnings:['Nearest projection is constrained to Main#22; residual is original-to-candidate geographic displacement, not Apple pixel residual.','Station/frame/underground raw warnings retained; native acceptance remains pending.']};
const pretty = value => JSON.stringify(value, null, 2) + '\n';
fs.writeFileSync(path.join(own, 'evidence.json'), pretty(evidence));
fs.writeFileSync(path.join(own, 'candidate-native-rows.json'), pretty(rows));
fs.writeFileSync(path.join(own, 'measured-reference-witness-29575.json'), pretty(witness));
fs.writeFileSync(path.join(own, 'candidate-measured-references.json'), pretty(mapped));
fs.writeFileSync(path.join(own, 'candidate.geojson'), pretty(candidateGeoJSON(repaired, evidence)));
fs.writeFileSync(path.join(own, 'derivation-receipt.json'), pretty({ status: 'candidate-only',
  candidateSha256: evidence.candidate.sha256, intervalIDs: INTERVAL_IDS,
  physicalOwnerLinesExact: LINE_IDS.every(id => JSON.stringify(physicalLine(pkg.lines[baseline.packageIndices[id]])) === JSON.stringify(physicalLine(repaired.lines[baseline.packageIndices[id]]))),
  candidateRowsSha256: evidence.nativeReplay.candidateRowsSha256,
  nativeRowsCount: Object.fromEntries(LINE_IDS.map(id => [id, rows[id].length])),
  measuredReferencesMappedWithinOwnIntervals: true, productionInputsChanged: false, nativeAccepted: false }));
console.log(JSON.stringify({ status: 'candidate-only', candidateSha256: evidence.candidate.sha256,
  candidateRowsSha256: evidence.nativeReplay.candidateRowsSha256,
  nativeRowsCount: Object.fromEntries(LINE_IDS.map(id => [id, rows[id].length])) }));
