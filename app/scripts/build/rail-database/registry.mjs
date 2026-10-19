// Ledger IO, mint, and P0 reports for ADR 0013. The builder only reads the
// ledger; mint-registry.mjs is the only writer. Lines are canonical JSONL and,
// once written, are never edited — later facts are appended.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const APP_DIR = path.resolve(HERE, "..", "..", "..");

export const SCHEMA_ID = "jtm-registry/1";
export const KINDS = ["op", "lp", "cx", "st", "ls"];
export const REGIONS = ["jp", "tw", "hk", "mo", "kr", "cn"];
const FILE_KINDS = ["op", "ln", "lp", "cx", "st", "ls", "rp", "fc"];
const COUNTRY_CODES = ["jp", "tw", "hk", "mo", "kr", "cn"];
const KIND_RANK = Object.fromEntries(
  ["op", "ln", "lp", "cx", "fc", "st", "ls", "rp"].map((kind, index) => [kind, index]),
);

export const ID_RE = /^(op|ln|lp|cx|st|ls|rp|fc):(jp|tw|hk|mo|kr|cn):([1-9]\d*)$/;

export const KEY_ORDERS = {
  entity: ["id", "parent", "part", "slug", "run"],
  ref: ["id", "scheme", "value", "from", "to", "run"],
  event: ["id", "event", "value", "on", "why", "run"],
  alias: ["old", "scheme", "id", "why", "run"],
  run: ["run", "at", "tool", "inputs"],
};

const DERIV_SCHEME = {
  op: "package-operator",
  lp: "package-line",
  cx: "group-code",
  st: "derivation",
  ls: "derivation",
};

const KEY_SCHEME = {
  ...DERIV_SCHEME,
  ln: "crosswalk",
};

export const REPORT_RULES = [
  "line-family-candidate",
  "same-operator-split-names",
  "same-operator-multi-codes",
  "cross-complex-same-station",
  "unmapped-source",
  "ambiguous-company-text",
  "identity-not-a-railway",
  "history-unmatched",
  "shared-facility-candidate",
  "name-line-not-unique",
  "line-label-collision",
  "line-alias-is-country-code",
  "station-code-conflict",
  "crosswalk-conflict",
];

const NOT_MAPPED = [
  "raw/display vertex ordinal",
  "display part index + metre ruler",
  "native chain",
  "capture pointOrdinal",
];

export function canonical(record, keyOrder) {
  const out = {};
  for (const key of keyOrder) {
    const value = record[key];
    if (value === null || value === undefined || value === "") continue;
    out[key] = value;
  }
  return JSON.stringify(out);
}

export function compareText(a, b) {
  const left = String(a);
  const right = String(b);
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

export function compareId(a, b) {
  const left = ID_RE.exec(a);
  const right = ID_RE.exec(b);
  if (!left || !right) return compareText(a, b);
  if (left[1] !== right[1]) return compareText(left[1], right[1]);
  if (left[2] !== right[2]) return compareText(left[2], right[2]);
  return Number(left[3]) - Number(right[3]);
}

export function nextSeq(entities, region, kind) {
  let max = 0;
  for (const id of entities.keys()) {
    const match = ID_RE.exec(id);
    if (match && match[1] === kind && match[2] === region) max = Math.max(max, Number(match[3]));
  }
  return max + 1;
}

function headerKeys(headerKind) {
  return headerKind === "runs" ? ["schema", "kind"] : ["schema", "region", "kind"];
}

function headerLine(region, headerKind) {
  const record = headerKind === "runs"
    ? { schema: SCHEMA_ID, kind: "runs" }
    : { schema: SCHEMA_ID, region, kind: headerKind };
  return canonical(record, headerKeys(headerKind));
}

export function classifyLedgerName(name) {
  if (name === "runs.jsonl") return { type: "run", headerKind: "runs" };
  if (name === "alias.jsonl") return { type: "alias", headerKind: "alias" };
  if (name === "events.jsonl") return { type: "event", headerKind: "events" };
  const match = /^(op|ln|lp|cx|st|ls|rp|fc)(\.ref)?\.jsonl$/.exec(name);
  if (!match) return null;
  return match[2]
    ? { type: "ref", kind: match[1], headerKind: `${match[1]}.ref` }
    : { type: "entity", kind: match[1], headerKind: match[1] };
}

function emptyLedger() {
  return {
    entities: new Map(),
    refs: [],
    events: [],
    aliases: [],
    runs: [],
    fileLines: new Map(),
  };
}

function listLedgerFiles(root) {
  const files = [];
  if (!fs.existsSync(root)) return files;
  const runs = path.join(root, "runs.jsonl");
  if (fs.existsSync(runs)) files.push({ abs: runs, region: null, name: "runs.jsonl" });
  for (const region of REGIONS) {
    const dir = path.join(root, region);
    if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) continue;
    const present = new Set(fs.readdirSync(dir));
    for (const name of fs.readdirSync(dir)) {
      if (!name.endsWith(".jsonl")) continue;
      if (!classifyLedgerName(name)) {
        files.push({ abs: path.join(dir, name), region, name, unknown: true });
      }
    }
    const ordered = [];
    for (const kind of FILE_KINDS) ordered.push(`${kind}.jsonl`, `${kind}.ref.jsonl`);
    ordered.push("alias.jsonl", "events.jsonl");
    for (const name of ordered) {
      if (present.has(name)) files.push({ abs: path.join(dir, name), region, name });
    }
  }
  return files;
}

export function parseLedger(root) {
  const ledger = emptyLedger();
  const violations = [];
  for (const file of listLedgerFiles(root)) {
    const rel = path.relative(root, file.abs);
    if (file.unknown) {
      violations.push(`${rel}:0 unknown ledger file`);
      continue;
    }
    const info = classifyLedgerName(file.name);
    const text = fs.readFileSync(file.abs);
    if (text.length === 0 || text[text.length - 1] !== 0x0a) violations.push(`${rel}: missing trailing newline`);
    const raw = text.toString("utf8").split("\n");
    if (raw[raw.length - 1] === "") raw.pop();
    ledger.fileLines.set(file.abs, raw.slice());
    let lastSeq = 0;
    raw.forEach((line, index) => {
      const lineNo = index + 1;
      const where = `${rel}:${lineNo}`;
      if (line === "") {
        violations.push(`${where}: empty line`);
        return;
      }
      let parsed;
      try {
        parsed = JSON.parse(line);
      } catch {
        violations.push(`${where}: invalid json`);
        return;
      }
      const keys = index === 0 ? headerKeys(info.headerKind) : KEY_ORDERS[info.type];
      if (canonical(parsed, keys) !== line) {
        violations.push(`${where}: not canonical`);
        return;
      }
      if (index === 0) {
        if (parsed.schema !== SCHEMA_ID || parsed.kind !== info.headerKind) {
          violations.push(`${where}: bad header`);
        } else if (info.headerKind !== "runs" && parsed.region !== file.region) {
          violations.push(`${where}: header region`);
        }
        return;
      }
      if (info.type === "run") {
        ledger.runs.push(parsed);
        return;
      }
      const id = info.type === "alias" ? parsed.id : parsed.id;
      const match = ID_RE.exec(id ?? "");
      if (!match) {
        violations.push(`${where}: bad id`);
        return;
      }
      if (file.region && match[2] !== file.region) violations.push(`${where}: region mismatch`);
      if ((info.type === "entity" || info.type === "ref") && match[1] !== info.kind) {
        violations.push(`${where}: kind mismatch`);
      }
      if (info.type === "entity") {
        const seq = Number(match[3]);
        if (seq <= lastSeq) violations.push(`${where}: seq not increasing`);
        lastSeq = seq;
        if (ledger.entities.has(parsed.id)) violations.push(`${where}: duplicate id ${parsed.id}`);
        else ledger.entities.set(parsed.id, parsed);
        return;
      }
      if (info.type === "ref") ledger.refs.push(parsed);
      else if (info.type === "event") ledger.events.push(parsed);
      else ledger.aliases.push(parsed);
    });
  }
  return { ledger, violations };
}

