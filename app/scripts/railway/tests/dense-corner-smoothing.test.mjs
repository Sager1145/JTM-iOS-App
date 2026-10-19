import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';
const stroke = createRequire(import.meta.url)('../../../public/rail-stroke.js');
for (const [name, source, corners] of [
  ['localized moderate corner', [[-100,0],[0,0],[100*Math.cos(35*Math.PI/180),100*Math.sin(35*Math.PI/180)],[200*Math.cos(35*Math.PI/180),200*Math.sin(35*Math.PI/180)]], [1]],
  ['isolated surveyed corner', [[-100,0],[0,0],[0,100],[0,200]], [1]],
  ['ambiguous short connector retained', [[-100,0],[0,0],[10,10],[110,10]], [1,2]],
  ['short opposing surveyed corners', [[-100,0],[0,0],[5,5],[105,5]], [1,2]],
]) test(name, () => {
  for (const scale of [0.25, 1, 4]) for (const strict of [false, true]) {
    const points = source.map(p => p.map(v => v * scale));
    const measures = [0];
    for (let i=1;i<source.length;i++) measures.push(measures.at(-1)+Math.hypot(source[i][0]-source[i-1][0],source[i][1]-source[i-1][1]));
    const result = stroke.buildStroke(points, { measures, rows: [], totalMetres: measures.at(-1),
      laneGapPx: 0, minRampPx: 24, cornerRadiusPx: 3.6, minCornerRadiusPx: strict ? 3 : 0,
      anchors: [0,3], enforceMinimumCornerRadius: strict });
    for (const index of corners) {
      const at = result.points.findIndex(p => p[0] === points[index][0] && p[1] === points[index][1]);
      assert.ok(at > 0 && at + 1 < result.points.length);
      const turn = (p, i) => {
        const a=[p[i][0]-p[i-1][0],p[i][1]-p[i-1][1]],b=[p[i+1][0]-p[i][0],p[i+1][1]-p[i][1]];
        return Math.atan2(a[0]*b[1]-a[1]*b[0],a[0]*b[0]+a[1]*b[1]);
      };
      assert.ok(Math.abs(turn(result.points, at) - turn(points, index)) < 1e-9);
    }
    assert.ok(result.measures.every((m,i) => !i || m >= result.measures[i-1]));
  }
});
