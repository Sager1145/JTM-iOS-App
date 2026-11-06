// Preloaded into child node processes (NODE_OPTIONS --import) while a stamped
// fixture is being built: appends every .json path read to JTM_FIXTURE_READ_LOG.
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { fileURLToPath } from "node:url";

const log = process.env.JTM_FIXTURE_READ_LOG;
if (log) {
  const record = (target) => {
    try {
      const file = target instanceof URL ? fileURLToPath(target) : typeof target === "string" ? target : null;
      if (file && file.endsWith(".json")) fs.appendFileSync(log, `${file}\n`);
    } catch {}
  };
  const readFileSync = fs.readFileSync;
  fs.readFileSync = function (target, ...rest) {
    record(target);
    return readFileSync.call(this, target, ...rest);
  };
  const readFile = fs.promises.readFile;
  fs.promises.readFile = function (target, ...rest) {
    record(target);
    return readFile.call(this, target, ...rest);
  };
  syncBuiltinESMExports();
}
