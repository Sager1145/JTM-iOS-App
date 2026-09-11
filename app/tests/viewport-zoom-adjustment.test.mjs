import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(HERE, "..", "public");

function loadContext() {
  const context = vm.createContext({ console });
  context.globalThis = context;
  // Both browser scripts are IIFEs that take `window` as their global.
  context.window = context;
  vm.runInContext(
    fs.readFileSync(path.join(PUBLIC, "rail-network.js"), "utf8"),
    context,
    { filename: "rail-network.js" },
  );
  // railmap-style.js destructures the basemap module at load time.
  vm.runInContext(
    fs.readFileSync(path.join(PUBLIC, "railmap-basemap.js"), "utf8"),
    context,
    { filename: "railmap-basemap.js" },
  );
  vm.runInContext(
    fs.readFileSync(path.join(PUBLIC, "railmap-style.js"), "utf8"),
    context,
    { filename: "railmap-style.js" },
  );
  return context;
}

test("viewportZoomAdjustment matches the reference-viewport formula", () => {
  const { RailNetwork } = loadContext();
  const near = (a, b) => Math.abs(a - b) < 1e-3;

  assert.ok(near(RailNetwork.viewportZoomAdjustment(390, 844), 0));
  assert.ok(near(RailNetwork.viewportZoomAdjustment(780, 1688), -1));
  assert.ok(near(RailNetwork.viewportZoomAdjustment(1024, 1366), -1.393));
  // Clamp at the wide end.
  assert.equal(RailNetwork.viewportZoomAdjustment(2000, 2000), -1.5);
  // Clamp at the narrow end.
  assert.equal(RailNetwork.viewportZoomAdjustment(200, 200), 0.5);
  // Landscape/portrait use the SHORT edge, so they agree.
  assert.ok(
    near(
      RailNetwork.viewportZoomAdjustment(844, 390),
      RailNetwork.viewportZoomAdjustment(390, 844),
    ),
  );
  // Degenerate/non-finite viewports fall back to no adjustment.
  assert.equal(RailNetwork.viewportZoomAdjustment(0, 0), 0);
  assert.equal(RailNetwork.viewportZoomAdjustment(NaN, 844), 0);
  assert.equal(RailNetwork.viewportZoomAdjustment(-10, 844), 0);
});

test("lineLengthVisibilityOpacity gates minz against zoom + adjustment", () => {
  const { RailMapStyle } = loadContext();
  const firstVisibleBucket = (minz, adjustment) => {
    const stepped = RailMapStyle.lineLengthVisibilityOpacity(1, adjustment);
    // stepped is ["step", ["zoom"], gate(0), 1, gate(1), 2, gate(2), ...]
    // Find the first bucket zoom whose gate condition (minz <= zoom+adjustment)
    // evaluates true for the given minz. gate(z) is
    // ["case", ["<=", ["coalesce", ["get", "minz"], 0], z + adjustment], 1, 0].
    for (let i = 2; i < stepped.length; i += 2) {
      const zoom = stepped[i - 1];
      const gate = stepped[i];
      const compareTo = gate[1][2];
      if (minz <= compareTo) return zoom;
    }
    return null;
  };

  assert.equal(firstVisibleBucket(5, 0), 5);
  assert.equal(firstVisibleBucket(5, -1.4), 7);
});
