import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const Network = createRequire(import.meta.url)('../public/rail-network.js');

test('a physical spur starts at its switch without duplicating the main track', () => {
  const start = [139,35], junction = [139.01,35], middle = [139.015,35.0005];
  const platform = [139.02,35.001], mainNearPlatform = [139.02,35], end = [139.03,35];
  const line = {
    id:'jp-test-branch', name:'branch', operator:'test', isLoop:false,
    stations:[['a','main start',...start],['b','branch platform',...platform],['c','main end',...end]],
    segments:[[2,0,[start,junction,middle,platform]], [3,0,[platform,middle,junction,mainNearPlatform,end]]],
  };
  const parts = Network.displayPartsForLine(line);
  const branch = parts.find(part => JSON.stringify(part.at(-1)) === JSON.stringify(platform));
  assert.ok(branch, 'the real platform spur must remain');
  assert.deepEqual(branch[0], junction, 'draw the spur from the physical switch, without an out-and-back main lead-in');
  assert.equal(branch.length, 3);
  assert.equal(parts.flat().filter(point => JSON.stringify(point) === JSON.stringify(mainNearPlatform)).length, 1);
  assert.ok(branch.some(point => JSON.stringify(point) === JSON.stringify(junction)));
  const trunk = parts.find(part => JSON.stringify(part[0]) === JSON.stringify(start));
  assert.deepEqual(trunk.at(-1), end);
});

test('short and long exact shared spurs are drawn once without a topology override', () => {
  for (const direction of [1,-1]) for (const scale of [1,5]) {
    const start=[138.99,35], junction=[139,35], mid=[139+scale*0.001,35+scale*0.0002], platform=[139+scale*0.002,35+scale*0.0004];
    const next=[139+direction*0.005,35], end=[139+direction*0.01,35];
    const line={id:'jp-short-exact-spur',operator:'test',stations:[['a','a',...start],['b','b',...platform],['c','c',...end]],
      segments:[[1,0,[start,junction,mid,platform]],[1,0,[platform,mid,junction,next,end]]]};
    const parts=Network.displayPartsForLine(line);
    const edge=(a,b)=>[JSON.stringify(a),JSON.stringify(b)].sort().join('|');
    const shared=new Set([edge(junction,mid),edge(mid,platform)]);
    const counts=new Map();
    for(const part of parts)for(let i=1;i<part.length;i++) {const key=edge(part[i-1],part[i]);if(shared.has(key))counts.set(key,(counts.get(key)||0)+1);}
    assert.deepEqual([...counts.values()], [1,1], 'physical station spur edges must occur only once');
    const spur=parts.find(part=>JSON.stringify(part.at(-1))===JSON.stringify(platform));
    assert.deepEqual(spur[0],junction);
    assert.equal(parts.length,direction===1?2:3,'a sharp main turn must remain separate rather than become a hairpin');
  }
});

test('display artifact rebuilding retains the sharp main-leg boundary', async () => {
  const {physicalForkBoundaries}=await import('../scripts/railway/build-display-lanes.mjs');
  const row=(index,points)=>['jp-fork',index,-1,-1,points.length,100,'complex',points];
  const rows=[row(0,[[139,35],[139.001,35.0001]]),row(1,[[139.01,35],[139,35]]),row(2,[[139,35],[139.01,34.999]])];
  assert.deepEqual(physicalForkBoundaries(rows),[['jp-fork',1,2,'exact-shared-spur-main-legs']]);
  rows[2][7][1]=[138.99,35];
  assert.deepEqual(physicalForkBoundaries(rows),[], 'a straight through main is not a sharp boundary');
});