export function readLedger(root) {
  const { ledger, violations } = parseLedger(root);
  if (violations.length) throw new Error(violations[0]);
  return ledger;
}

function blankAdditions() {
  return {
    entities: [],
    refs: [],
    events: [],
    aliases: [],
    runs: [],
    reappeared: [],
    conflicts: [],
    crosswalkConflicts: [],
  };
}

export function additionsEmpty(additions) {
  return ["entities", "refs", "events", "aliases", "runs"].every((key) => !(additions[key]?.length));
}

export function planLedgerWrites(root, additions) {
  const groups = new Map();
  const touch = (rel, region, headerKind) => {
    if (!groups.has(rel)) {
      groups.set(rel, {
        rel,
        abs: path.join(root, rel),
        region,
        headerKind,
        header: headerLine(region, headerKind),
        lines: [],
      });
    }
    return groups.get(rel);
  };
  for (const item of additions.entities ?? []) {
    touch(path.join(item.region, `${item.kind}.jsonl`), item.region, item.kind)
      .lines.push(canonical(item.rec, KEY_ORDERS.entity));
  }
  const refsByFile = new Map();
  for (const item of additions.refs ?? []) {
    const rel = path.join(item.region, `${item.kind}.ref.jsonl`);
    if (!refsByFile.has(rel)) refsByFile.set(rel, []);
    refsByFile.get(rel).push(item);
  }
  for (const [rel, items] of refsByFile) {
    items.sort((a, b) => compareId(a.rec.id, b.rec.id)
      || compareText(a.rec.scheme, b.rec.scheme)
      || compareText(a.rec.value, b.rec.value));
    const bucket = touch(rel, items[0].region, `${items[0].kind}.ref`);
    for (const item of items) bucket.lines.push(canonical(item.rec, KEY_ORDERS.ref));
  }
  for (const item of additions.events ?? []) {
    touch(path.join(item.region, "events.jsonl"), item.region, "events")
      .lines.push(canonical(item.rec, KEY_ORDERS.event));
  }
  for (const item of additions.aliases ?? []) {
    touch(path.join(item.region, "alias.jsonl"), item.region, "alias")
      .lines.push(canonical(item.rec, KEY_ORDERS.alias));
  }
  for (const item of additions.runs ?? []) {
    touch("runs.jsonl", null, "runs").lines.push(canonical(item.rec, KEY_ORDERS.run));
  }
  return [...groups.values()].filter((group) => group.lines.length > 0);
}

function fileRank(rel) {
  if (rel === "runs.jsonl" || rel.endsWith(`${path.sep}runs.jsonl`)) return 4;
  if (rel.endsWith(".ref.jsonl")) return 0;
  if (rel.endsWith(`${path.sep}alias.jsonl`) || rel === "alias.jsonl") return 1;
  if (rel.endsWith(`${path.sep}events.jsonl`) || rel === "events.jsonl") return 3;
  return 2;
}

export function appendLedger(root, additions) {
  const plans = planLedgerWrites(root, additions).sort(
    (a, b) => fileRank(a.rel) - fileRank(b.rel) || compareText(a.rel, b.rel),
  );
  const prepared = [];
  const crashAfter = process.env.JTM_REGISTRY_CRASH_AFTER || "";
  const crashRank = { refs: 0, alias: 1, entities: 2, events: 3, runs: 4 }[crashAfter];
  try {
    for (const plan of plans) {
      fs.mkdirSync(path.dirname(plan.abs), { recursive: true });
      const exists = fs.existsSync(plan.abs);
      let prefix = exists ? fs.readFileSync(plan.abs) : Buffer.from(`${plan.header}\n`, "utf8");
      if (prefix.length && prefix[prefix.length - 1] !== 0x0a) prefix = Buffer.concat([prefix, Buffer.from("\n")]);
      const extra = Buffer.from(plan.lines.map((line) => `${line}\n`).join(""), "utf8");
      const tmp = path.join(path.dirname(plan.abs), `.${path.basename(plan.abs)}.${process.pid}.tmp`);
      prepared.push({ plan, tmp, exists, renamed: false });
      const fd = fs.openSync(tmp, "w");
      try {
        fs.writeSync(fd, Buffer.concat([prefix, extra]));
        fs.fsyncSync(fd);
      } finally {
        fs.closeSync(fd);
      }
    }
    let lastRank = -1;
    for (const item of prepared) {
      const rank = fileRank(item.plan.rel);
      if (crashRank !== undefined && lastRank === crashRank && rank > crashRank) {
        throw new Error(`injected crash after ${crashAfter}`);
      }
      fs.renameSync(item.tmp, item.plan.abs);
      item.renamed = true;
      item.plan.exists = item.exists;
      lastRank = rank;
    }
    if (crashRank !== undefined && prepared.length > 0 && lastRank === crashRank) {
      throw new Error(`injected crash after ${crashAfter}`);
    }
  } catch (error) {
    for (const item of prepared) {
      if (!item.renamed) fs.rmSync(item.tmp, { force: true });
    }
    throw error;
  }
  return plans;
}

function seqOf(id) {
  return Number(id.split(":")[2]);
}

function haversineMetres(lon1, lat1, lon2, lat2) {
  const radius = 6371000;
  const rad = (degrees) => degrees * Math.PI / 180;
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * radius * Math.asin(Math.min(1, Math.sqrt(a)));
}

function intersects(a, b) {
  return a[0] <= b[2] && b[0] <= a[2] && a[1] <= b[3] && b[1] <= a[3];
}

function boundsOf(points) {
  if (!points.length) return null;
  let minLon = Infinity;
  let minLat = Infinity;
  let maxLon = -Infinity;
  let maxLat = -Infinity;
  for (const [lon, lat] of points) {
    if (lon < minLon) minLon = lon;
    if (lat < minLat) minLat = lat;
    if (lon > maxLon) maxLon = lon;
    if (lat > maxLat) maxLat = lat;
  }
  return [minLon, minLat, maxLon, maxLat];
}

export function stripPackageLineId(id) {
  let value = String(id);
  let previous;
  do {
    previous = value;
    value = value.replace(/-p\d+$/, "").replace(/-\d+$/, "");
  } while (value !== previous);
  return value;
}

