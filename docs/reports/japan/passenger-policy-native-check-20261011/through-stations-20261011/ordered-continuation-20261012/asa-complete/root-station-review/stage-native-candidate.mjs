import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const root=process.cwd(), id='jp-土佐くろしお鉄道-阿佐線';
const report=path.join(root,'docs/reports/japan/passenger-policy-native-check-20261011/through-stations-20261011/ordered-continuation-20261012/asa-complete/root-station-review');
const candidateFile=process.argv[2] ? path.resolve(process.argv[2]) : path.join(report,'candidate-all-20-intervals-v2.json');
const candidate=JSON.parse(fs.readFileSync(candidateFile));
assert.equal(candidate.nativeAcceptance,false);assert.equal(candidate.intervals.length,20);assert.equal(Object.keys(candidate.displayStationCoordinates).length,21);
const source=path.join(root,'app/public/rail'), stage=process.argv[3] ? path.resolve(process.argv[3]) : path.join(root,'.build/asa-native-candidate-v2/rail');fs.mkdirSync(stage,{recursive:true});
for(const f of fs.readdirSync(source).filter(f=>f.endsWith('.json'))){const t=path.join(stage,f);if(!fs.existsSync(t))fs.symlinkSync(path.join(source,f),t);}
const pkg=JSON.parse(fs.readFileSync(path.join(source,'jp-2025.json'))), lanes=JSON.parse(fs.readFileSync(path.join(source,'display-lanes.json')));
const line=pkg.lines.find(l=>l.id===id);assert(line && line.stations.length===21 && line.segments.length===20);
const physical=structuredClone(line);line.displayStationCoordinates=structuredClone(candidate.displayStationCoordinates);line.displayIntervalCoordinates=Object.fromEntries(candidate.intervals.map((r,i)=>{assert.equal(r.intervalIndex,i);assert.deepEqual(r.coordinates[0],candidate.displayStationCoordinates[line.stations[i][0]]);assert.deepEqual(r.coordinates.at(-1),candidate.displayStationCoordinates[line.stations[i+1][0]]);return [i,r.coordinates];}));
const strip=l=>{const p=structuredClone(l);delete p.displayIntervalCoordinates;delete p.displayStationCoordinates;return p;};assert.deepEqual(strip(line),strip(physical));
const network=createRequire(import.meta.url)(path.join(root,'app/public/rail-network.js'));
assert.deepEqual(network.decodeIntervals(line),network.decodeIntervals(physical));
const {partRowsForLine}=await import(path.join(root,'app/scripts/railway/build-display-lanes.mjs'));
const stations=line.stations.map(row=>[...row.slice(0,2),...line.displayStationCoordinates[row[0]],...row.slice(4)]);
const rows=partRowsForLine(line,network.displayPartsForLine(line),{stations,intervals:candidate.intervals.map(x=>x.coordinates)},null);
assert(rows.length>0);
for(const [key,value] of Object.entries(lanes)){if(key==='partsByRegion')continue;assert(!JSON.stringify(value).includes(id),`Measured reference requires coordinated remap: ${key}`);}
let inserted=false;lanes.partsByRegion.jp=lanes.partsByRegion.jp.flatMap(row=>{if(row[0]!==id)return [row];if(inserted)return [];inserted=true;return rows;});assert(inserted);
for(const [name,data] of [['jp-2025.json',pkg],['display-lanes.json',lanes]]){const t=path.join(stage,name);if(fs.lstatSync(t).isSymbolicLink())fs.unlinkSync(t);fs.writeFileSync(t,JSON.stringify(data));}
fs.writeFileSync(path.join(path.dirname(candidateFile),'native-stage-receipt.json'),JSON.stringify({lineID:id,status:'candidate-only',physicalUnchanged:true,intervalCount:20,aliasCount:21,nativeRows:rows.map(r=>r.slice(0,6)),sourceProductionModified:false,stage},null,2)+'\n');
console.log(JSON.stringify({stage,intervals:20,aliases:21,rows:rows.length,physicalUnchanged:true,productionModified:false}));
