#!/usr/bin/env node
// The only writer of app/data/registry. build-rail-database.mjs only reads.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";

import {
  REGIONS,
  additionsEmpty,
  appendLedger,
  homonyms,
  indexSpaceMap,
  mint,
  planLedgerWrites,
  readLedger,
  reports,
} from "./rail-database/registry.mjs";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

function parseArgs(argv) {
  const options = {
    db: path.resolve("data/rail.db"),
    root: path.resolve("data/registry"),
    regions: [],
    at: null,
    dryRun: false,
    allowRetire: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--db") options.db = path.resolve(argv[++index]);
    else if (argument === "--root") options.root = path.resolve(argv[++index]);
    else if (argument === "--region") options.regions.push(...argv[++index].split(",").map((item) => item.trim().toLowerCase()).filter(Boolean));
    else if (argument === "--at") options.at = argv[++index];
    else if (argument === "--dry-run") options.dryRun = true;
    else if (argument === "--allow-retire") options.allowRetire = true;
    else throw new Error(`unknown option: ${argument}`);
  }
  return options;
}

function today() {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${now.getFullYear()}-${month}-${day}`;
}

function sha256File(file) {
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function printPlans(root, additions) {
  const plans = planLedgerWrites(root, additions);
  if (!plans.length) {
    console.log("no changes");
    return;
  }
  for (const plan of plans) {
    const exists = fs.existsSync(plan.abs);
    const shown = exists ? plan.lines : [plan.header, ...plan.lines];
    console.log(`${plan.rel} +${shown.length}`);
    for (const line of shown.slice(0, 3)) console.log(line);
  }
}

function retireLines(events) {
  const counts = new Map();
  for (const item of events) {
    if (item.rec?.event !== "retire") continue;
    const kind = String(item.rec.id).split(":")[0];
    const key = `${item.region} ${kind}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map(([key, count]) => `${key} ${count}`);
}

function regionsInDb(db, requested) {
  const present = db.prepare(`
    SELECT DISTINCT country_code AS code FROM operator
    UNION SELECT DISTINCT country_code FROM line
    UNION SELECT DISTINCT country_code FROM station
  `).all().map((row) => String(row.code).toLowerCase()).filter((code) => REGIONS.includes(code));
  const regions = requested.length ? requested : present;
  for (const region of regions) {
    if (!REGIONS.includes(region)) throw new Error(`unknown region ${region}`);
  }
  return [...new Set(regions)].sort();
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const freezePath = path.join(options.root, "phase0-freeze.json");
  if (!fs.existsSync(freezePath)) {
    console.log("phase 0 freeze missing");
    process.exit(1);
  }
  const at = options.at ?? today();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(at)) throw new Error(`bad --at ${at}`);
  const db = new DatabaseSync(options.db, { readOnly: true });
  let code = 0;
  try {
    const regions = regionsInDb(db, options.regions);
    const ledger = readLedger(options.root);
    const runId = ledger.runs.reduce((max, run) => Math.max(max, Number(run.run) || 0), 0) + 1;
    const merged = {
      entities: [],
      refs: [],
      events: [],
      aliases: [],
      runs: [],
      reappeared: [],
      conflicts: [],
      crosswalkConflicts: [],
      operatorRenameInvalid: [],
      operatorNameAmbiguous: [],
    };
    for (const region of regions) {
      const additions = mint(db, ledger, { region, runId, at, root: options.root });
      merged.entities.push(...additions.entities);
      merged.refs.push(...additions.refs);
      merged.events.push(...additions.events);
      merged.aliases.push(...additions.aliases);
      merged.reappeared.push(...additions.reappeared);
      merged.conflicts.push(...additions.conflicts);
      merged.crosswalkConflicts.push(...additions.crosswalkConflicts);
      merged.operatorRenameInvalid.push(...(additions.operatorRenameInvalid ?? []));
      merged.operatorNameAmbiguous.push(...(additions.operatorNameAmbiguous ?? []));
    }
    if (merged.reappeared.length) console.log(`reappeared ${merged.reappeared.length}`);
    if (merged.conflicts.length) console.log(`station-code-conflict ${merged.conflicts.length}`);
    if (merged.crosswalkConflicts.length) console.log(`crosswalk-conflict ${merged.crosswalkConflicts.length}`);
    if (merged.operatorRenameInvalid.length) console.log(`operator-rename-invalid ${merged.operatorRenameInvalid.length}`);
    if (merged.operatorNameAmbiguous.length) console.log(`operator-name-ambiguous ${merged.operatorNameAmbiguous.length}`);
    const refused = retireLines(merged.events);
    if (merged.reappeared.length || merged.operatorNameAmbiguous.length) {
      code = 1;
    } else if (refused.length && !options.allowRetire) {
      console.log("retire refused");
      for (const line of refused) console.log(line);
      code = 1;
    } else {
      const changed = !additionsEmpty(merged);
      if (changed) {
        const freeze = JSON.parse(fs.readFileSync(freezePath, "utf8"));
        const inputs = (freeze.registryInputs ?? []).map((item) => ({
          path: item.path,
          sha256: sha256File(path.resolve(REPO_ROOT, item.path)),
        }));
        merged.runs.push({ rec: { run: runId, at, tool: "mint-registry/1", inputs } });
      }
      if (!options.dryRun && changed) appendLedger(options.root, merged);
      printPlans(options.root, merged);
      if (!options.dryRun) {
        const minted = readLedger(options.root);
        for (const region of regions) {
          writeJson(path.join(options.root, region, "station-derivation-exceptions.json"), reports(db, minted, region, options.root));
          writeJson(path.join(options.root, region, "homonyms.json"), homonyms(db, minted, region));
          writeJson(path.join(options.root, region, "index-space-map.json"), indexSpaceMap(db, minted, region));
        }
      }
    }
  } finally {
    db.close();
  }
  if (code) process.exit(code);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