function normText(value) {
  return String(value ?? "").normalize("NFKC").trim().replace(/\s+/g, " ");
}

function hasTable(db, name) {
  return !!db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(name);
}

function planStationCodes(rows) {
  const byCode = new Map();
  for (const row of rows) {
    if (!row.code) continue;
    if (!byCode.has(row.code)) byCode.set(row.code, []);
    byCode.get(row.code).push(row);
  }
  const assign = [];
  const conflicts = [];
  for (const [code, group] of byCode) {
    const operators = new Set(group.map((row) => row.operator));
    const candidates = [...new Set(group.map((row) => row.stId).filter(Boolean))].sort(compareId);
    if (operators.size > 1 || candidates.length > 1) conflicts.push({ value: code, candidates });
    else if (candidates.length === 1) assign.push({ code, stId: candidates[0] });
  }
  conflicts.sort((a, b) => compareText(a.value, b.value));
  assign.sort((a, b) => compareText(a.code, b.code) || compareId(a.stId, b.stId));
  return { assign, conflicts };
}

function crosswalkKey(lpIds) {
  return [...(lpIds ?? [])].map(String).sort(compareId).join(",");
}

function readLineCrosswalk(root, region) {
  if (!root) return null;
  const file = path.join(root, region, "line-crosswalk.json");
  if (!fs.existsSync(file)) return null;
  const doc = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!doc || doc.schema !== "jtm-line-crosswalk/1" || !Array.isArray(doc.groups)) {
    throw new Error(`bad line-crosswalk ${file}`);
  }
  return doc;
}

function sortedCrosswalkGroups(doc) {
  return [...doc.groups].sort((a, b) => compareText(String(a.slug ?? ""), String(b.slug ?? ""))
    || compareText(crosswalkKey(a.lp), crosswalkKey(b.lp)));
}

function crosswalkBadMembers(group, { hasEntity, isRetired, assignedLn, existingLn }) {
  const lpIds = Array.isArray(group.lp) ? group.lp.map(String).sort(compareId) : [];
  const bad = [];
  if (!lpIds.length) bad.push({ lp: "", ln: null });
  for (const lpId of lpIds) {
    const current = assignedLn(lpId);
    if (!hasEntity(lpId) || isRetired(lpId)) bad.push({ lp: lpId, ln: current });
    else if (current && current !== existingLn) bad.push({ lp: lpId, ln: current });
  }
  bad.sort((a, b) => compareId(a.lp, b.lp));
  return { lpIds, bad };
}

