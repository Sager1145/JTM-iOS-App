#!/usr/bin/env node
// ADR 0013 P2: map rail-history retirements and identity periods onto live
// registry ids. Matching is the history report's exact line name and operator,
// plus any package-line interval vertex inside the inclusive bbox.
import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";

import { compareId, compareText } from "../build/rail-database/registry.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const APP_DIR = path.resolve(HERE, "..", "..");
export const HISTORY_CROSSWALK_SCHEMA = "jtm-history-crosswalk/1";

function vertexInside(lon, lat, bbox) {
  return bbox[0] <= lon && lon <= bbox[2] && bbox[1] <= lat && lat <= bbox[3];
}

function normOperator(value) {
  return value == null ? "" : String(value);
}

function tableExists(db, name) {
  return Boolean(db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(name));
}

function usesStationPoints(match) {
  const targets = match?.targets;
  if (Array.isArray(targets) && targets.length > 0 && !targets.includes("sections")) return true;
  return typeof match?.station_name === "string" && match.station_name !== "";
}

function loadIndex(db) {
  const linesByKey = new Map();
  const lines = db.prepare(`
    SELECT l.id AS id, l.name AS name, o.name AS operator_name
      FROM line l
      JOIN operator o ON o.id = l.operator_id
     WHERE l.country_code = 'JP'
     ORDER BY l.id
  `).all();
  for (const line of lines) {
    const key = `${line.name}\0${normOperator(line.operator_name)}`;
    if (!linesByKey.has(key)) linesByKey.set(key, []);
    linesByKey.get(key).push(line.id);
  }
  const pointsByLine = new Map();
  const points = db.prepare(`
    SELECT i.line_id AS line_id, v.lon AS lon, v.lat AS lat
      FROM "interval" i
      JOIN interval_vertex v ON v.interval_id = i.id
      JOIN line l ON l.id = i.line_id
     WHERE l.country_code = 'JP'
  `).all();
  for (const point of points) {
    if (!pointsByLine.has(point.line_id)) pointsByLine.set(point.line_id, []);
    pointsByLine.get(point.line_id).push(point);
  }
  const lpByLine = new Map();
  const lpRows = db.prepare(`
    SELECT r.value AS line_id, e.id AS id
      FROM external_ref r
      JOIN registry_entity e ON e.id = r.entity_id
     WHERE r.scheme = 'package-line'
       AND e.kind = 'lp'
       AND e.region = 'jp'
       AND e.retired IS NULL
  `).all();
  for (const row of lpRows) {
    if (!lpByLine.has(row.line_id)) lpByLine.set(row.line_id, []);
    lpByLine.get(row.line_id).push(row.id);
  }
  const opByName = new Map();
  const opRows = db.prepare(`
    SELECT r.value AS name, e.id AS id
      FROM external_ref r
      JOIN registry_entity e ON e.id = r.entity_id
     WHERE r.scheme = 'package-operator'
       AND e.kind = 'op'
       AND e.region = 'jp'
       AND e.retired IS NULL
  `).all();
  for (const row of opRows) {
    const name = normOperator(row.name);
    if (!opByName.has(name)) opByName.set(name, new Set());
    opByName.get(name).add(row.id);
  }
  const stationPointsByLine = new Map();
  if (tableExists(db, "line_station")) {
    const stations = db.prepare(`
      SELECT line_id, name, lon, lat FROM line_station
    `).all();
    for (const point of stations) {
      if (!stationPointsByLine.has(point.line_id)) stationPointsByLine.set(point.line_id, []);
      stationPointsByLine.get(point.line_id).push(point);
    }
  }
  return { linesByKey, pointsByLine, stationPointsByLine, lpByLine, opByName };
}

function resolveEntry(index, entry, kind) {
  const match = entry?.match ?? {};
  const lineName = match.line_name ?? "";
  const operator = normOperator(match.operator);
  const rawBox = Array.isArray(match.bbox) ? match.bbox.map(Number) : [];
  const bboxOk = rawBox.length === 4 && rawBox.every(Number.isFinite);
  const lp = new Set();
  if (bboxOk && lineName !== "") {
    const lineIds = index.linesByKey.get(`${lineName}\0${operator}`) ?? [];
    const stationName = typeof match.station_name === "string" ? match.station_name : "";
    const byStation = usesStationPoints(match);
    for (const lineId of lineIds) {
      const points = byStation
        ? (index.stationPointsByLine.get(lineId) ?? []).filter((point) => !stationName || point.name === stationName)
        : (index.pointsByLine.get(lineId) ?? []);
      const hit = points.some((point) => vertexInside(point.lon, point.lat, rawBox));
      if (!hit) continue;
      for (const id of index.lpByLine.get(lineId) ?? []) lp.add(id);
    }
  }
  const lpIds = [...lp].sort(compareId);
  let status = "unmatched";
  if (lpIds.length === 1) status = "unique";
  else if (lpIds.length > 1) status = "multiple";
  const ops = index.opByName.get(operator);
  const op = ops && ops.size === 1 ? [...ops][0] : null;
  const row = {
    history_id: entry?.history_id ?? "",
    kind,
    match: {
      line_name: lineName,
      operator,
      bbox: bboxOk ? rawBox : [],
    },
    lp: lpIds,
    op,
    status,
  };
  if (entry?.valid_from) row.valid_from = String(entry.valid_from);
  if (entry?.valid_to) row.valid_to = String(entry.valid_to);
  return {
    history_id: row.history_id,
    kind: row.kind,
    match: row.match,
    ...(row.valid_from ? { valid_from: row.valid_from } : {}),
    ...(row.valid_to ? { valid_to: row.valid_to } : {}),
    lp: row.lp,
    op: row.op,
    status: row.status,
  };
}

