// Bounded display-only alignment of two incoming paths at one shared platform.
// Caller must establish through-running and select the correct platform family.
export function alignThroughPaths(paths, anchor, windowMetres = 120, straightMetres = 20) {
  const scaleX = 111320 * Math.cos(anchor[1] * Math.PI / 180);
  const toLocal = p => [(p[0] - anchor[0]) * scaleX, (p[1] - anchor[1]) * 111320];
  const fromLocal = p => [anchor[0] + p[0] / scaleX, anchor[1] + p[1] / 111320];
  const unit = p => { const n = Math.hypot(...p); return p.map(x => x / n); };
  const windows = paths.map(path => {
    const points = path.map(toLocal);
    let walked = 0;
    for (let i = points.length - 2; i >= 0; i--) {
      const a = points[i], b = points[i + 1];
      const length = Math.hypot(b[0] - a[0], b[1] - a[1]);
      if (walked + length >= windowMetres) {
        const t = (windowMetres - walked) / length;
        const cut = b.map((x, j) => x + (a[j] - x) * t);
        return { prefix: path.slice(0, i + 1), cut, tangent: unit(b.map((x, j) => x - a[j])) };
      }
      walked += length;
    }
    throw new Error('Through-running display approach is shorter than its alignment window');
  });
  const outward = windows.map(window => unit(window.cut));
  const axis = unit(outward[0].map((x, i) => x - outward[1][i]));
  if (!axis.every(Number.isFinite)) throw new Error('Through-running approaches do not oppose each other');
  return windows.map((window, index) => {
    const endTangent = axis.map(x => index === 0 ? -x : x);
    const end = endTangent.map(x => -x * straightMetres);
    const handle = Math.hypot(window.cut[0] - end[0], window.cut[1] - end[1]) / 3;
    const c1 = window.cut.map((x, i) => x + window.tangent[i] * handle);
    const c2 = end.map((x, i) => x - endTangent[i] * handle);
    const curve = [];
    for (let i = 0; i <= 16; i++) {
      const t = i / 16, u = 1 - t;
      curve.push(fromLocal(window.cut.map((x, j) =>
        u ** 3 * x + 3 * u ** 2 * t * c1[j] + 3 * u * t ** 2 * c2[j] + t ** 3 * end[j])));
    }
    // Both final edges use the exact same axis; the protected station vertex
    // sits between their opposite rays even after screen-space filleting.
    return [...window.prefix, ...curve, anchor.slice()];
  });
}