export function mint(db, ledger, { region, runId, at, root } = {}) {
  if (!REGIONS.includes(region)) throw new Error(`unknown region ${region}`);
  if (!Number.isInteger(runId) || runId < 1) throw new Error("runId must be a positive integer");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(at ?? "")) throw new Error("at must be YYYY-MM-DD");
  const country = region.toUpperCase();
  const additions = blankAdditions();
  const entities = new Map(ledger.entities);
  const retired = new Set();
  for (const event of ledger.events) {
    if (event.event === "retire") retired.add(event.id);
  }
  const refIndex = new Map();
  const derivByEntity = new Map();
  const keyRefCount = new Map();
  for (const ref of ledger.refs) {
    const parts = String(ref.id).split(":");
    if (parts[1] !== region) continue;
    refIndex.set(`${ref.scheme}\0${ref.value}`, ref.id);
    if (DERIV_SCHEME[parts[0]] === ref.scheme) derivByEntity.set(ref.id, ref.value);
    if (KEY_SCHEME[parts[0]] === ref.scheme) keyRefCount.set(ref.id, (keyRefCount.get(ref.id) ?? 0) + 1);
  }
  for (const id of entities.keys()) {
    const parts = String(id).split(":");
    if (parts[1] !== region || !KEY_SCHEME[parts[0]]) continue;
    if (keyRefCount.get(id) !== 1) throw new Error(`ledger incomplete: ${id} key ref`);
  }
  const inputs = { op: new Set(), lp: new Set(), cx: new Set(), st: new Set(), ls: new Set() };
  const seq = Object.fromEntries(KINDS.map((kind) => [kind, nextSeq(entities, region, kind)]));
  const seenReappeared = new Set();

  const noteReappeared = (entry) => {
    const key = `${entry.id ?? ""}\0${entry.scheme}\0${entry.value}`;
    if (seenReappeared.has(key)) return;
    seenReappeared.add(key);
    additions.reappeared.push(entry);
  };

  const addRef = (kind, id, scheme, value) => {
    const key = `${scheme}\0${value}`;
    if (refIndex.has(key)) return false;
    refIndex.set(key, id);
    additions.refs.push({ region, kind, rec: { id, scheme, value, run: runId } });
    if (DERIV_SCHEME[kind] === scheme) derivByEntity.set(id, value);
    return true;
  };

  const rememberEntity = (kind, id, parent, part) => {
    const rec = { id, run: runId };
    if (parent) rec.parent = parent;
    if (part) rec.part = part;
    additions.entities.push({ region, kind, rec });
    entities.set(id, rec);
    return id;
  };

  const ensureEntity = (kind, scheme, value, { parent, part } = {}) => {
    const existing = refIndex.get(`${scheme}\0${value}`);
    if (existing) {
      if (retired.has(existing)) {
        noteReappeared({ region, id: existing, scheme, value });
        return null;
      }
      inputs[kind].add(value);
      if (!entities.has(existing)) rememberEntity(kind, existing, parent, part);
      return existing;
    }
    if ((parent && retired.has(parent)) || (part && retired.has(part))) {
      const retiredId = parent && retired.has(parent) ? parent : part;
      noteReappeared({
        region,
        id: retiredId,
        scheme: KEY_SCHEME[retiredId.split(":")[0]] ?? scheme,
        value: derivByEntity.get(retiredId) ?? value,
      });
      return null;
    }
    inputs[kind].add(value);
    const id = `${kind}:${region}:${seq[kind]}`;
    seq[kind] += 1;
    rememberEntity(kind, id, parent, part);
    addRef(kind, id, scheme, value);
    return id;
  };

  const operators = db.prepare(
    "SELECT id, name FROM operator WHERE country_code = ? ORDER BY id",
  ).all(country);
  const opByOperatorId = new Map();
  for (const row of operators) {
    const id = ensureEntity("op", "package-operator", row.name);
    if (id) opByOperatorId.set(row.id, id);
  }

  const lines = db.prepare(`
    SELECT rowid AS line_rowid, id
      FROM line
     WHERE country_code = ?
     ORDER BY rowid
  `).all(country);
  const lpByLineId = new Map();
  for (const row of lines) {
    const id = ensureEntity("lp", "package-line", row.id);
    if (id) lpByLineId.set(row.id, id);
  }

  const stations = db.prepare(`
    SELECT id, code
      FROM station
     WHERE country_code = ?
     ORDER BY id
  `).all(country);
  const cxByCode = new Map();
  for (const row of stations) {
    const id = ensureEntity("cx", "group-code", row.code);
    if (id) cxByCode.set(row.code, id);
  }

  const codeRows = hasTable(db, "source_station")
    ? db.prepare(`
        SELECT group_code, operator, station_code
          FROM source_station
         WHERE country_code = ?
         ORDER BY group_code, operator, station_code
      `).all(country)
    : [];

  const pairs = db.prepare(`
    SELECT DISTINCT s.code AS code, o.id AS operator_id, o.name AS operator_name
      FROM line_station ls
      JOIN line l ON l.id = ls.line_id
      JOIN station s ON s.id = ls.station_id
      JOIN operator o ON o.id = l.operator_id
     WHERE l.country_code = ?
  `).all(country);
  const stRows = [];
  for (const row of pairs) {
    const cx = cxByCode.get(row.code);
    const op = opByOperatorId.get(row.operator_id);
    if (!cx || !op) continue;
    stRows.push({ ...row, cx, op, cxSeq: seqOf(cx), opSeq: seqOf(op) });
  }
  stRows.sort((a, b) => a.cxSeq - b.cxSeq || a.opSeq - b.opSeq || compareText(a.code, b.code));
  const stByCxOp = new Map();
  for (const row of stRows) {
    const value = `${row.cx}|${row.op}`;
    const id = ensureEntity("st", "derivation", value, { parent: row.cx });
    if (!id) continue;
    stByCxOp.set(`${row.cx}|${row.op}`, id);
  }
  const opIdByName = new Map(operators.map((row) => [row.name, row.id]));
  const stationCodeRows = [];
  for (const row of codeRows) {
    if (!row.station_code) continue;
    const operatorId = opIdByName.get(row.operator);
    const op = operatorId == null ? null : opByOperatorId.get(operatorId);
    const cx = cxByCode.get(row.group_code);
    const stId = op && cx ? stByCxOp.get(`${cx}|${op}`) ?? null : null;
    stationCodeRows.push({ code: row.station_code, operator: row.operator, stId });
  }
  const stationCodes = planStationCodes(stationCodeRows);
  for (const conflict of stationCodes.conflicts) {
    additions.conflicts.push({ region, value: conflict.value, candidates: conflict.candidates });
  }
  for (const item of stationCodes.assign) addRef("st", item.stId, "station-code", item.code);

  const stops = db.prepare(`
    SELECT l.rowid AS line_rowid, ls.seq AS seq, ls.line_id AS line_id,
           s.code AS code, l.operator_id AS operator_id
      FROM line_station ls
      JOIN line l ON l.id = ls.line_id
      JOIN station s ON s.id = ls.station_id
     WHERE l.country_code = ?
     ORDER BY l.rowid, ls.seq
  `).all(country);
  for (const row of stops) {
    const lp = lpByLineId.get(row.line_id);
    const cx = cxByCode.get(row.code);
    const op = opByOperatorId.get(row.operator_id);
    if (!lp || !cx || !op) continue;
    if (retired.has(lp) || retired.has(cx) || retired.has(op)) continue;
    const stId = stByCxOp.get(`${cx}|${op}`);
    if (!stId || retired.has(stId)) continue;
    ensureEntity("ls", "derivation", `${lp}|${stId}`, { parent: stId, part: lp });
  }

  const retireIds = [];
  for (const id of entities.keys()) {
    const match = ID_RE.exec(id);
    if (!match || match[2] !== region || !KINDS.includes(match[1])) continue;
    if (retired.has(id)) continue;
    const value = derivByEntity.get(id);
    if (value === undefined) continue;
    if (!inputs[match[1]].has(value)) retireIds.push(id);
  }
  retireIds.sort(compareId);
  for (const id of retireIds) {
    additions.events.push({
      region,
      rec: { id, event: "retire", on: at, why: "absent from inputs", run: runId },
    });
    retired.add(id);
  }

  const crosswalk = readLineCrosswalk(root, region);
  if (crosswalk) {
    const assigned = new Map();
    for (const event of ledger.events) {
      if (event.event === "line") assigned.set(event.id, event.value);
    }
    for (const item of additions.events) {
      if (item.rec.event === "line") assigned.set(item.rec.id, item.rec.value);
    }
    let lnSeq = nextSeq(entities, region, "ln");
    for (const group of sortedCrosswalkGroups(crosswalk)) {
      const lpIds = Array.isArray(group.lp) ? group.lp.map(String).sort(compareId) : [];
      const value = lpIds.join(",");
      const existing = value ? refIndex.get(`crosswalk\0${value}`) ?? null : null;
      const { bad } = crosswalkBadMembers(group, {
        hasEntity: (id) => entities.has(id),
        isRetired: (id) => retired.has(id),
        assignedLn: (id) => assigned.get(id) ?? null,
        existingLn: existing,
      });
      if (bad.length) {
        additions.crosswalkConflicts.push({
          slug: String(group.slug ?? ""),
          lp: lpIds,
          assigned: bad,
        });
        continue;
      }
      if (existing && retired.has(existing)) {
        noteReappeared({ region, id: existing, scheme: "crosswalk", value });
        continue;
      }
      let lnId = existing;
      if (existing && !entities.has(existing)) {
        const rec = { id: existing, slug: String(group.slug ?? ""), run: runId };
        additions.entities.push({ region, kind: "ln", rec });
        entities.set(existing, rec);
      }
      if (!existing) {
        lnId = `ln:${region}:${lnSeq}`;
        lnSeq += 1;
        const rec = { id: lnId, slug: String(group.slug ?? ""), run: runId };
        additions.entities.push({ region, kind: "ln", rec });
        entities.set(lnId, rec);
        addRef("ln", lnId, "crosswalk", value);
      }
      const why = group.why ? String(group.why) : "line-crosswalk";
      for (const lpId of lpIds) {
        if (assigned.get(lpId) === lnId) continue;
        additions.events.push({
          region,
          rec: { id: lpId, event: "line", value: lnId, why, run: runId },
        });
        assigned.set(lpId, lnId);
      }
    }
    additions.crosswalkConflicts.sort((a, b) => compareText(a.slug, b.slug) || compareText(a.lp.join(","), b.lp.join(",")));
  }
  return additions;
}

function pushMap(map, key, value) {
  const list = map.get(key);
  if (list) list.push(value);
  else map.set(key, [value]);
}

function ledgerIndex(ledger, region) {
  const retired = new Set();
  for (const event of ledger.events) {
    if (event.event === "retire") retired.add(event.id);
  }
  const byKey = new Map();
  for (const ref of ledger.refs) {
    const parts = String(ref.id).split(":");
    if (parts[1] !== region) continue;
    const key = `${ref.scheme}\0${ref.value}`;
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key).push(ref.id);
  }
  const idFor = (scheme, value) => {
    const ids = byKey.get(`${scheme}\0${value}`) ?? [];
    return ids.find((id) => !retired.has(id)) ?? ids[0] ?? null;
  };
  return { retired, idFor };
}

