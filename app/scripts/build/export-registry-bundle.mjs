#!/usr/bin/env node
// ADR 0013 §10. Derived identity bundle for the app. The ledger stays the source.
import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";

import { REGIONS, compareId, compareText, readLedger, splitBracketName } from "./rail-database/registry.mjs";
import { searchFold } from "./search-fold.mjs";

const IDENTITY_PATH = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../../ios/RailKit/Sources/RailCore/Resources/operator-identities.json",
);

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

function tableColumns(db, name) {
  if (!db || !hasTable(db, name)) return new Set();
  return new Set(db.prepare(`PRAGMA table_info(${name})`).all().map((row) => row.name));
}

function round5(value) {
  return Number(Number(value).toFixed(5));
}

function entryNames(entry) {
  const names = [entry.legal, entry.label];
  const localized = entry.names && typeof entry.names === "object" ? entry.names : {};
  for (const key of Object.keys(localized).sort(compareText)) {
    const values = localized[key];
    if (Array.isArray(values)) names.push(...values);
  }
  if (Array.isArray(entry.aliases)) names.push(...entry.aliases);
  return names.filter((name) => name != null && name !== "");
}

let identityEntries = null;

function loadIdentityEntries() {
  if (identityEntries) return identityEntries;
  const document = JSON.parse(fs.readFileSync(IDENTITY_PATH, "utf8"));
  identityEntries = (document.operators ?? []).map((entry) => ({
    code: entry.code,
    folded: new Set(entryNames(entry).map((name) => searchFold(name)).filter(Boolean)),
  }));
  return identityEntries;
}

// One identity code when exactly one operator-identities entry shares a
// SearchFold-equal name. Zero or several entries → null.
export function identityFor(names, entries = loadIdentityEntries()) {
  const folded = new Set(names.map((name) => searchFold(name)).filter(Boolean));
  const hits = [];
  for (const entry of entries) {
    let matched = false;
    for (const key of folded) {
      if (entry.folded.has(key)) {
        matched = true;
        break;
      }
    }
    if (matched) hits.push(entry.code);
  }
  const unique = [...new Set(hits)];
  return unique.length === 1 ? unique[0] : null;
}

function bracketParts(name) {
  const split = splitBracketName(name);
  if (!split) return null;
  const entry = {
    base: split.base,
    bracket: split.bracket,
    kind: split.kind,
    position: split.position,
  };
  if (split.kind === "status") entry.status = split.status;
  return entry;
}

