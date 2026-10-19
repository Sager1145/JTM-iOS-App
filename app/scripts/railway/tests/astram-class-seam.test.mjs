import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const data = new URL('../../../data/', import.meta.url);
const raw = JSON.parse(fs.readFileSync(new URL('rail-sections.json', data)));
const registry = JSON.parse(fs.readFileSync(new URL('physical-rail-junctions.json', data)));
const junction = registry.junctions.find(j => j.id === 'astram-kencho-class16-class24');

test('Astram junction connects existing opposite ends of the N02 class seam', () => {
  assert.ok(junction, 'reviewed Astram class seam must be in the shared registry');
  function matches(endpoint, terminal) {
    return raw.features.filter(f => {
      const p = f.properties;
      const c = f.geometry.coordinates;
      const point = terminal === 'end' ? c.at(-1) : c[0];
      return p.N02_004 === endpoint.identity.operatorName &&
        p.N02_003 === endpoint.identity.lineName &&
        p.N02_001 === endpoint.identity.railwayClassCode &&
        JSON.stringify(point) === JSON.stringify(endpoint.coordinate);
    });
  }
  assert.equal(junction.kind, 'zeroLength');
  assert.deepEqual(junction.from.coordinate, junction.to.coordinate);
  assert.equal(matches(junction.from, 'end').length, 1);
  assert.equal(matches(junction.to, 'start').length, 1);
  assert.notEqual(junction.from.identity.railwayClassCode, junction.to.identity.railwayClassCode);
  assert.equal(junction.from.identity.operatorName, junction.to.identity.operatorName);
  assert.equal(junction.from.identity.lineName, junction.to.identity.lineName);
  assert.equal(junction.validFrom, '1994-08-20');
  assert.ok(junction.evidence.every(url => url.startsWith('https://www.astramline.co.jp/')));
});