function loadFacts(db, region) {
  const country = region.toUpperCase();
  const operators = db.prepare(`
    SELECT id, name, short_name, display_label
      FROM operator
     WHERE country_code = ?
     ORDER BY id
  `).all(country);
  const lines = db.prepare(`
    SELECT l.rowid AS line_rowid, l.id, l.name, l.line_code, l.railway_identity,
           l.interval_count, l.operator_id, o.name AS operator_name, o.short_name
      FROM line l
      JOIN operator o ON o.id = l.operator_id
     WHERE l.country_code = ?
     ORDER BY l.rowid
  `).all(country);
  const stations = db.prepare(`
    SELECT id, code, name, name_norm, lon, lat
      FROM station
     WHERE country_code = ?
     ORDER BY id
  `).all(country);
  const stops = db.prepare(`
    SELECT ls.line_id, ls.seq, ls.station_id, ls.name, ls.lon, ls.lat,
           s.code, s.name_norm, l.operator_id
      FROM line_station ls
      JOIN station s ON s.id = ls.station_id
      JOIN line l ON l.id = ls.line_id
     WHERE l.country_code = ?
     ORDER BY l.rowid, ls.seq
  `).all(country);
  const sources = hasTable(db, "source_station")
    ? db.prepare(`
        SELECT ord, station_code, group_code, station_id, name, line_name, operator,
               display_lon, display_lat
          FROM source_station
         WHERE country_code = ?
         ORDER BY ord, station_code
      `).all(country)
    : [];
  const aliases = hasTable(db, "operator_alias")
    ? db.prepare("SELECT alias, label FROM operator_alias WHERE scope = ? ORDER BY alias").all(country)
    : [];
  return { operators, lines, stations, stops, sources, aliases };
}

function qualifiedLabel(operatorName, shortName, lineName) {
  return `${shortName || operatorName}${lineName}`;
}

function lineLabel(line, nameCounts) {
  if ((nameCounts.get(line.name) ?? 0) > 1) return qualifiedLabel(line.operator_name, line.short_name, line.name);
  return line.name;
}

export function reports(db, ledger, region, root) {
  const facts = loadFacts(db, region);
  const index = ledgerIndex(ledger, region);
  const opById = new Map(facts.operators.map((row) => [row.id, row]));
  const operatorByName = new Map(facts.operators.map((row) => [row.name, row]));
  const lineById = new Map(facts.lines.map((row) => [row.id, row]));
  const stationById = new Map(facts.stations.map((row) => [row.id, row]));
  const nameCounts = new Map();
  for (const line of facts.lines) nameCounts.set(line.name, (nameCounts.get(line.name) ?? 0) + 1);
  const operatorUsers = new Map();
  for (const line of facts.lines) {
    if (!operatorUsers.has(line.name)) operatorUsers.set(line.name, new Set());
    operatorUsers.get(line.name).add(line.operator_id);
  }
  const cxOfCode = (code) => index.idFor("group-code", code);
  const opOf = (operatorId) => {
    const row = opById.get(operatorId);
    return row ? index.idFor("package-operator", row.name) : null;
  };
  const lpOf = (lineId) => index.idFor("package-line", lineId);
  const stOf = (cx, op) => (cx && op ? index.idFor("derivation", `${cx}|${op}`) : null);

  const out = {};

  const families = new Map();
  const identities = new Map();
  for (const line of facts.lines) {
    const lp = lpOf(line.id);
    if (!lp) continue;
    const stripped = stripPackageLineId(line.id);
    const familyKey = `${line.operator_id}\0${stripped}`;
    if (!families.has(familyKey)) {
      families.set(familyKey, {
        by: "stripped-id",
        key: stripped,
        operators: [line.operator_name],
        lp: [],
      });
    }
    families.get(familyKey).lp.push(lp);
    if (line.railway_identity) {
      if (!identities.has(line.railway_identity)) identities.set(line.railway_identity, []);
      identities.get(line.railway_identity).push(line);
    }
  }
  const familyRows = [];
  for (const group of families.values()) {
    if (group.lp.length < 2) continue;
    group.lp.sort(compareId);
    familyRows.push(group);
  }
  for (const [key, members] of identities) {
    if (members.length < 2) continue;
    const lps = members.map((line) => lpOf(line.id)).filter(Boolean).sort(compareId);
    if (lps.length < 2) continue;
    familyRows.push({
      by: "railway_identity",
      key,
      operators: [...new Set(members.map((line) => line.operator_name))].sort(compareText),
      lp: lps,
    });
  }
  familyRows.sort((a, b) => compareText(a.by, b.by) || compareText(a.key, b.key) || compareText(a.operators.join("|"), b.operators.join("|")));
  out["line-family-candidate"] = familyRows;

  const namesBySt = new Map();
  for (const source of facts.sources) {
    const operator = operatorByName.get(source.operator);
    if (!operator || !source.name) continue;
    const cx = cxOfCode(source.group_code);
    const op = opOf(operator.id);
    if (!cx || !op) continue;
    const key = `${cx}\0${op}`;
    if (!namesBySt.has(key)) namesBySt.set(key, { cx, op, st: stOf(cx, op), names: new Set() });
    namesBySt.get(key).names.add(source.name);
  }
  out["same-operator-split-names"] = [...namesBySt.values()]
    .filter((group) => group.names.size > 1)
    .map((group) => ({ cx: group.cx, op: group.op, st: group.st, names: [...group.names].sort(compareText) }))
    .sort((a, b) => compareId(a.cx, b.cx) || compareId(a.op, b.op));

  const codesBySt = new Map();
  for (const source of facts.sources) {
    if (!source.station_code) continue;
    const operator = operatorByName.get(source.operator);
    if (!operator) continue;
    const cx = cxOfCode(source.group_code);
    const op = opOf(operator.id);
    if (!cx || !op) continue;
    const key = `${cx}\0${op}`;
    if (!codesBySt.has(key)) codesBySt.set(key, { cx, op, st: stOf(cx, op), codes: new Set() });
    codesBySt.get(key).codes.add(source.station_code);
  }
  out["same-operator-multi-codes"] = [...codesBySt.values()]
    .filter((group) => group.codes.size > 1)
    .map((group) => ({ cx: group.cx, op: group.op, st: group.st, codes: [...group.codes].sort(compareText) }))
    .sort((a, b) => compareId(a.cx, b.cx) || compareId(a.op, b.op));

  const served = new Map();
  for (const stop of facts.stops) {
    const station = stationById.get(stop.station_id);
    const cx = cxOfCode(stop.code);
    const op = opOf(stop.operator_id);
    if (!station || !cx || !op) continue;
    const key = `${op}\0${station.name_norm}`;
    if (!served.has(key)) served.set(key, new Map());
    served.get(key).set(cx, station);
  }
  const cross = [];
  for (const [key, complexes] of served) {
    const [op] = key.split("\0");
    const rows = [...complexes.entries()].sort((a, b) => compareId(a[0], b[0]));
    for (let i = 0; i < rows.length; i += 1) {
      for (let j = i + 1; j < rows.length; j += 1) {
        const metres = haversineMetres(rows[i][1].lon, rows[i][1].lat, rows[j][1].lon, rows[j][1].lat);
        if (metres < 500) {
          cross.push({
            name: rows[i][1].name_norm,
            op,
            cx: [rows[i][0], rows[j][0]],
            metres: Math.round(metres),
          });
        }
      }
    }
  }
  cross.sort((a, b) => compareText(a.name, b.name) || compareId(a.op, b.op) || compareId(a.cx[0], b.cx[0]) || compareId(a.cx[1], b.cx[1]));
  out["cross-complex-same-station"] = cross;

  out["unmapped-source"] = facts.sources
    .filter((row) => row.station_id === null || row.station_id === undefined)
    .map((row) => ({
      ord: row.ord,
      station_code: row.station_code,
      group_code: row.group_code,
      name: row.name,
      line_name: row.line_name,
      operator: row.operator,
    }))
    .sort((a, b) => a.ord - b.ord || compareText(a.station_code, b.station_code));

  out["ambiguous-company-text"] = ambiguousCompanies(facts, region);

  const identityRows = [];
  for (const [key, members] of identities) {
    if (members.length < 2) continue;
    const operators = [...new Set(members.map((line) => line.operator_name))].sort(compareText);
    const stripped = [...new Set(members.map((line) => stripPackageLineId(line.id)))].sort(compareText);
    if (operators.length === 1 && stripped.length === 1) continue;
    identityRows.push({
      railway_identity: key,
      operators,
      stripped,
      lp: members.map((line) => lpOf(line.id)).filter(Boolean).sort(compareId),
    });
  }
  identityRows.sort((a, b) => compareText(a.railway_identity, b.railway_identity));
  out["identity-not-a-railway"] = identityRows;

  out["history-unmatched"] = historyUnmatched(facts, region, lpOf);

  const facility = sharedFacilities(facts, index, opOf, cxOfCode);
  out["shared-facility-candidate"] = facility;

  out["name-line-not-unique"] = nameLineCollisions(facts, index, cxOfCode, operatorUsers, opById);
  out["line-label-collision"] = [...operatorUsers.entries()]
    .filter(([, operators]) => operators.size > 1)
    .map(([name, operators]) => ({
      name,
      operators: [...operators].map((id) => opById.get(id).name).sort(compareText),
    }))
    .sort((a, b) => compareText(a.name, b.name));

  const aliasRows = [];
  for (const line of facts.lines) {
    const lp = lpOf(line.id);
    for (const field of ["name", "line_code"]) {
      const value = line[field];
      if (!value) continue;
      if (COUNTRY_CODES.includes(String(value).trim().toLowerCase())) {
        aliasRows.push({ lp, line: line.id, field, value });
      }
    }
  }
  aliasRows.sort((a, b) => compareText(a.field, b.field) || compareText(a.value, b.value) || compareText(a.line, b.line));
  out["line-alias-is-country-code"] = aliasRows;

  const stationCodeRows = facts.sources.map((source) => {
    const operator = operatorByName.get(source.operator);
    const cx = cxOfCode(source.group_code);
    const op = operator ? opOf(operator.id) : null;
    const st = cx && op ? stOf(cx, op) : null;
    return {
      code: source.station_code,
      operator: source.operator,
      stId: st && !index.retired.has(st) ? st : null,
    };
  });
  out["station-code-conflict"] = planStationCodes(stationCodeRows).conflicts;

  const assignedLn = new Map();
  for (const event of ledger.events) {
    if (event.event === "line" && String(event.id).split(":")[1] === region) assignedLn.set(event.id, event.value);
  }
  const crosswalk = readLineCrosswalk(root, region);
  const crosswalkRows = [];
  if (crosswalk) {
    for (const group of sortedCrosswalkGroups(crosswalk)) {
      const lpIds = Array.isArray(group.lp) ? group.lp.map(String).sort(compareId) : [];
      const existing = lpIds.length ? index.idFor("crosswalk", lpIds.join(",")) : null;
      const { bad } = crosswalkBadMembers(group, {
        hasEntity: (id) => ledger.entities.has(id),
        isRetired: (id) => index.retired.has(id),
        assignedLn: (id) => assignedLn.get(id) ?? null,
        existingLn: existing,
      });
      if (bad.length) crosswalkRows.push({ slug: String(group.slug ?? ""), lp: lpIds, assigned: bad });
    }
  }
  out["crosswalk-conflict"] = crosswalkRows;

  const ordered = {};
  for (const rule of REPORT_RULES) ordered[rule] = out[rule];
  return ordered;
}

