#!/usr/bin/env node
// ADR 0013 §10. Derived identity bundle for the app. The ledger stays the source.
import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";

import { REGIONS, compareId, compareText, readLedger, splitBracketName } from "./rail-database/registry.mjs";

function parseArgs(argv) {
  const options = {
    db: path.resolve("data/rail.db"),
    root: path.resolve("data/registry"),
    out: path.resolve("data/registry-bundle"),
    regions: [],
    check: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--db") options.db = path.resolve(argv[++index]);
    else if (argument === "--root") options.root = path.resolve(argv[++index]);
    else if (argument === "--out") options.out = path.resolve(argv[++index]);
    else if (argument === "--region") options.regions.push(...argv[++index].split(",").map((item) => item.trim().toLowerCase()).filter(Boolean));
    else if (argument === "--check") options.check = true;
    else throw new Error(`unknown option: ${argument}`);
  }
  return options;
}

function hasTable(db, name) {
  return !!db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(name);
}

function normText(value) {
  return String(value ?? "").normalize("NFKC").trim().replace(/\s+/g, " ");
}

function pushUnique(list, value) {
  if (value === null || value === undefined || value === "") return;
  const text = String(value);
  if (!list.includes(text)) list.push(text);
}

function bracketFields(db, region) {
  const bracketedNames = {};
  const collected = new Set();
  if (db && hasTable(db, "station")) {
    const country = region.toUpperCase();
    for (const row of db.prepare("SELECT name FROM station WHERE country_code = ?").all(country)) {
      if (row.name) collected.add(String(row.name));
    }
    if (hasTable(db, "line") && hasTable(db, "line_station")) {
      const stops = db.prepare(`
        SELECT ls.name AS name
          FROM line_station ls
          JOIN line l ON l.id = ls.line_id
         WHERE l.country_code = ?
      `).all(country);
      for (const row of stops) {
        if (row.name) collected.add(String(row.name));
      }
    }
  }
  for (const name of [...collected].sort(compareText)) {
    const split = splitBracketName(name);
    if (!split) continue;
    const entry = {
      base: split.base,
      bracket: split.bracket,
      kind: split.kind,
      position: split.position,
    };
    if (split.kind === "status") entry.status = split.status;
    bracketedNames[name] = entry;
  }
  const bases = new Set(Object.values(bracketedNames).map((entry) => entry.base));
  const baseNameCounts = {};
  for (const base of [...bases].sort(compareText)) baseNameCounts[base] = 0;
  if (db && hasTable(db, "station") && bases.size) {
    const seen = new Set();
    const country = region.toUpperCase();
    for (const row of db.prepare("SELECT code, name FROM station WHERE country_code = ?").all(country)) {
      if (seen.has(row.code)) continue;
      seen.add(row.code);
      const split = splitBracketName(row.name);
      const hit = new Set();
      if (bases.has(row.name)) hit.add(row.name);
      if (split && bases.has(split.base)) hit.add(split.base);
      for (const base of hit) baseNameCounts[base] += 1;
    }
  }
  return { bracketedNames, baseNameCounts };
}

function operatorList(packageValues, shorts, aliases) {
  const list = [...packageValues].sort(compareText);
  for (const value of [...shorts].sort(compareText)) pushUnique(list, value);
  for (const value of [...aliases].sort(compareText)) pushUnique(list, value);
  return list;
}