export function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  if (value && typeof value === "object") {
    const keys = Object.keys(value).sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function reviewedAliasTexts(root, region) {
  const byOp = new Map();
  if (!root) return byOp;
  const file = path.join(root, region, "operator-aliases.json");
  if (!fs.existsSync(file)) return byOp;
  const doc = JSON.parse(fs.readFileSync(file, "utf8"));
  for (const alias of doc.aliases ?? []) {
    if (!alias.op || !alias.text) continue;
    if (!byOp.has(alias.op)) byOp.set(alias.op, []);
    pushUnique(byOp.get(alias.op), alias.text);
  }
  return byOp;
}

function bundleFacilities(ledger, region, live) {
  const members = new Map();
  const managers = new Map();
  for (const event of ledger.events) {
    if (event.event === "facility" && live(event.value) && live(event.id)) {
      if (!members.has(event.value)) members.set(event.value, []);
      pushUnique(members.get(event.value), event.id);
    } else if (event.event === "manager" && live(event.id) && String(event.id).split(":")[1] === region) {
      managers.set(event.id, event.value);
    }
  }
  const facilities = {};
  for (const [id, stations] of members) {
    if (String(id).split(":")[1] !== region) continue;
    const slug = ledger.entities.get(id)?.slug;
    facilities[id] = {
      stations: [...stations].sort(compareId),
      manager: managers.get(id) ?? null,
      kind: slug === "boundary" ? "boundary" : "shared",
    };
  }
  const links = [];
  const seen = new Set();
  for (const event of ledger.events) {
    if (event.event !== "link" || !live(event.id) || !live(event.value)) continue;
    if (String(event.id).split(":")[1] !== region) continue;
    const pair = [event.id, event.value].sort(compareId);
    const key = `${pair[0]}\0${pair[1]}\0${event.why ?? ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    links.push([pair[0], pair[1], event.why === "street_transfer" ? "street_transfer" : "gate_transfer"]);
  }
  links.sort((a, b) => compareId(a[0], b[0]) || compareId(a[1], b[1]) || compareText(a[2], b[2]));
  return { facilities, links };
}

export function bundleDocument(db, ledger, region, root = null) {
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
  const byName = new Map();
  let operatorRows = [];
  if (db && hasTable(db, "operator")) {
    const country = region.toUpperCase();
    const columns = tableColumns(db, "operator");
    const selected = ["name", "short_name"];
    if (columns.has("display_label")) selected.push("display_label");
    if (columns.has("logo_path")) selected.push("logo_path");
    operatorRows = db.prepare(
      `SELECT ${selected.join(", ")} FROM operator WHERE country_code = ? ORDER BY name`,
    ).all(country);
    for (const [id, names] of packageNames) {
      for (const name of names) {
        if (!byName.has(name)) byName.set(name, id);
        else if (byName.get(name) !== id) byName.set(name, null);
      }
    }
    for (const row of operatorRows) {
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
        const matches = operatorRows.filter((row) => [row.display_label, row.name, row.short_name].some((value) => normText(value) === label));
        if (matches.length !== 1) continue;
        const id = byName.get(matches[0].name);
        if (!id) continue;
        if (!aliases.has(id)) aliases.set(id, []);
        pushUnique(aliases.get(id), alias.alias);
      }
    }
  }
  const profiles = new Map();
  for (const row of operatorRows) {
    const id = byName.get(row.name);
    if (!id || profiles.has(id)) continue;
    const logo = row.logo_path ? String(row.logo_path) : null;
    profiles.set(id, { label: row.display_label == null ? "" : String(row.display_label), logo });
  }
  const reviewedAliases = reviewedAliasTexts(root, region);
  const operators = {};
  for (const [id, names] of packageNames) {
    const aliasTexts = [...(aliases.get(id) ?? [])];
    for (const text of reviewedAliases.get(id) ?? []) pushUnique(aliasTexts, text);
    const list = operatorList(names, shorts.get(id) ?? [], aliasTexts);
    const profile = profiles.get(id);
    operators[id] = {
      names: list,
      label: profile?.label ?? "",
      logo: profile?.logo ?? null,
      identity: identityFor(list),
    };
  }
  const stationOperator = {};
  for (const [st, op] of stOp) stationOperator[st] = op;
  const lines = {};
  for (const [lineId, ids] of lineIds) {
    if (ids.size === 1) lines[lineId] = [...ids][0];
  }
  const run = ledger.runs.reduce((max, item) => Math.max(max, Number(item.run) || 0), 0);
  const brackets = bracketFields(db, region);
  const reversed = reverseTables(db, ledger, region, {
    live, packageNames, stOp, childrenByParent, stationCodes, root,
  });
  const places = bundleFacilities(ledger, region, live);
  return {
    schema: "jtm-registry-bundle/2",
    region,
    run,
    stationCodes,
    groupCodes,
    operators,
    stationOperator,
    lines,
    stations: reversed.stations,
    complexes: reversed.complexes,
    lineParts: reversed.lineParts,
    facilities: places.facilities,
    links: places.links,
    bracketedNames: brackets.bracketedNames,
    baseNameCounts: brackets.baseNameCounts,
  };
}

function lineOperatorOverrides(root, region) {
  const overrides = new Map();
  if (!root) return overrides;
  const file = path.join(root, region, "line-operators.json");
  if (!fs.existsSync(file)) return overrides;
  const doc = JSON.parse(fs.readFileSync(file, "utf8"));
  if (doc?.schema !== "jtm-line-operators/1" || !Array.isArray(doc.lines)) return overrides;
  for (const item of doc.lines) overrides.set(String(item.lp), String(item.op));
  return overrides;
}

function reverseTables(db, ledger, region, { live, packageNames, stOp, childrenByParent, stationCodes, root = null }) {
  const lpOverride = lineOperatorOverrides(root, region);
  const country = region.toUpperCase();
  const groupOfCx = new Map();
  const codesOfStation = new Map();
  const linesOfStation = new Map();
  const packageLineOfLp = new Map();
  for (const ref of ledger.refs) {
    if (!live(ref.id)) continue;
    if (ref.scheme === "group-code" && !ref.from && String(ref.id).startsWith("cx:")) {
      if (!groupOfCx.has(ref.id)) groupOfCx.set(ref.id, []);
      pushUnique(groupOfCx.get(ref.id), ref.value);
    } else if (ref.scheme === "station-code" && String(ref.id).startsWith("st:") && stationCodes[ref.value] === ref.id) {
      if (!codesOfStation.has(ref.id)) codesOfStation.set(ref.id, []);
      pushUnique(codesOfStation.get(ref.id), ref.value);
    } else if (ref.scheme === "package-line" && !ref.from && String(ref.id).startsWith("lp:")) {
      if (!packageLineOfLp.has(ref.id)) packageLineOfLp.set(ref.id, []);
      pushUnique(packageLineOfLp.get(ref.id), ref.value);
    }
  }
  for (const entity of ledger.entities.values()) {
    if (!live(entity.id) || !String(entity.id).startsWith("ls:")) continue;
    if (!entity.parent || !entity.part || !live(entity.parent) || !live(entity.part)) continue;
    if (!linesOfStation.has(entity.parent)) linesOfStation.set(entity.parent, []);
    pushUnique(linesOfStation.get(entity.parent), entity.part);
  }
  const lnOfLp = new Map();
  for (const event of ledger.events) {
    if (event.event !== "line" || !event.id || !event.value) continue;
    if (!String(event.id).startsWith("lp:") || !live(event.id)) continue;
    if (!live(event.value)) lnOfLp.delete(event.id);
    else lnOfLp.set(event.id, event.value);
  }
  const stationByCode = new Map();
  if (db && hasTable(db, "station")) {
    for (const row of db.prepare(
      "SELECT code, name, lon, lat FROM station WHERE country_code = ?",
    ).all(country)) {
      stationByCode.set(row.code, row);
    }
  }
  const stopNames = new Map();
  if (db && hasTable(db, "line_station") && hasTable(db, "line") && hasTable(db, "station") && hasTable(db, "operator")) {
    const rows = db.prepare(`
      SELECT s.code AS code, o.name AS operator_name, ls.name AS stop_name
        FROM line_station ls
        JOIN line l ON l.id = ls.line_id
        JOIN station s ON s.id = ls.station_id
        JOIN operator o ON o.id = l.operator_id
       WHERE l.country_code = ?
    `).all(country);
    for (const row of rows) {
      const key = `${row.code}\0${row.operator_name}`;
      if (!stopNames.has(key)) stopNames.set(key, new Set());
      stopNames.get(key).add(String(row.stop_name));
    }
  }
  const lineRow = new Map();
  if (db && hasTable(db, "line") && hasTable(db, "operator")) {
    const rank = tableColumns(db, "line").has("rank") ? "l.rank" : "NULL";
    const rows = db.prepare(`
      SELECT l.id AS id, l.name AS name, ${rank} AS rank, o.name AS operator_name
        FROM line l
        JOIN operator o ON o.id = l.operator_id
       WHERE l.country_code = ?
    `).all(country);
    for (const row of rows) lineRow.set(row.id, row);
  }
  const chosenGroup = (cx) => {
    const values = [...(groupOfCx.get(cx) ?? [])].sort(compareText);
    return values.find((code) => stationByCode.has(code)) ?? values[0] ?? "";
  };
  const stations = {};
  for (const entity of ledger.entities.values()) {
    if (!live(entity.id) || !String(entity.id).startsWith("st:")) continue;
    const cx = entity.parent;
    const op = stOp.get(entity.id);
    if (!cx || !op || !live(cx)) continue;
    const group = chosenGroup(cx);
    const names = new Set();
    for (const operatorName of packageNames.get(op) ?? []) {
      const hit = stopNames.get(`${group}\0${operatorName}`);
      if (hit) for (const name of hit) names.add(name);
    }
    const complexName = stationByCode.get(group)?.name;
    const name = names.size === 1 ? [...names][0] : (complexName == null ? "" : String(complexName));
    const record = {
      cx,
      group,
      codes: [...(codesOfStation.get(entity.id) ?? [])].sort(compareText),
      op,
      name,
      lines: [...(linesOfStation.get(entity.id) ?? [])].sort(compareId),
    };
    const parts = bracketParts(name);
    if (parts) record.parts = parts;
    const networks = [...new Set(record.lines.map((lp) => lnOfLp.get(lp)).filter(Boolean))].sort(compareId);
    if (networks.length) record.ln = networks;
    stations[entity.id] = record;
  }
  const complexes = {};
  for (const entity of ledger.entities.values()) {
    if (!live(entity.id) || !String(entity.id).startsWith("cx:")) continue;
    const group = chosenGroup(entity.id);
    const row = stationByCode.get(group);
    if (!row || row.lon == null || row.lat == null) continue;
    const members = [...(childrenByParent.get(entity.id) ?? [])].filter((id) => live(id)).sort(compareId);
    complexes[entity.id] = {
      group,
      name: String(row.name),
      stations: members,
      lon: round5(row.lon),
      lat: round5(row.lat),
    };
  }
  const lineParts = {};
  for (const entity of ledger.entities.values()) {
    if (!live(entity.id) || !String(entity.id).startsWith("lp:")) continue;
    const packageLines = packageLineOfLp.get(entity.id) ?? [];
    if (packageLines.length !== 1) continue;
    const row = lineRow.get(packageLines[0]);
    if (!row) continue;
    const holders = new Set();
    for (const [id, names] of packageNames) {
      if (names.includes(row.operator_name)) holders.add(id);
    }
    const override = lpOverride.get(entity.id);
    if (holders.size !== 1 && !(override && live(override))) continue;
    const record = {
      packageLine: packageLines[0],
      name: String(row.name),
      op: override && live(override) ? override : [...holders][0],
      rank: row.rank == null ? 0 : Number(row.rank),
    };
    const network = lnOfLp.get(entity.id);
    if (network) record.ln = network;
    lineParts[entity.id] = record;
  }
  return { stations, complexes, lineParts };
}

export function bundleText(db, ledger, region, root = null) {
  return `${canonicalJson(bundleDocument(db, ledger, region, root))}\n`;
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
      const text = bundleText(db, ledger, region, options.root);
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