function ambiguousCompanies(facts, region) {
  const dir = path.join(APP_DIR, "data");
  if (!fs.existsSync(dir)) return [];
  const companies = new Set();
  for (const name of fs.readdirSync(dir)) {
    const match = /^train-store(?:-([a-z]{2}))?\.json$/i.exec(name);
    if (!match) continue;
    const fileRegion = (match[1] || "jp").toLowerCase();
    const doc = JSON.parse(fs.readFileSync(path.join(dir, name), "utf8"));
    const trains = Array.isArray(doc?.trains) ? doc.trains : [];
    for (const train of trains) {
      const trainRegion = train?.region ? String(train.region).toLowerCase() : fileRegion;
      if (trainRegion !== region) continue;
      const company = String(train.company ?? "");
      if (normText(company)) companies.add(company);
    }
  }
  const rows = [];
  for (const company of companies) {
    const key = normText(company);
    const found = new Map();
    for (const operator of facts.operators) {
      if (normText(operator.name) === key || normText(operator.short_name) === key) found.set(operator.id, operator.name);
    }
    for (const alias of facts.aliases) {
      if (normText(alias.alias) !== key) continue;
      const label = normText(alias.label);
      for (const operator of facts.operators) {
        if ([operator.display_label, operator.name, operator.short_name].some((value) => normText(value) === label)) {
          found.set(operator.id, operator.name);
        }
      }
    }
    if (found.size === 1) continue;
    rows.push({
      company,
      candidates: found.size,
      operators: [...found.values()].sort(compareText),
    });
  }
  rows.sort((a, b) => compareText(a.company, b.company));
  return rows;
}

function historyUnmatched(facts, region, lpOf) {
  if (region !== "jp") return [];
  const file = path.join(APP_DIR, "data", "rail-history.json");
  if (!fs.existsSync(file)) return [];
  const doc = JSON.parse(fs.readFileSync(file, "utf8"));
  const stopsByLine = new Map();
  for (const stop of facts.stops) {
    if (!stopsByLine.has(stop.line_id)) stopsByLine.set(stop.line_id, []);
    stopsByLine.get(stop.line_id).push([stop.lon, stop.lat]);
  }
  const lineBounds = new Map();
  for (const line of facts.lines) lineBounds.set(line.id, boundsOf(stopsByLine.get(line.id) ?? []));
  const rows = [];
  for (const collection of ["retirements", "identity_periods"]) {
    for (const entry of doc[collection] ?? []) {
      const match = entry?.match;
      if (!match) continue;
      const bbox = (match.bbox ?? []).map(Number);
      const lps = [];
      if (bbox.length === 4 && bbox.every(Number.isFinite)) {
        for (const line of facts.lines) {
          if (line.name !== match.line_name || line.operator_name !== match.operator) continue;
          const bounds = lineBounds.get(line.id);
          if (!bounds || !intersects(bounds, bbox)) continue;
          const lp = lpOf(line.id);
          if (lp) lps.push(lp);
        }
      }
      lps.sort(compareId);
      if (lps.length === 1) continue;
      rows.push({
        collection,
        history_id: entry.history_id ?? "",
        line_name: match.line_name ?? "",
        operator: match.operator ?? "",
        matchCount: lps.length,
        lp: lps,
      });
    }
  }
  rows.sort((a, b) => compareText(a.collection, b.collection)
    || compareText(a.history_id, b.history_id)
    || compareText(a.line_name, b.line_name)
    || compareText(a.operator, b.operator));
  return rows;
}