export function applyHistoryOverrides(doc, overrides) {
  const byId = new Map();
  for (const item of overrides?.overrides ?? []) byId.set(String(item.history_id ?? ""), item);
  let reviewed = 0;
  const entries = (doc.entries ?? []).map((entry) => {
    const item = byId.get(entry.history_id);
    if (!item) return entry;
    reviewed += 1;
    const validFrom = item.valid_from ? String(item.valid_from) : entry.valid_from;
    const validTo = item.valid_to ? String(item.valid_to) : entry.valid_to;
    const next = {
      history_id: entry.history_id,
      kind: entry.kind,
      match: entry.match,
    };
    if (validFrom) next.valid_from = String(validFrom);
    if (validTo) next.valid_to = String(validTo);
    next.lp = Array.isArray(item.lp) ? item.lp.map(String).sort(compareId) : [];
    next.op = item.op ?? entry.op;
    next.status = "reviewed";
    return next;
  });
  return { doc: { schema: doc.schema, entries }, reviewed };
}

export function buildHistoryCrosswalk(db, history, overrides = null) {
  const index = loadIndex(db);
  const entries = [];
  for (const entry of history?.retirements ?? []) entries.push(resolveEntry(index, entry, "retirement"));
  for (const entry of history?.identity_periods ?? []) entries.push(resolveEntry(index, entry, "identity_period"));
  entries.sort((a, b) => compareText(a.history_id, b.history_id) || compareText(a.kind, b.kind));
  const doc = { schema: HISTORY_CROSSWALK_SCHEMA, entries };
  if (!overrides) return doc;
  return applyHistoryOverrides(doc, overrides).doc;
}

export function historyCrosswalkText(doc) {
  return `${JSON.stringify(doc, null, 2)}\n`;
}

function parseArgs(argv) {
  const options = {
    db: path.join(APP_DIR, "data", "rail.db"),
    history: path.join(APP_DIR, "data", "rail-history.json"),
    out: path.join(APP_DIR, "data", "registry", "jp", "history-crosswalk.json"),
    overrides: path.join(APP_DIR, "data", "registry", "jp", "history-overrides.json"),
    check: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--db") options.db = path.resolve(argv[++index]);
    else if (argument === "--history") options.history = path.resolve(argv[++index]);
    else if (argument === "--out") options.out = path.resolve(argv[++index]);
    else if (argument === "--overrides") options.overrides = path.resolve(argv[++index]);
    else if (argument === "--check") options.check = true;
    else throw new Error(`unknown option: ${argument}`);
  }
  return options;
}

function statusCounts(doc) {
  const counts = { unique: 0, multiple: 0, unmatched: 0, reviewed: 0 };
  for (const entry of doc.entries) counts[entry.status] = (counts[entry.status] ?? 0) + 1;
  return counts;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const history = JSON.parse(fs.readFileSync(options.history, "utf8"));
  const overrides = fs.existsSync(options.overrides) ? JSON.parse(fs.readFileSync(options.overrides, "utf8")) : null;
  const db = new DatabaseSync(options.db, { readOnly: true });
  let built;
  try {
    built = buildHistoryCrosswalk(db, history);
  } finally {
    db.close();
  }
  const applied = overrides ? applyHistoryOverrides(built, overrides) : { doc: built, reviewed: 0 };
  const doc = applied.doc;
  const text = historyCrosswalkText(doc);
  const counts = statusCounts(doc);
  const summary = `unique=${counts.unique} multiple=${counts.multiple} unmatched=${counts.unmatched} reviewed=${applied.reviewed}`;
  if (options.check) {
    const current = fs.existsSync(options.out) ? fs.readFileSync(options.out, "utf8") : null;
    if (current !== text) {
      console.log("history-crosswalk differs");
      process.exit(1);
    }
    console.log(`history-crosswalk ok ${summary}`);
    return;
  }
  fs.mkdirSync(path.dirname(options.out), { recursive: true });
  fs.writeFileSync(options.out, text);
  console.log(`history-crosswalk ${doc.entries.length} ${summary}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
