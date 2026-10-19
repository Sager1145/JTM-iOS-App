import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';
const require = createRequire(import.meta.url);
const Network = require('../public/rail-network.js');
const packageInput = require('../public/rail/jp-2025.json');
const line = packageInput.lines.find(row => row.id === 'jp-えちごトキめき鉄道-妙高はねうまライン');
const station = line.stations[2].slice(2,4);
const junction = [138.23198,36.98702];
const same = (a,b) => a[0] === b[0] && a[1] === b[1];

test('reviewed short switchback draws a continuous main and a single platform spur', () => {
  const parts = Network.displayPartsForLine(line);
  const spur = parts.find(part => same(part.at(-1),station));
  assert.deepEqual(spur[0],junction, 'the spur must start at the physical switch, without a reversed main lead-in');
  assert.equal(spur.length,7);
  const trunk = parts.find(part => !part.some(point => same(point,station)));
  assert.ok(trunk,'the through main must not reverse at the platform');
  const cut = trunk.findIndex(point => same(point,junction));
  assert.ok(cut > 0 && cut < trunk.length - 1);
  assert.deepEqual(trunk[cut+1],[138.23206,36.98717]);
  assert.equal(parts.length,2);
});