function sharedFacilities(facts, index, opOf, cxOfCode) {
  const operatorByName = new Map(facts.operators.map((row) => [row.name, row]));
  const opsByCx = new Map();
  const pointsByCxOp = new Map();
  const addPoint = (cx, op, lon, lat) => {
    if (!Number.isFinite(lon) || !Number.isFinite(lat)) return;
    const key = `${cx}\0${op}`;
    if (!pointsByCxOp.has(key)) pointsByCxOp.set(key, []);
    pointsByCxOp.get(key).push([lon, lat]);
  };
  for (const stop of facts.stops) {
    const cx = cxOfCode(stop.code);
    const op = opOf(stop.operator_id);
    if (!cx || !op) continue;
    if (!opsByCx.has(cx)) opsByCx.set(cx, new Set());
    opsByCx.get(cx).add(op);
    addPoint(cx, op, stop.lon, stop.lat);
  }
  for (const source of facts.sources) {
    const operator = operatorByName.get(source.operator);
    if (!operator) continue;
    const cx = cxOfCode(source.group_code);
    const op = opOf(operator.id);
    if (!cx || !op) continue;
    addPoint(cx, op, source.display_lon, source.display_lat);
  }
  const sharedByCx = new Map();
  const codeOps = new Map();
  for (const source of facts.sources) {
    if (!source.station_code) continue;
    const operator = operatorByName.get(source.operator);
    if (!operator) continue;
    const cx = cxOfCode(source.group_code);
    const op = opOf(operator.id);
    if (!cx || !op) continue;
    const key = `${cx}\0${source.station_code}`;
    if (!codeOps.has(key)) codeOps.set(key, new Set());
    codeOps.get(key).add(op);
  }
  for (const [key, ops] of codeOps) {
    if (ops.size < 2) continue;
    const [cx, code] = key.split("\0");
    if (!sharedByCx.has(cx)) sharedByCx.set(cx, []);
    sharedByCx.get(cx).push(code);
  }
  const rows = [];
  for (const [cx, ops] of opsByCx) {
    if (ops.size < 2) continue;
    const opIds = [...ops].sort(compareId);
    let best = null;
    for (let i = 0; i < opIds.length; i += 1) {
      for (let j = i + 1; j < opIds.length; j += 1) {
        const left = pointsByCxOp.get(`${cx}\0${opIds[i]}`) ?? [];
        const right = pointsByCxOp.get(`${cx}\0${opIds[j]}`) ?? [];
        for (const a of left) {
          for (const b of right) {
            const metres = haversineMetres(a[0], a[1], b[0], b[1]);
            if (best === null || metres < best) best = metres;
          }
        }
      }
    }
    const sharedCodes = (sharedByCx.get(cx) ?? []).sort(compareText);
    if ((best === null || best >= 50) && sharedCodes.length === 0) continue;
    rows.push({
      cx,
      operators: opIds,
      metres: best === null ? null : Math.round(best),
      sharedCodes,
    });
  }
  rows.sort((a, b) => compareId(a.cx, b.cx));
  return rows;
}

function nameLineCollisions(facts, index, cxOfCode, operatorUsers, opById) {
  const bare = new Map();
  const qualified = new Map();
  const stationById = new Map(facts.stations.map((row) => [row.id, row]));
  const lineById = new Map(facts.lines.map((row) => [row.id, row]));
  for (const stop of facts.stops) {
    const station = stationById.get(stop.station_id);
    const line = lineById.get(stop.line_id);
    const cx = cxOfCode(stop.code);
    if (!station || !line || !cx) continue;
    pushMap(bare, `${station.name_norm}\0${line.name}`, cx);
    if ((operatorUsers.get(line.name)?.size ?? 0) > 1) {
      const label = qualifiedLabel(line.operator_name, line.short_name, line.name);
      pushMap(qualified, `${station.name_norm}\0${label}`, cx);
    }
  }
  const rows = [];
  const emit = (map, isQualified) => {
    for (const [key, cxs] of map) {
      const unique = [...new Set(cxs)].sort(compareId);
      if (unique.length < 2) continue;
      const [name, label] = key.split("\0");
      rows.push({ name, label, qualified: isQualified, cx: unique });
    }
  };
  emit(bare, false);
  emit(qualified, true);
  rows.sort((a, b) => Number(a.qualified) - Number(b.qualified) || compareText(a.name, b.name) || compareText(a.label, b.label));
  return rows;
}

export function homonyms(db, ledger, region) {
  const facts = loadFacts(db, region);
  const index = ledgerIndex(ledger, region);
  const cc = region.toUpperCase();
  const nameCounts = new Map();
  for (const line of facts.lines) nameCounts.set(line.name, (nameCounts.get(line.name) ?? 0) + 1);
  const linesByStation = new Map();
  for (const stop of facts.stops) {
    if (!linesByStation.has(stop.station_id)) linesByStation.set(stop.station_id, []);
    linesByStation.get(stop.station_id).push(stop.line_id);
  }
  const lineById = new Map(facts.lines.map((row) => [row.id, row]));
  const byStationName = new Map();
  for (const station of facts.stations) {
    const cx = index.idFor("group-code", station.code);
    if (!cx) continue;
    if (!byStationName.has(station.name)) byStationName.set(station.name, []);
    byStationName.get(station.name).push({ station, cx });
  }
  const stations = [];
  for (const [name, members] of byStationName) {
    if (members.length < 2) continue;
    members.sort((a, b) => compareId(a.cx, b.cx));
    const labels = members.map(({ station }) => {
      const lineIds = linesByStation.get(station.id) ?? [];
      const labelsForStation = lineIds
        .map((id) => lineById.get(id))
        .filter(Boolean)
        .map((line) => lineLabel(line, nameCounts))
        .sort(compareText);
      const label = labelsForStation[0] ?? "";
      return label ? `${name} (${cc}, ${label})` : `${name} (${cc})`;
    });
    stations.push({ name, cx: members.map((member) => member.cx), labels });
  }
  stations.sort((a, b) => compareText(a.name, b.name) || compareId(a.cx[0], b.cx[0]));

  const byLineName = new Map();
  for (const line of facts.lines) {
    const lp = index.idFor("package-line", line.id);
    if (!lp) continue;
    if (!byLineName.has(line.name)) byLineName.set(line.name, []);
    byLineName.get(line.name).push({ line, lp });
  }
  const lines = [];
  for (const [name, members] of byLineName) {
    if (members.length < 2) continue;
    members.sort((a, b) => compareId(a.lp, b.lp));
    lines.push({
      name,
      lp: members.map((member) => member.lp),
      labels: members.map((member) => lineLabel(member.line, nameCounts)),
    });
  }
  lines.sort((a, b) => compareText(a.name, b.name) || compareId(a.lp[0], b.lp[0]));
  return { stations, lines };
}