export function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  if (value && typeof value === "object") {
    const keys = Object.keys(value).sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function bundleDocument(db, ledger, region) {
  const retired = new Set(ledger.events.filter((event) => event.event === "retire").map((event) => event.id));
  const live = (id) => ledger.entities.has(id) && !retired.has(id) && String(id).split(":")[1] === region;
  const stationCodeIds = new Map();
  const groupIds = new Map();
  const packageNames = new Map();
  const lineIds = new Map();
  const stOp = new Map();
  for (const ref of ledger.refs) {
    if (!live(ref.id)) continue;
    if (ref.scheme === "station-code" && ref.id.startsWith("st:")) {
      if (!stationCodeIds.has(ref.value)) stationCodeIds.set(ref.value, new Set());
      stationCodeIds.get(ref.value).add(ref.id);
    } else if (ref.scheme === "group-code" && ref.id.startsWith("cx:")) {
      if (!groupIds.has(ref.value)) groupIds.set(ref.value, new Set());
      groupIds.get(ref.value).add(ref.id);
    } else if (ref.scheme === "package-operator" && ref.id.startsWith("op:")) {
      if (!packageNames.has(ref.id)) packageNames.set(ref.id, []);
      pushUnique(packageNames.get(ref.id), ref.value);
    } else if (ref.scheme === "package-line" && ref.id.startsWith("lp:")) {
      if (!lineIds.has(ref.value)) lineIds.set(ref.value, new Set());
      lineIds.get(ref.value).add(ref.id);
    } else if (ref.scheme === "derivation" && ref.id.startsWith("st:") && !ref.from) {
      const op = String(ref.value).split("|")[1];
      if (op && live(op)) stOp.set(ref.id, op);
    }
  }
  const stationCodes = {};
  for (const [code, ids] of stationCodeIds) {
    if (ids.size === 1) stationCodes[code] = [...ids][0];
  }
  const childrenByParent = new Map();
  for (const entity of ledger.entities.values()) {
    if (!live(entity.id) || !entity.id.startsWith("st:")) continue;
    if (!childrenByParent.has(entity.parent)) childrenByParent.set(entity.parent, []);
    childrenByParent.get(entity.parent).push(entity.id);
  }
  const groupCodes = {};
  for (const [code, cxs] of groupIds) {
    const children = [];
    for (const cx of cxs) {
      const kids = childrenByParent.get(cx);
      if (kids) children.push(...kids);
    }
    groupCodes[code] = [...new Set(children)].sort(compareId);
  }
  const shorts = new Map();
  const aliases = new Map();
  if (db && hasTable(db, "operator")) {
    const country = region.toUpperCase();
    const rows = db.prepare("SELECT name, short_name, display_label FROM operator WHERE country_code = ?").all(country);
    const byName = new Map();
    for (const [id, names] of packageNames) {
      for (const name of names) {
        if (!byName.has(name)) byName.set(name, id);
        else if (byName.get(name) !== id) byName.set(name, null);
      }
    }
    for (const row of rows) {
      const id = byName.get(row.name);
      if (!id) continue;
      if (row.short_name) {
        if (!shorts.has(id)) shorts.set(id, []);
        pushUnique(shorts.get(id), row.short_name);
      }
    }
    if (hasTable(db, "operator_alias")) {
      const aliasRows = db.prepare("SELECT alias, label FROM operator_alias WHERE scope = ? ORDER BY alias").all(country);
      for (const alias of aliasRows) {
        const label = normText(alias.label);
        const matches = rows.filter((row) => [row.display_label, row.name, row.short_name].some((value) => normText(value) === label));
        if (matches.length !== 1) continue;
        const id = byName.get(matches[0].name);
        if (!id) continue;
        if (!aliases.has(id)) aliases.set(id, []);
        pushUnique(aliases.get(id), alias.alias);
      }
    }
  }
  const operators = {};
  for (const [id, names] of packageNames) {
    operators[id] = operatorList(names, shorts.get(id) ?? [], aliases.get(id) ?? []);
  }
  const stationOperator = {};
  for (const [st, op] of stOp) stationOperator[st] = op;
  const lines = {};
  for (const [lineId, ids] of lineIds) {
    if (ids.size === 1) lines[lineId] = [...ids][0];
  }
  const run = ledger.runs.reduce((max, item) => Math.max(max, Number(item.run) || 0), 0);
  const brackets = bracketFields(db, region);
  return {
    schema: "jtm-registry-bundle/1",
    region,
    run,
    stationCodes,
    groupCodes,
    operators,
    stationOperator,
    lines,
    bracketedNames: brackets.bracketedNames,
    baseNameCounts: brackets.baseNameCounts,
  };
}

export function bundleText(db, ledger, region) {
  return `${canonicalJson(bundleDocument(db, ledger, region))}\n`;
}

function regionsPresent(root, requested) {
  const present = REGIONS.filter((region) => {
    const dir = path.join(root, region);
    return fs.existsSync(dir) && fs.statSync(dir).isDirectory();
  });
  const regions = requested.length ? requested : present;
  for (const region of regions) {
    if (!REGIONS.includes(region)) throw new Error(`unknown region ${region}`);
  }
  return [...new Set(regions)].sort();
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const db = new DatabaseSync(options.db, { readOnly: true });
  let code = 0;
  try {
    const ledger = readLedger(options.root);
    const regions = regionsPresent(options.root, options.regions);
    if (!options.check) fs.mkdirSync(options.out, { recursive: true });
    for (const region of regions) {
      const text = bundleText(db, ledger, region);
      const file = path.join(options.out, `${region}.json`);
      if (options.check) {
        const current = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null;
        if (current !== text) {
          console.log(`bundle differs ${region}`);
          code = 1;
        }
      } else {
        fs.writeFileSync(file, text);
        console.log(`${region} ${Buffer.byteLength(text)} bytes`);
      }
    }
  } finally {
    db.close();
  }
  if (code) process.exit(code);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