export function indexSpaceMap(db, ledger, region) {
  const facts = loadFacts(db, region);
  const index = ledgerIndex(ledger, region);
  const stopsByLine = new Map();
  for (const stop of facts.stops) {
    if (!stopsByLine.has(stop.line_id)) stopsByLine.set(stop.line_id, []);
    stopsByLine.get(stop.line_id).push(stop);
  }
  const cxByStation = new Map(facts.stations.map((station) => [station.id, index.idFor("group-code", station.code)]));
  const opByOperatorId = new Map(facts.operators.map((row) => [row.id, index.idFor("package-operator", row.name)]));
  const lines = facts.lines.map((line) => {
    const lp = index.idFor("package-line", line.id);
    const op = opByOperatorId.get(line.operator_id);
    const stops = (stopsByLine.get(line.id) ?? []).map((stop) => {
      const cx = cxByStation.get(stop.station_id);
      const st = cx && op ? index.idFor("derivation", `${cx}|${op}`) : null;
      const ls = lp && st ? index.idFor("derivation", `${lp}|${st}`) : null;
      return { seq: stop.seq, ls };
    });
    return {
      packageLine: line.id,
      lp,
      intervals: line.interval_count,
      stops,
    };
  });
  lines.sort((a, b) => compareText(a.packageLine, b.packageLine));
  return { lines, notMapped: NOT_MAPPED.slice() };
}

function textOrNull(value) {
  if (value === undefined || value === null || value === "") return null;
  return String(value);
}

function collectIds(value, into = new Set()) {
  if (typeof value === "string" && ID_RE.test(value)) into.add(value);
  else if (Array.isArray(value)) value.forEach((item) => collectIds(item, into));
  else if (value && typeof value === "object") Object.values(value).forEach((item) => collectIds(item, into));
  return into;
}

export function loadRegistryTables(db, root) {
  const { ledger, violations } = parseLedger(root);
  if (violations.length) throw new Error(violations[0]);
  const counts = {};
  const tally = (table, n = 1) => {
    counts[table] = (counts[table] || 0) + n;
  };
  const runAt = new Map(ledger.runs.map((run) => [run.run, run.at ?? null]));
  const retiredOn = new Map();
  for (const event of ledger.events) {
    if (event.event === "retire" && !retiredOn.has(event.id)) retiredOn.set(event.id, event.on ?? null);
  }
  const insertEntity = db.prepare(`
    INSERT INTO registry_entity (id, kind, region, slug, parent_id, created, retired)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  const entities = [...ledger.entities.values()].sort((a, b) => {
    const rank = (id) => KIND_RANK[id.split(":")[0]] ?? 99;
    const byKind = rank(a.id) - rank(b.id);
    return byKind || compareId(a.id, b.id);
  });
  for (const entity of entities) {
    const [kind, region] = entity.id.split(":");
    insertEntity.run(
      entity.id,
      kind,
      region,
      textOrNull(entity.slug),
      textOrNull(entity.parent),
      textOrNull(runAt.get(entity.run)),
      textOrNull(retiredOn.get(entity.id)),
    );
    tally("registry_entity");
  }
  const insertRef = db.prepare(`
    INSERT INTO external_ref (entity_id, scheme, value, valid_from, valid_to, source, region)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  for (const ref of ledger.refs) {
    if (!ledger.entities.has(ref.id)) continue;
    const refRegion = String(ref.id).split(":")[1];
    insertRef.run(ref.id, ref.scheme, ref.value, textOrNull(ref.from), textOrNull(ref.to), textOrNull(ref.run), refRegion);
    tally("external_ref");
  }
  const insertAlias = db.prepare(`
    INSERT INTO identity_alias (old_key, scheme, entity_id, reason) VALUES (?, ?, ?, ?)
  `);
  for (const alias of ledger.aliases) {
    if (!ledger.entities.has(alias.id)) continue;
    insertAlias.run(alias.old, alias.scheme, alias.id, textOrNull(alias.why));
    tally("identity_alias");
  }
  const insertOwner = db.prepare(`
    INSERT INTO station_operator (station_id, operator_id, role, valid_from, valid_to)
    VALUES (?, ?, 'owner', NULL, NULL)
  `);
  for (const ref of ledger.refs) {
    if (ref.scheme !== "derivation" || !String(ref.id).startsWith("st:")) continue;
    if (!ledger.entities.has(ref.id)) continue;
    const opId = String(ref.value).split("|")[1];
    if (!opId || !ledger.entities.has(opId)) continue;
    insertOwner.run(ref.id, opId);
    tally("station_operator");
  }
  const insertHomonym = db.prepare(`
    INSERT INTO homonym_group (region, kind, norm_name, entity_id, display_label)
    VALUES (?, ?, ?, ?, ?)
  `);
  const insertException = db.prepare(`
    INSERT INTO registry_exception (region, rule, entity_ids, detail) VALUES (?, ?, ?, ?)
  `);
  const insertExcluded = db.prepare(`
    INSERT INTO excluded_source (region, scheme, value, reason, source) VALUES (?, ?, ?, ?, ?)
  `);
  for (const region of REGIONS) {
    const homonymFile = path.join(root, region, "homonyms.json");
    if (fs.existsSync(homonymFile)) {
      const doc = JSON.parse(fs.readFileSync(homonymFile, "utf8"));
      const emit = (groups, kind, idKey) => {
        for (const group of groups ?? []) {
          const ids = group[idKey] ?? [];
          ids.forEach((id, index) => {
            if (!ledger.entities.has(id)) return;
            insertHomonym.run(region, kind, group.name, id, textOrNull(group.labels?.[index]));
            tally("homonym_group");
          });
        }
      };
      emit(doc.stations, "station", "cx");
      emit(doc.lines, "line", "lp");
    }
    const exceptionFile = path.join(root, region, "station-derivation-exceptions.json");
    if (fs.existsSync(exceptionFile)) {
      const doc = JSON.parse(fs.readFileSync(exceptionFile, "utf8"));
      for (const [rule, entries] of Object.entries(doc)) {
        if (!Array.isArray(entries)) continue;
        for (const entry of entries) {
          const ids = [...collectIds(entry)].sort(compareId);
          insertException.run(region, rule, ids.join(","), JSON.stringify(entry));
          tally("registry_exception");
        }
      }
    }
    const excludedFile = path.join(root, region, "excluded-source.json");
    if (fs.existsSync(excludedFile)) {
      const doc = JSON.parse(fs.readFileSync(excludedFile, "utf8"));
      const rows = Array.isArray(doc) ? doc : (doc.excluded ?? doc.sources ?? []);
      for (const row of rows) {
        insertExcluded.run(region, row.scheme ?? null, row.value ?? null, textOrNull(row.reason), textOrNull(row.source));
        tally("excluded_source");
      }
    }
  }
  return counts;
}
