// Ledger IO, mint, and P0 reports for ADR 0013. The builder only reads the
// ledger; mint-registry.mjs is the only writer. Lines are canonical JSONL and,
// once written, are never edited — later facts are appended.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const APP_DIR = path.resolve(HERE, "..", "..", "..");

export const SCHEMA_ID = "jtm-registry/1";
export const KINDS = ["op", "lp", "cx", "st", "ls", "rp", "fc"];
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
  rp: "route-pattern",
  fc: "facility",
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
  "history-unresolved",
  "history-period-undated",
  "shared-facility-candidate",
  "name-line-not-unique",
  "line-label-collision",
  "line-alias-is-country-code",
  "station-code-conflict",
  "crosswalk-conflict",
  "operator-rename-invalid",
  "bracket-name-unsplit",
];

// Whole trimmed bracket text, exact. Latin markers compare case-insensitively.
// Unknown text stays a subname. Extend this table; do not match substrings.
export const BRACKET_STATUS_MARKERS = {
  reserved: ["预留", "預留"],
  planned: ["规划", "規劃", "计划", "計画", "計画中", "仮称", "在建", "建設中"],
  closed: ["废止", "廢止", "廃止", "停办", "停辦", "关闭", "關閉", "已关闭", "已停用", "停用", "closed"],
  suspended: ["休止", "停运", "停運", "暂停", "暫停", "運休"],
  historical: ["旧", "舊", "原", "前", "历史", "歷史", "旧駅", "旧站", "舊站", "former", "old"],
};

const BRACKET_PAIRS = { "（": "）", "(": ")", "〈": "〉", "<": ">" };
const BRACKET_CLOSERS = new Set(Object.values(BRACKET_PAIRS));
const BRACKET_STATUS_BY_TEXT = new Map();
for (const [status, words] of Object.entries(BRACKET_STATUS_MARKERS)) {
  for (const word of words) BRACKET_STATUS_BY_TEXT.set(word.toLowerCase(), status);
}

export function containsBracketChar(name) {
  return /[（）()〈〉<>]/.test(String(name ?? ""));
}

// One matching bracket group → { base, bracket, kind, position, status? }.
// Zero groups, two or more groups, unbalanced pairs, or an empty base/bracket → null.
export function splitBracketName(name) {
  const text = String(name ?? "");
  const groups = [];
  const stack = [];
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (BRACKET_PAIRS[character]) {
      stack.push({ character, index });
      continue;
    }
    if (!BRACKET_CLOSERS.has(character)) continue;
    if (!stack.length || BRACKET_PAIRS[stack[stack.length - 1].character] !== character) return null;
    const open = stack.pop();
    groups.push({ start: open.index, end: index });
  }
  if (stack.length || groups.length !== 1) return null;
  const group = groups[0];
  const bracket = text.slice(group.start + 1, group.end).trim();
  const base = `${text.slice(0, group.start)}${text.slice(group.end + 1)}`.replace(/\s+/g, " ").trim();
  if (!bracket || !base) return null;
  const status = BRACKET_STATUS_BY_TEXT.get(bracket.toLowerCase()) ?? null;
  const split = {
    base,
    bracket,
    kind: status ? "status" : "subname",
    position: text.slice(group.end + 1).trim() === "" ? "suffix" : "infix",
  };
  if (status) split.status = status;
  return split;
}

// Rows for `name.form` base/bracket. Status column is the category, or `subname`.
export function bracketNameRows(official) {
  const split = splitBracketName(official);
  if (!split) return [];
  return [
    { form: "base", value: split.base, status: null },
    { form: "bracket", value: split.bracket, status: split.kind === "status" ? split.status : "subname" },
  ];
}

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
    operatorRenameInvalid: [],
    operatorNameAmbiguous: [],
    operatorMergeInvalid: [],
    lineOperatorInvalid: [],
    genericOperatorInvalid: [],
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

function readReviewed(root, region, name, schema, listKey) {
  if (!root) return null;
  const file = path.join(root, region, name);
  if (!fs.existsSync(file)) return null;
  const doc = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!doc || doc.schema !== schema || !Array.isArray(doc[listKey])) {
    throw new Error(`bad ${name} ${file}`);
  }
  return doc;
}

function readLineCrosswalk(root, region) {
  return readReviewed(root, region, "line-crosswalk.json", "jtm-line-crosswalk/1", "groups");
}

function readOperatorRenames(root, region) {
  return readReviewed(root, region, "operator-renames.json", "jtm-operator-renames/1", "renames");
}

function readRoutePatterns(root, region) {
  return readReviewed(root, region, "route-patterns.json", "jtm-route-patterns/1", "patterns");
}

function readHistoryCrosswalk(root, region) {
  return readReviewed(root, region, "history-crosswalk.json", "jtm-history-crosswalk/1", "entries");
}

function readOperatorMerges(root, region) {
  return readReviewed(root, region, "operator-merges.json", "jtm-operator-merges/1", "merges");
}

function readLineOperators(root, region) {
  return readReviewed(root, region, "line-operators.json", "jtm-line-operators/1", "lines");
}

function readGenericOperators(root, region) {
  return readReviewed(root, region, "generic-operators.json", "jtm-generic-operators/1", "generics");
}

function readOfficialCodeSchemes(root, region) {
  return readReviewed(root, region, "official-code-schemes.json", "jtm-official-codes/1", "schemes");
}

function readStationFacilities(root, region) {
  const doc = readReviewed(root, region, "station-facilities.json", "jtm-station-facilities/1", "facilities");
  if (doc && !Array.isArray(doc.links)) throw new Error(`bad station-facilities.json ${region}`);
  return doc;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function datedBound(value) {
  if (value == null || value === "") return null;
  const text = String(value);
  return ISO_DATE.test(text) ? text : null;
}

function operationEventKey(event) {
  return [event.id, event.event, event.value ?? "", event.on ?? "", event.why ?? ""].join("\0");
}

function operationPairPrefix(event) {
  return [event.id, event.value ?? "", event.why ?? ""].join("\0");
}

/**
 * A withdrawal cancels the operation object that is live at that point in the
 * ledger. A later operation with the same id, operator, why, and `on` is a new
 * interval and stays live. An operation-end is withdrawn only when its prefix
 * has no live start at the moment the withdrawal is applied.
 */
export function withdrawnOperationPairs(events) {
  const withdrawnEvents = new Set();
  const liveByPrefix = new Map();
  const endsByPrefix = new Map();
  const starts = new Set();
  const prefixes = new Set();
  for (const event of events) {
    if (event.event !== "operation" && event.event !== "operation-end" && event.event !== "operation-withdrawn") continue;
    const prefix = operationPairPrefix(event);
    const on = event.on ?? "";
    if (event.event === "operation") {
      let byOn = liveByPrefix.get(prefix);
      if (!byOn) {
        byOn = new Map();
        liveByPrefix.set(prefix, byOn);
      }
      byOn.set(on, event);
    } else if (event.event === "operation-end") {
      const list = endsByPrefix.get(prefix);
      if (list) list.push(event);
      else endsByPrefix.set(prefix, [event]);
    } else {
      prefixes.add(prefix);
      starts.add(`${prefix}\0${on}`);
      const byOn = liveByPrefix.get(prefix);
      const live = byOn?.get(on);
      if (live) {
        withdrawnEvents.add(live);
        byOn.delete(on);
        if (byOn.size === 0) liveByPrefix.delete(prefix);
      }
      if (!liveByPrefix.has(prefix)) {
        for (const end of endsByPrefix.get(prefix) ?? []) withdrawnEvents.add(end);
        endsByPrefix.delete(prefix);
      }
    }
  }
  return { starts, prefixes, surviving: new Set(liveByPrefix.keys()), events: withdrawnEvents };
}

export function operationEventWithdrawn(event, withdrawn) {
  if (event.event !== "operation" && event.event !== "operation-end") return false;
  if (withdrawn.events) return withdrawn.events.has(event);
  const prefix = operationPairPrefix(event);
  if (event.event === "operation") return withdrawn.starts.has(`${prefix}\0${event.on ?? ""}`);
  if (withdrawn.surviving?.has(prefix)) return false;
  return withdrawn.prefixes.has(prefix);
}

function operationEndEvent(events, operation) {
  const prefix = operationPairPrefix(operation);
  let end = null;
  for (const event of events) {
    if (event.event !== "operation-end" || operationPairPrefix(event) !== prefix) continue;
    end = event;
  }
  return end;
}

function operationIntervalEmpty(operation, end) {
  if (!end) return false;
  const from = String(operation.on ?? "");
  const to = String(end.on ?? "");
  return from !== "" && to !== "" && to <= from;
}

function queueOperationWithdrawal(queued, seenOperation, event, runId) {
  const withdrawn = {
    id: event.id, event: "operation-withdrawn", value: event.value, why: event.why, run: runId,
  };
  if (event.on != null && event.on !== "") withdrawn.on = event.on;
  if (seenOperation.has(operationEventKey(withdrawn))) return;
  seenOperation.add(operationEventKey(withdrawn));
  queued.push(withdrawn);
}

function operationQueueRank(name) {
  if (name === "operation-withdrawn") return 0;
  if (name === "operation") return 1;
  if (name === "operation-end") return 2;
  return 3;
}

function historyCrosswalkEntries(root, region) {
  const doc = readHistoryCrosswalk(root, region);
  if (!doc) return [];
  return [...doc.entries].sort((a, b) => compareText(String(a.history_id ?? ""), String(b.history_id ?? ""))
    || compareText(String(a.kind ?? ""), String(b.kind ?? "")));
}

function historyReportRow(entry, status = null) {
  return {
    history_id: String(entry.history_id ?? ""),
    kind: String(entry.kind ?? ""),
    status: status ?? String(entry.status ?? ""),
    line_name: String(entry.match?.line_name ?? ""),
    operator: String(entry.match?.operator ?? ""),
    lp: Array.isArray(entry.lp) ? [...entry.lp].map(String).sort(compareId) : [],
    op: entry.op ?? null,
  };
}

export function operationIntervalsOverlap(left, right) {
  if ((left.from ?? null) === (right.from ?? null) && (left.to ?? null) === (right.to ?? null)) return false;
  const leftBeforeRightEnd = left.from == null || right.to == null || left.from < right.to;
  const rightBeforeLeftEnd = right.from == null || left.to == null || right.from < left.to;
  return leftBeforeRightEnd && rightBeforeLeftEnd;
}

export function planHistoryCrosswalk(entries) {
  const unresolved = [];
  const undated = [];
  const candidates = [];
  for (const entry of entries) {
    const op = entry.op ? String(entry.op) : "";
    const status = String(entry.status ?? "");
    if (status === "multiple" || status === "unmatched" || !op) {
      unresolved.push(historyReportRow(entry));
      continue;
    }
    if (entry.kind !== "identity_period") continue;
    if (status !== "unique" && status !== "reviewed") continue;
    const validFrom = datedBound(entry.valid_from);
    const validTo = datedBound(entry.valid_to);
    if (!validFrom && !validTo) {
      undated.push(historyReportRow(entry));
      continue;
    }
    const lpIds = Array.isArray(entry.lp) ? entry.lp.map(String) : [];
    if (status === "reviewed" && lpIds.length === 0) {
      unresolved.push(historyReportRow(entry, "unmatched"));
      continue;
    }
    if (status !== "reviewed" && lpIds.length !== 1) {
      unresolved.push(historyReportRow(entry, "multiple"));
      continue;
    }
    for (const lp of lpIds) {
      candidates.push({
        entry, lp, op, validFrom, validTo, interval: { from: validFrom, to: validTo },
      });
    }
  }
  const blocked = new Set();
  for (let i = 0; i < candidates.length; i += 1) {
    for (let j = i + 1; j < candidates.length; j += 1) {
      if (candidates[i].lp !== candidates[j].lp) continue;
      if (operationIntervalsOverlap(candidates[i].interval, candidates[j].interval)) {
        blocked.add(i);
        blocked.add(j);
      }
    }
  }
  const accepted = [];
  const withheld = [];
  for (let i = 0; i < candidates.length; i += 1) {
    if (blocked.has(i)) {
      unresolved.push(historyReportRow(candidates[i].entry, "overlap"));
      withheld.push(candidates[i]);
    } else {
      accepted.push(candidates[i]);
    }
  }
  unresolved.sort((a, b) => compareText(a.history_id, b.history_id) || compareText(a.kind, b.kind) || compareText(a.status, b.status));
  undated.sort((a, b) => compareText(a.history_id, b.history_id) || compareText(a.kind, b.kind));
  withheld.sort((a, b) => compareText(String(a.entry.history_id ?? ""), String(b.entry.history_id ?? "")));
  return { unresolved, undated, accepted, withheld };
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
  const refUniq = new Map();
  const derivByEntity = new Map();
  const keyRefCount = new Map();
  const liveOpsByName = new Map();
  for (const ref of ledger.refs) {
    const parts = String(ref.id).split(":");
    if (parts[1] !== region) continue;
    refIndex.set(`${ref.scheme}\0${ref.value}`, ref.id);
    const uniqKey = `${ref.scheme}\0${ref.value}\0${ref.from ?? ""}`;
    const prior = refUniq.get(uniqKey);
    // A ref re-appended for a new holder after the old holder retired (operator merge) is not a second key.
    const transferred = prior !== undefined && prior !== ref.id && retired.has(prior);
    refUniq.set(uniqKey, ref.id);
    if (DERIV_SCHEME[parts[0]] === ref.scheme && !ref.from && !(parts[0] === "cx" && derivByEntity.has(ref.id))) {
      derivByEntity.set(ref.id, ref.value);
    }
    if (KEY_SCHEME[parts[0]] === ref.scheme && !(parts[0] === "op" && ref.from) && !transferred) {
      keyRefCount.set(ref.id, (keyRefCount.get(ref.id) ?? 0) + 1);
    }
    if (ref.scheme === "package-operator" && parts[0] === "op" && entities.has(ref.id) && !retired.has(ref.id)) {
      let holders = liveOpsByName.get(ref.value);
      if (!holders) {
        holders = new Set();
        liveOpsByName.set(ref.value, holders);
      }
      holders.add(ref.id);
    }
  }
  for (const id of entities.keys()) {
    const parts = String(id).split(":");
    if (parts[1] !== region || !KEY_SCHEME[parts[0]]) continue;
    if (keyRefCount.get(id) !== 1) throw new Error(`ledger incomplete: ${id} key ref`);
  }
  const inputs = { op: new Set(), lp: new Set(), cx: new Set(), st: new Set(), ls: new Set(), rp: new Set(), fc: new Set() };
  const seq = Object.fromEntries(KINDS.map((kind) => [kind, nextSeq(entities, region, kind)]));
  const seenReappeared = new Set();

  const noteReappeared = (entry) => {
    const key = `${entry.id ?? ""}\0${entry.scheme}\0${entry.value}`;
    if (seenReappeared.has(key)) return;
    seenReappeared.add(key);
    additions.reappeared.push(entry);
  };

  const pendingRetire = new Set();
  const addRef = (kind, id, scheme, value, from = null) => {
    const uniq = `${scheme}\0${value}\0${from ?? ""}`;
    const holder = refUniq.get(uniq);
    if (holder !== undefined) {
      const transferable = (scheme === "station-code" || scheme === "group-code") && holder !== id
        && (retired.has(holder) || pendingRetire.has(holder));
      if (!transferable) return false;
    }
    refUniq.set(uniq, id);
    refIndex.set(`${scheme}\0${value}`, id);
    const rec = { id, scheme, value, run: runId };
    if (from) rec.from = from;
    additions.refs.push({ region, kind, rec });
    if (DERIV_SCHEME[kind] === scheme && !from && !(kind === "cx" && derivByEntity.has(id))) derivByEntity.set(id, value);
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

  const renameDoc = readOperatorRenames(root, region);
  if (renameDoc) {
    const renames = [...renameDoc.renames].sort((a, b) => compareId(String(a.op ?? ""), String(b.op ?? ""))
      || compareText(String(a.from ?? ""), String(b.from ?? ""))
      || compareText(String(a.name ?? ""), String(b.name ?? "")));
    for (const rename of renames) {
      const op = String(rename.op ?? "");
      const name = String(rename.name ?? "");
      const from = String(rename.from ?? "");
      const source = String(rename.source ?? "");
      const live = ID_RE.test(op) && op.startsWith(`op:${region}:`) && entities.has(op) && !retired.has(op);
      const holder = refUniq.get(`package-operator\0${name}\0${from}`);
      const heldByOther = [...(liveOpsByName.get(name) ?? [])].some((id) => id !== op);
      if (!live || !name || !/^\d{4}-\d{2}-\d{2}$/.test(from) || (holder && holder !== op) || heldByOther) {
        additions.operatorRenameInvalid.push({ op, name, from, source });
        continue;
      }
      if (addRef("op", op, "package-operator", name, from)) {
        let holders = liveOpsByName.get(name);
        if (!holders) {
          holders = new Set();
          liveOpsByName.set(name, holders);
        }
        holders.add(op);
      }
    }
    additions.operatorRenameInvalid.sort((a, b) => compareText(a.op, b.op) || compareText(a.from, b.from) || compareText(a.name, b.name));
  }

  const aliasSeen = new Set(ledger.aliases.map((alias) => `${alias.old}\0${alias.scheme}\0${alias.id}`));
  const pushAlias = (old, scheme, id) => {
    const key = `${old}\0${scheme}\0${id}`;
    if (aliasSeen.has(key)) return;
    aliasSeen.add(key);
    additions.aliases.push({ region, rec: { old, scheme, id, run: runId } });
  };
  const retireWhy = new Map();
  const liveOp = (id) => ID_RE.test(id) && id.startsWith(`op:${region}:`) && entities.has(id) && !retired.has(id);

  const mergeOf = new Map();
  const mergeDoc = readOperatorMerges(root, region);
  if (mergeDoc) {
    const intoSet = new Set();
    const fromSet = new Set();
    for (const merge of mergeDoc.merges) {
      intoSet.add(String(merge.into ?? ""));
      for (const from of Array.isArray(merge.from) ? merge.from : []) fromSet.add(String(from));
    }
    const merges = [...mergeDoc.merges].sort((a, b) => compareId(String(a.into ?? ""), String(b.into ?? "")));
    for (const merge of merges) {
      const into = String(merge.into ?? "");
      const froms = (Array.isArray(merge.from) ? merge.from.map(String) : []).sort(compareId);
      const problems = [];
      if (!liveOp(into)) problems.push("into not live");
      if (fromSet.has(into)) problems.push("into is also from");
      if (!froms.length) problems.push("no from");
      for (const from of froms) {
        const done = aliasSeen.has(`${from}\0operator-merge\0${into}`);
        if (from === into) problems.push(`from equals into ${from}`);
        else if (intoSet.has(from)) problems.push(`from is also into ${from}`);
        else if (!(liveOp(from) || (done && entities.has(from)))) problems.push(`from not live ${from}`);
        else if (mergeOf.has(from) && mergeOf.get(from) !== into) problems.push(`from merged twice ${from}`);
      }
      if (problems.length) {
        additions.operatorMergeInvalid.push({ into, from: froms, problems });
        continue;
      }
      for (const from of froms) {
        mergeOf.set(from, into);
        const names = ledger.refs.concat(additions.refs.map((item) => item.rec))
          .filter((ref) => ref.id === from && ref.scheme === "package-operator");
        for (const ref of names) {
          const key = `package-operator\0${ref.value}\0${ref.from ?? ""}`;
          if (refUniq.get(key) !== into) {
            const rec = { id: into, scheme: "package-operator", value: ref.value, run: runId };
            if (ref.from) rec.from = ref.from;
            additions.refs.push({ region, kind: "op", rec });
            refUniq.set(key, into);
          }
          refIndex.set(`package-operator\0${ref.value}`, into);
          const holders = liveOpsByName.get(ref.value) ?? new Set();
          holders.delete(from);
          holders.add(into);
          liveOpsByName.set(ref.value, holders);
        }
        if (!retired.has(from)) {
          additions.events.push({
            region,
            rec: { id: from, event: "retire", on: at, why: `merged into ${into}`, run: runId },
          });
          retired.add(from);
        }
        pushAlias(from, "operator-merge", into);
      }
    }
    additions.operatorMergeInvalid.sort((a, b) => compareId(a.into, b.into));
  }

  const lpOverride = new Map();
  const overrideDoc = readLineOperators(root, region);
  if (overrideDoc) {
    for (const item of overrideDoc.lines) {
      const lp = String(item.lp ?? "");
      const op = String(item.op ?? "");
      const lpLive = ID_RE.test(lp) && lp.startsWith(`lp:${region}:`) && entities.has(lp) && !retired.has(lp);
      if (!lpLive || !liveOp(op) || mergeOf.has(op) || (lpOverride.has(lp) && lpOverride.get(lp) !== op)) {
        additions.lineOperatorInvalid.push({ lp, op });
        continue;
      }
      lpOverride.set(lp, op);
    }
    additions.lineOperatorInvalid.sort((a, b) => compareId(a.lp, b.lp));
  }

  const genericSpecifics = new Map();
  const genericDoc = readGenericOperators(root, region);
  if (genericDoc) {
    for (const item of genericDoc.generics) {
      const generic = String(item.generic ?? "");
      const specifics = Array.isArray(item.specifics) ? item.specifics.map(String) : [];
      const bad = !liveOp(generic) || mergeOf.has(generic) || specifics.length === 0
        || specifics.some((op) => !liveOp(op) || mergeOf.has(op) || op === generic)
        || genericSpecifics.has(generic);
      if (bad) {
        additions.genericOperatorInvalid.push({ generic, specifics });
        continue;
      }
      genericSpecifics.set(generic, new Set(specifics));
    }
    additions.genericOperatorInvalid.sort((a, b) => compareId(a.generic, b.generic));
  }

  const operators = db.prepare(
    "SELECT id, name FROM operator WHERE country_code = ? ORDER BY id",
  ).all(country);
  const opByOperatorId = new Map();
  const seenOp = new Set();
  for (const row of operators) {
    const holders = liveOpsByName.get(row.name);
    if (holders && holders.size > 1) {
      additions.operatorNameAmbiguous.push({
        name: row.name,
        ops: [...holders].sort(compareId),
      });
      for (const id of holders) seenOp.add(id);
      continue;
    }
    const id = ensureEntity("op", "package-operator", row.name);
    if (id) {
      opByOperatorId.set(row.id, id);
      seenOp.add(id);
    }
  }
  additions.operatorNameAmbiguous.sort((a, b) => compareText(a.name, b.name) || compareId(a.ops[0] ?? "", b.ops[0] ?? ""));

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

  // An official station code is authoritative identity: complexes sharing one are the same station.
  const complexMerge = new Map();
  const schemeDoc = readOfficialCodeSchemes(root, region);
  const prefixes = (schemeDoc?.schemes ?? []).map((item) => String(item.prefix ?? "")).filter(Boolean);
  if (prefixes.length) {
    const holders = new Map();
    for (const row of codeRows) {
      const sc = row.station_code;
      if (!sc || !prefixes.some((prefix) => String(sc).startsWith(prefix))) continue;
      const cx = cxByCode.get(row.group_code);
      if (!cx) continue;
      if (!holders.has(sc)) holders.set(sc, new Set());
      holders.get(sc).add(cx);
    }
    const parent = new Map();
    const find = (x) => {
      if (!parent.has(x)) parent.set(x, x);
      while (parent.get(x) !== x) x = parent.get(x);
      return x;
    };
    const viaCode = new Map();
    for (const code of [...holders.keys()].sort(compareText)) {
      const set = [...holders.get(code)];
      if (set.length < 2) continue;
      for (const cx of set) if (!viaCode.has(cx)) viaCode.set(cx, code);
      for (const cx of set.slice(1)) parent.set(find(cx), find(set[0]));
    }
    const groups = new Map();
    for (const cx of viaCode.keys()) pushMap(groups, find(cx), cx);
    for (const members of groups.values()) {
      members.sort((a, b) => seqOf(a) - seqOf(b));
      const kept = members[0];
      for (const old of members.slice(1)) {
        if (!retired.has(old)) {
          additions.events.push({
            region,
            rec: { id: old, event: "retire", on: at, why: `merged by official code ${viaCode.get(old)}`, run: runId },
          });
          retired.add(old);
        }
        pushAlias(old, "complex-merge", kept);
        complexMerge.set(old, kept);
        const keys = ledger.refs.concat(additions.refs.map((item) => item.rec))
          .filter((ref) => ref.id === old && ref.scheme === "group-code" && !ref.from)
          .map((ref) => ref.value);
        for (const value of keys) addRef("cx", kept, "group-code", value);
      }
    }
    for (const [code, cx] of cxByCode) {
      if (complexMerge.has(cx)) cxByCode.set(code, complexMerge.get(cx));
    }
  }

  const pairs = db.prepare(`
    SELECT DISTINCT s.code AS code, o.id AS operator_id, o.name AS operator_name, l.id AS line_id
      FROM line_station ls
      JOIN line l ON l.id = ls.line_id
      JOIN station s ON s.id = ls.station_id
      JOIN operator o ON o.id = l.operator_id
     WHERE l.country_code = ?
  `).all(country);
  const stRows = [];
  const stRowSeen = new Set();
  const moveCandidates = [];
  const opsAtCx = new Map();
  if (genericSpecifics.size) {
    for (const row of pairs) {
      const cx = cxByCode.get(row.code);
      const op = lpOverride.get(lpByLineId.get(row.line_id)) ?? opByOperatorId.get(row.operator_id);
      if (!cx || !op) continue;
      if (!opsAtCx.has(cx)) opsAtCx.set(cx, new Set());
      opsAtCx.get(cx).add(op);
    }
  }
  // A generic operator's stop belongs to the one specific operator present in the same complex.
  const genericResolved = (cx, op) => {
    const specifics = genericSpecifics.get(op);
    if (!specifics) return op;
    const present = [...specifics].filter((id) => opsAtCx.get(cx)?.has(id));
    return present.length === 1 ? present[0] : op;
  };
  for (const row of pairs) {
    const cx = cxByCode.get(row.code);
    const baseOp = opByOperatorId.get(row.operator_id);
    const lineOp = lpOverride.get(lpByLineId.get(row.line_id)) ?? baseOp;
    const op = cx && lineOp ? genericResolved(cx, lineOp) : lineOp;
    if (!cx || !op) continue;
    if (op !== baseOp && baseOp) moveCandidates.push({ cx, baseOp, op, generic: op !== lineOp });
    const dedupe = `${cx}|${op}`;
    if (stRowSeen.has(dedupe)) continue;
    stRowSeen.add(dedupe);
    stRows.push({ ...row, cx, op, overridden: op !== baseOp, cxSeq: seqOf(cx), opSeq: seqOf(op) });
  }
  stRows.sort((a, b) => a.cxSeq - b.cxSeq || a.opSeq - b.opSeq || compareText(a.code, b.code));
  const stByCxOp = new Map();
  const overrideStByCx = new Map();
  for (const row of stRows) {
    const value = `${row.cx}|${row.op}`;
    const id = ensureEntity("st", "derivation", value, { parent: row.cx });
    if (!id) continue;
    stByCxOp.set(`${row.cx}|${row.op}`, id);
    if (row.overridden) pushMap(overrideStByCx, row.cx, id);
  }
  // Stations whose derivation is no longer produced retire; moved ones are aliased to their replacement.
  const oldStFor = new Map();
  const noteMove = (newSt, oldSt, scheme) => {
    if (!newSt || !oldSt || newSt === oldSt) return;
    if (!oldStFor.has(newSt)) oldStFor.set(newSt, new Map());
    oldStFor.get(newSt).set(oldSt, scheme);
  };
  const liveSt = (id) => id && entities.has(id) && !retired.has(id);
  for (const [id] of entities) {
    if (!id.startsWith(`st:${region}:`) || retired.has(id)) continue;
    const value = derivByEntity.get(id);
    if (value === undefined || inputs.st.has(value)) continue;
    pendingRetire.add(id);
    const [cx, op] = value.split("|");
    if (complexMerge.has(cx)) {
      const target = stByCxOp.get(`${complexMerge.get(cx)}|${genericResolved(complexMerge.get(cx), mergeOf.get(op) ?? op)}`);
      if (target) retireWhy.set(id, `merged into ${target}`);
      noteMove(target, id, "station-merge");
    } else if (mergeOf.has(op)) {
      const mergedOp = genericResolved(cx, mergeOf.get(op));
      retireWhy.set(id, `merged into ${mergedOp}`);
      noteMove(stByCxOp.get(`${cx}|${mergedOp}`), id, "operator-merge");
    }
  }
  // Stations retired by an earlier run without an alias get one once the replacement resolves.
  const aliasedOld = new Set(ledger.aliases.map((alias) => alias.old));
  for (const [id] of entities) {
    if (!id.startsWith(`st:${region}:`) || !retired.has(id) || aliasedOld.has(id)) continue;
    const [cx, op] = (derivByEntity.get(id) ?? "").split("|");
    if (!cx || !mergeOf.has(op)) continue;
    const target = stByCxOp.get(`${cx}|${genericResolved(cx, mergeOf.get(op))}`);
    if (liveSt(target)) pushAlias(id, "operator-merge", target);
  }
  for (const item of moveCandidates) {
    const oldSt = refIndex.get(`derivation\0${item.cx}|${item.baseOp}`);
    if (!liveSt(oldSt)) continue;
    if (pendingRetire.has(oldSt)) retireWhy.set(oldSt, item.generic ? "generic parent attached to specific" : "line operator override");
    noteMove(stByCxOp.get(`${item.cx}|${item.op}`), oldSt, item.generic ? "generic-operator" : "line-operator");
  }
  for (const [newSt, olds] of oldStFor) {
    // A station still used by other lines stays live and unaliased; only its stops move.
    for (const [oldSt, scheme] of olds) if (pendingRetire.has(oldSt)) pushAlias(oldSt, scheme, newSt);
  }
  const opIdByName = new Map(operators.map((row) => [row.name, row.id]));
  const stationCodeRows = [];
  for (const row of codeRows) {
    if (!row.station_code) continue;
    const operatorId = opIdByName.get(row.operator);
    const baseOp = operatorId == null ? null : opByOperatorId.get(operatorId);
    const cx = cxByCode.get(row.group_code);
    const op = baseOp && cx ? genericResolved(cx, baseOp) : baseOp;
    const stId = op && cx ? stByCxOp.get(`${cx}|${op}`) ?? null : null;
    const overridden = !stId && cx ? overrideStByCx.get(cx) : null;
    stationCodeRows.push({
      code: row.station_code,
      operator: stId || !overridden || overridden.length !== 1 ? (op ?? row.operator) : "override",
      stId: stId ?? (overridden?.length === 1 ? overridden[0] : null),
    });
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
    const lineOp = lpOverride.get(lp) ?? opByOperatorId.get(row.operator_id);
    const op = cx && lineOp ? genericResolved(cx, lineOp) : lineOp;
    if (!lp || !cx || !op) continue;
    if (retired.has(lp) || retired.has(cx) || retired.has(op)) continue;
    const stId = stByCxOp.get(`${cx}|${op}`);
    if (!stId || retired.has(stId)) continue;
    const lsId = ensureEntity("ls", "derivation", `${lp}|${stId}`, { parent: stId, part: lp });
    for (const [oldSt, scheme] of oldStFor.get(stId) ?? []) {
      const oldLs = refIndex.get(`derivation\0${lp}|${oldSt}`);
      if (!lsId || !oldLs || oldLs === lsId || !entities.has(oldLs) || retired.has(oldLs)) continue;
      retireWhy.set(oldLs, scheme === "operator-merge" || scheme === "station-merge" ? `merged into ${stId}` : scheme === "generic-operator" ? "generic parent attached to specific" : "line operator override");
      pushAlias(oldLs, scheme, lsId);
    }
  }

  const patternDoc = readRoutePatterns(root, region);
  if (patternDoc) {
    const memberSeen = new Set();
    for (const event of ledger.events) {
      if (event.event === "member") memberSeen.add(`${event.id}\0${event.value}`);
    }
    const patterns = [...patternDoc.patterns].sort((a, b) => compareText(String(a.slug ?? ""), String(b.slug ?? ""))
      || compareText(crosswalkKey(a.lp), crosswalkKey(b.lp)));
    for (const pattern of patterns) {
      const lpIds = Array.isArray(pattern.lp) ? pattern.lp.map(String).sort(compareId) : [];
      if (!lpIds.length) continue;
      const ready = lpIds.every((lpId) => lpId.startsWith(`lp:${region}:`) && entities.has(lpId) && !retired.has(lpId));
      if (!ready) continue;
      const value = lpIds.join(",");
      const existing = refIndex.get(`route-pattern\0${value}`) ?? null;
      const id = ensureEntity("rp", "route-pattern", value);
      if (!id) continue;
      if (!existing) {
        const created = additions.entities.find((item) => item.rec.id === id);
        if (created && pattern.slug) {
          created.rec.slug = String(pattern.slug);
          entities.set(id, created.rec);
        }
      }
      for (const lpId of lpIds) {
        const key = `${id}\0${lpId}`;
        if (memberSeen.has(key)) continue;
        memberSeen.add(key);
        additions.events.push({ region, rec: { id, event: "member", value: lpId, run: runId } });
      }
    }
  }

  const facilityDoc = readStationFacilities(root, region);
  if (facilityDoc) {
    const seenEvent = new Set();
    const remember = (rec) => {
      if (rec.event === "facility" || rec.event === "manager" || rec.event === "link") {
        seenEvent.add(`${rec.event}\0${rec.id}\0${rec.value ?? ""}`);
      }
    };
    for (const event of ledger.events) remember(event);
    for (const item of additions.events) remember(item.rec);
    const pushEvent = (rec) => {
      const key = `${rec.event}\0${rec.id}\0${rec.value ?? ""}`;
      if (seenEvent.has(key)) return;
      seenEvent.add(key);
      additions.events.push({ region, rec });
    };
    const facilities = [...facilityDoc.facilities].sort((a, b) => compareId(String(a.cx ?? ""), String(b.cx ?? ""))
      || compareText([...(a.stations ?? [])].map(String).sort(compareId).join(","), [...(b.stations ?? [])].map(String).sort(compareId).join(",")));
    for (const facility of facilities) {
      const cx = String(facility.cx ?? "");
      const stations = Array.isArray(facility.stations) ? facility.stations.map(String).sort(compareId) : [];
      const kind = facility.kind === "boundary" ? "boundary" : "shared";
      if (!cx.startsWith(`cx:${region}:`) || !stations.length) continue;
      const value = `${cx}|${stations.join(",")}`;
      const existing = refIndex.get(`facility\0${value}`) ?? null;
      const id = ensureEntity("fc", "facility", value, { parent: cx });
      if (!id) continue;
      if (!existing) {
        const created = additions.entities.find((item) => item.rec.id === id);
        if (created) {
          created.rec.slug = kind;
          entities.set(id, created.rec);
        }
      }
      for (const stId of stations) pushEvent({ id: stId, event: "facility", value: id, run: runId });
      const manager = String(facility.manager ?? "");
      if (manager) pushEvent({ id, event: "manager", value: manager, run: runId });
    }
    const linkRows = [...facilityDoc.links].sort((a, b) => compareId(String(a.a ?? ""), String(b.a ?? ""))
      || compareId(String(a.b ?? ""), String(b.b ?? "")));
    for (const link of linkRows) {
      let left = String(link.a ?? "");
      let right = String(link.b ?? "");
      if (!left || !right || compareId(left, right) === 0) continue;
      if (compareId(left, right) > 0) [left, right] = [right, left];
      const why = link.kind === "street_transfer" ? "street_transfer" : "gate_transfer";
      pushEvent({ id: left, event: "link", value: right, why, run: runId });
    }
  }

  const retireIds = [];
  for (const id of entities.keys()) {
    const match = ID_RE.exec(id);
    if (!match || match[2] !== region || !KINDS.includes(match[1])) continue;
    if (retired.has(id)) continue;
    if (match[1] === "op") {
      if (!seenOp.has(id)) retireIds.push(id);
      continue;
    }
    const value = derivByEntity.get(id);
    if (value === undefined) continue;
    if (!inputs[match[1]].has(value)) retireIds.push(id);
  }
  retireIds.sort(compareId);
  for (const id of retireIds) {
    additions.events.push({
      region,
      rec: { id, event: "retire", on: at, why: retireWhy.get(id) ?? "absent from inputs", run: runId },
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

  const seenOperation = new Set();
  const operationEvents = new Set(["operation", "operation-end", "operation-withdrawn"]);
  for (const event of ledger.events) {
    if (operationEvents.has(event.event)) seenOperation.add(operationEventKey(event));
  }
  for (const item of additions.events) {
    if (operationEvents.has(item.rec.event)) seenOperation.add(operationEventKey(item.rec));
  }
  const queued = [];
  const opState = new Map();
  const ledgerWithdrawn = withdrawnOperationPairs(ledger.events);
  for (const event of [...ledger.events, ...additions.events.map((item) => item.rec)]) {
    if (event.event !== "operation" && event.event !== "operation-withdrawn") continue;
    opState.set([event.id, event.value ?? "", event.on ?? "", event.why ?? ""].join("\0"), event.event === "operation" ? "live" : "withdrawn");
  }
  const historyPlan = planHistoryCrosswalk(historyCrosswalkEntries(root, region));
  for (const planned of historyPlan.accepted) {
    const { lp, op, validFrom, validTo } = planned;
    if (!entities.has(lp) || retired.has(lp) || !entities.has(op) || retired.has(op)) continue;
    const why = String(planned.entry.history_id ?? "");
    const newOn = validFrom ?? "";
    const stateKey = (id, v, on, w) => [id, v ?? "", on ?? "", w ?? ""].join("\0");
    for (const event of ledger.events) {
      if (event.event !== "operation" || event.id !== lp || (event.value ?? "") !== op || (event.why ?? "") !== why) continue;
      const sameOn = (event.on ?? "") === newOn;
      const end = operationEndEvent(ledger.events, event);
      const empty = operationIntervalEmpty(event, end) && !operationEventWithdrawn(end, ledgerWithdrawn);
      if (sameOn && !empty) continue;
      if (opState.get(stateKey(lp, op, event.on, why)) !== "live") continue;
      queueOperationWithdrawal(queued, new Set(), { id: lp, value: op, why, on: event.on }, runId);
      opState.set(stateKey(lp, op, event.on, why), "withdrawn");
      if (validTo && end) seenOperation.delete(operationEventKey(end));
    }
    const start = { id: lp, event: "operation", value: op, why, run: runId };
    if (validFrom) start.on = validFrom;
    let startAppended = false;
    if (opState.get(stateKey(lp, op, validFrom, why)) !== "live") {
      opState.set(stateKey(lp, op, validFrom, why), "live");
      queued.push(start);
      startAppended = true;
    }
    const pair = [];
    if (validTo) pair.push({ id: lp, event: "operation-end", value: op, on: validTo, why, run: runId });
    for (const rec of pair) {
      if (!startAppended && seenOperation.has(operationEventKey(rec))) continue;
      seenOperation.add(operationEventKey(rec));
      queued.push(rec);
    }
  }
  for (const planned of historyPlan.withheld) {
    const why = String(planned.entry.history_id ?? "");
    const prior = ledger.events.filter((event) => event.event === "operation"
      && event.id === planned.lp && (event.value ?? "") === planned.op && (event.why ?? "") === why);
    for (const event of prior) {
      const key = [event.id, event.value ?? "", event.on ?? "", event.why ?? ""].join("\0");
      if (opState.get(key) !== "live") continue;
      opState.set(key, "withdrawn");
      queueOperationWithdrawal(queued, new Set(), event, runId);
    }
  }
  queued.sort((a, b) => compareText(a.why ?? "", b.why ?? "")
    || (operationQueueRank(a.event) - operationQueueRank(b.event))
    || compareId(a.id, b.id));
  for (const rec of queued) additions.events.push({ region, rec });
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

function unsplitBracketNames(facts) {
  const rows = [];
  const seen = new Set();
  const push = (row) => {
    const key = [row.source, row.name, row.code ?? "", row.line ?? ""].join("\0");
    if (seen.has(key)) return;
    seen.add(key);
    rows.push(row);
  };
  for (const station of facts.stations) {
    if (!containsBracketChar(station.name) || splitBracketName(station.name)) continue;
    push({ source: "station", name: station.name, code: station.code });
  }
  for (const stop of facts.stops) {
    if (!containsBracketChar(stop.name) || splitBracketName(stop.name)) continue;
    push({ source: "line_station", name: stop.name, code: stop.code, line: stop.line_id });
  }
  rows.sort((a, b) => compareText(a.source, b.source)
    || compareText(a.name, b.name)
    || compareText(a.code ?? "", b.code ?? "")
    || compareText(a.line ?? "", b.line ?? ""));
  return rows;
}

function qualifiedLabel(operatorName, shortName, lineName) {
  return `${shortName || operatorName}${lineName}`;
}

function lineLabel(line, nameCounts) {
  if ((nameCounts.get(line.name) ?? 0) > 1) return qualifiedLabel(line.operator_name, line.short_name, line.name);
  return line.name;
}

export function reports(db, ledger, region, root, resolvedConflicts = null) {
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
  const historyPlan = planHistoryCrosswalk(historyCrosswalkEntries(root, region));
  out["history-unresolved"] = historyPlan.unresolved;
  out["history-period-undated"] = historyPlan.undated;

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
  // Minted conflicts already reflect merges, line overrides, generic attachment and complex resolution.
  out["station-code-conflict"] = resolvedConflicts
    ? resolvedConflicts.map(({ value, candidates }) => ({ value, candidates }))
    : planStationCodes(stationCodeRows).conflicts;

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
  out["operator-rename-invalid"] = operatorRenameRows(root, region, ledger, index);
  out["bracket-name-unsplit"] = unsplitBracketNames(facts);

  const ordered = {};
  for (const rule of REPORT_RULES) ordered[rule] = out[rule];
  return ordered;
}

function operatorRenameRows(root, region, ledger, index) {
  const doc = readOperatorRenames(root, region);
  if (!doc) return [];
  const rows = [];
  for (const rename of doc.renames) {
    const op = String(rename.op ?? "");
    const name = String(rename.name ?? "");
    const from = String(rename.from ?? "");
    const source = String(rename.source ?? "");
    const live = ID_RE.test(op) && op.startsWith(`op:${region}:`) && ledger.entities.has(op) && !index.retired.has(op);
    const holder = ledger.refs.find((ref) => ref.scheme === "package-operator"
      && ref.value === name
      && (ref.from ?? "") === from
      && String(ref.id).startsWith(`op:${region}:`));
    const heldByOther = ledger.refs.some((ref) => ref.scheme === "package-operator"
      && ref.value === name
      && ref.id !== op
      && String(ref.id).startsWith(`op:${region}:`)
      && ledger.entities.has(ref.id)
      && !index.retired.has(ref.id));
    if (!live || !name || !/^\d{4}-\d{2}-\d{2}$/.test(from) || (holder && holder.id !== op) || heldByOther) {
      rows.push({ op, name, from, source });
    }
  }
  rows.sort((a, b) => compareText(a.op, b.op) || compareText(a.from, b.from) || compareText(a.name, b.name) || compareText(a.source, b.source));
  return rows;
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
  fillStationFacilities(db, ledger, root, tally);
  fillLineOperation(db, ledger, tally);
  fillNames(db, ledger, tally);
  return counts;
}

function facilityReviewIndex(root) {
  const byFacility = new Map();
  const byLink = new Map();
  for (const region of REGIONS) {
    const file = path.join(root, region, "station-facilities.json");
    if (!fs.existsSync(file)) continue;
    const doc = JSON.parse(fs.readFileSync(file, "utf8"));
    for (const facility of doc.facilities ?? []) {
      const stations = [...(facility.stations ?? [])].map(String).sort(compareId);
      byFacility.set(`${facility.cx}|${stations.join(",")}`, (facility.sources ?? []).join(" "));
    }
    for (const link of doc.links ?? []) {
      const pair = [String(link.a), String(link.b)].sort(compareId);
      byLink.set(pair.join("\0"), (link.sources ?? []).join(" "));
    }
  }
  return { byFacility, byLink };
}

function fillStationFacilities(db, ledger, root, tally) {
  if (!hasTable(db, "station_facility") || !hasTable(db, "station_facility_member") || !hasTable(db, "station_link")) return;
  const retired = new Set();
  for (const event of ledger.events) {
    if (event.event === "retire") retired.add(event.id);
  }
  const live = (id) => ledger.entities.has(id) && !retired.has(id);
  const review = facilityReviewIndex(root);
  const facilityValue = new Map();
  for (const ref of ledger.refs) {
    if (ref.scheme === "facility") facilityValue.set(ref.id, ref.value);
  }
  const members = new Map();
  const managers = new Map();
  for (const event of ledger.events) {
    if (event.event === "facility" && live(event.value) && live(event.id)) {
      if (!members.has(event.value)) members.set(event.value, []);
      if (!members.get(event.value).includes(event.id)) members.get(event.value).push(event.id);
    } else if (event.event === "manager" && live(event.id) && live(event.value)) {
      managers.set(event.id, event.value);
    }
  }
  const insertFacility = db.prepare(`
    INSERT INTO station_facility (id, complex_id, manager_operator_id, kind, source)
    VALUES (?, ?, ?, ?, ?)
  `);
  const insertMember = db.prepare(`
    INSERT INTO station_facility_member (facility_id, station_id) VALUES (?, ?)
  `);
  const insertManager = db.prepare(`
    INSERT INTO station_operator (station_id, operator_id, role, valid_from, valid_to)
    VALUES (?, ?, 'manager', NULL, NULL)
  `);
  const facilityIds = [...ledger.entities.values()]
    .map((entity) => entity.id)
    .filter((id) => id.startsWith("fc:") && live(id))
    .sort(compareId);
  for (const id of facilityIds) {
    const entity = ledger.entities.get(id);
    const kind = entity.slug === "boundary" ? "boundary" : "shared";
    const value = facilityValue.get(id) ?? "";
    const source = review.byFacility.get(value) ?? null;
    const manager = managers.get(id) ?? null;
    insertFacility.run(id, textOrNull(entity.parent), manager, kind, source || null);
    tally("station_facility");
    const stationIds = (members.get(id) ?? []).sort(compareId);
    for (const stationId of stationIds) {
      if (!live(stationId)) continue;
      insertMember.run(id, stationId);
      tally("station_facility_member");
      if (manager) {
        insertManager.run(stationId, manager);
        tally("station_operator");
      }
    }
  }
  const insertLink = db.prepare(`
    INSERT INTO station_link (a_station_id, b_station_id, kind, source) VALUES (?, ?, ?, ?)
  `);
  const seenLink = new Set();
  const linkRows = [];
  for (const event of ledger.events) {
    if (event.event !== "link" || !live(event.id) || !live(event.value)) continue;
    const pair = [event.id, event.value].sort(compareId);
    const key = pair.join("\0");
    if (seenLink.has(key)) continue;
    seenLink.add(key);
    linkRows.push({
      a: pair[0],
      b: pair[1],
      kind: event.why === "street_transfer" ? "street_transfer" : "gate_transfer",
      source: review.byLink.get(key) ?? null,
    });
  }
  linkRows.sort((a, b) => compareId(a.a, b.a) || compareId(a.b, b.b) || compareText(a.kind, b.kind));
  for (const row of linkRows) {
    insertLink.run(row.a, row.b, row.kind, row.source || null);
    tally("station_link");
  }
}

/**
 * Dated rows for live, non-withdrawn operation pairs. An undated current
 * operator is kept only when that lp has no dated rows. Otherwise it starts
 * at the latest operation-end when the current operator differs, or it is
 * omitted (and listed) when that bound cannot be derived.
 */
export function planLineOperationRows(ledger, currents) {
  const retired = new Set();
  for (const event of ledger.events) {
    if (event.event === "retire") retired.add(event.id);
  }
  const live = (id) => ledger.entities.has(id) && !retired.has(id);
  const lnByLp = new Map();
  for (const event of ledger.events) {
    if (event.event === "line" && event.value && ledger.entities.has(event.value)) lnByLp.set(event.id, event.value);
  }
  const lineIdOf = (lp) => lnByLp.get(lp) ?? lp;
  const withdrawn = withdrawnOperationPairs(ledger.events);
  const endByKey = new Map();
  for (const event of ledger.events) {
    if (event.event !== "operation-end" || operationEventWithdrawn(event, withdrawn)) continue;
    endByKey.set(operationPairPrefix(event), event.on ?? null);
  }
  const seenPair = new Set();
  const rows = [];
  for (const event of ledger.events) {
    if (event.event !== "operation" || operationEventWithdrawn(event, withdrawn)) continue;
    if (!live(event.id) || !live(event.value)) continue;
    const key = operationPairPrefix(event);
    if (seenPair.has(key)) continue;
    seenPair.add(key);
    const lineId = lineIdOf(event.id);
    if (!ledger.entities.has(lineId)) continue;
    const row = {
      lp: event.id,
      lineId,
      operatorId: event.value,
      role: "operator",
      validFrom: event.on ?? null,
      validTo: endByKey.has(key) ? endByKey.get(key) : null,
    };
    rows.push(row);
  }
  // Currents are bounded per line id. Grouped package lines share one ln, so a
  // sibling's undated current must not sit on top of another part's closed interval.
  const omitted = [];
  const datedByLine = new Map();
  for (const row of rows) {
    if (!datedByLine.has(row.lineId)) datedByLine.set(row.lineId, []);
    datedByLine.get(row.lineId).push(row);
  }
  const currentsByLine = new Map();
  for (const current of currents) {
    if (!currentsByLine.has(current.lineId)) currentsByLine.set(current.lineId, []);
    currentsByLine.get(current.lineId).push(current);
  }
  for (const lineId of [...currentsByLine.keys()].sort(compareId)) {
    const members = currentsByLine.get(lineId).slice().sort((a, b) => compareId(a.lp, b.lp));
    const operators = [...new Set(members.map((member) => member.operatorId))].sort(compareId);
    if (operators.length !== 1) {
      for (const member of members) omitted.push(member.lp);
      continue;
    }
    const bound = boundCurrentOperator(datedByLine.get(lineId) ?? [], operators[0]);
    if (bound.omit) {
      for (const member of members) omitted.push(member.lp);
      continue;
    }
    if (!bound.row) continue;
    rows.push({
      lp: members[0].lp,
      lineId,
      operatorId: operators[0],
      role: "operator",
      validFrom: bound.row.validFrom,
      validTo: bound.row.validTo,
    });
  }
  omitted.sort(compareId);
  return { rows, omitted };
}

function boundCurrentOperator(dated, operatorId) {
  if (!dated.length) return { row: { validFrom: null, validTo: null } };
  const open = dated.filter((row) => row.validTo == null || row.validTo === "");
  if (open.length) {
    const operators = new Set(open.map((row) => row.operatorId));
    if (operators.size === 1 && operators.has(operatorId)) return { row: null };
    return { omit: true };
  }
  const latest = dated.map((row) => row.validTo).filter(Boolean).sort(compareText).at(-1);
  if (!latest) return { omit: true };
  const atLatest = dated.filter((row) => row.validTo === latest);
  const operators = new Set(atLatest.map((row) => row.operatorId));
  if (operators.size !== 1) return { omit: true };
  if (operators.has(operatorId)) return { row: null };
  return { row: { validFrom: latest, validTo: null } };
}

function fillLineOperation(db, ledger, tally) {
  if (!hasTable(db, "line") || !hasTable(db, "operator")) return;
  const retired = new Set();
  for (const event of ledger.events) {
    if (event.event === "retire") retired.add(event.id);
  }
  const live = (id) => ledger.entities.has(id) && !retired.has(id);
  const lnByLp = new Map();
  for (const event of ledger.events) {
    if (event.event === "line" && event.value && ledger.entities.has(event.value)) lnByLp.set(event.id, event.value);
  }
  const lineIdOf = (lp) => lnByLp.get(lp) ?? lp;
  const operatorByLine = new Map();
  for (const row of db.prepare(`
    SELECT l.id AS id, o.name AS operator_name
      FROM line l
      JOIN operator o ON o.id = l.operator_id
  `).all()) {
    operatorByLine.set(row.id, row.operator_name);
  }
  const opsByName = new Map();
  const packageLineOfLp = new Map();
  for (const ref of ledger.refs) {
    if (!live(ref.id)) continue;
    if (ref.scheme === "package-operator" && String(ref.id).startsWith("op:")) {
      if (!opsByName.has(ref.value)) opsByName.set(ref.value, new Set());
      opsByName.get(ref.value).add(ref.id);
    }
    if (ref.scheme === "package-line" && String(ref.id).startsWith("lp:") && !ref.from) {
      packageLineOfLp.set(ref.id, ref.value);
    }
  }
  const currents = [];
  for (const entity of ledger.entities.values()) {
    if (!String(entity.id).startsWith("lp:") || !live(entity.id)) continue;
    const packageId = packageLineOfLp.get(entity.id);
    const operatorName = packageId ? operatorByLine.get(packageId) : null;
    if (!operatorName) continue;
    const ops = [...(opsByName.get(operatorName) ?? [])].sort(compareId);
    if (ops.length !== 1) continue;
    const lineId = lineIdOf(entity.id);
    if (!ledger.entities.has(lineId) || !live(ops[0])) continue;
    currents.push({ lp: entity.id, lineId, operatorId: ops[0] });
  }
  currents.sort((a, b) => compareId(a.lp, b.lp));
  const planned = planLineOperationRows(ledger, currents);
  for (const lp of planned.omitted) console.log(`line_operation omitted ${lp}`);
  const rows = planned.rows;
  rows.sort((a, b) => compareId(a.lineId, b.lineId)
    || compareId(a.operatorId, b.operatorId)
    || compareText(a.validFrom ?? "", b.validFrom ?? "")
    || compareText(a.validTo ?? "", b.validTo ?? ""));
  const seenRow = new Set();
  const uniqueRows = [];
  for (const row of rows) {
    const key = [row.lineId, row.operatorId, row.role, row.validFrom ?? "", row.validTo ?? ""].join("\0");
    if (seenRow.has(key)) continue;
    seenRow.add(key);
    uniqueRows.push(row);
  }
  const insert = db.prepare(`
    INSERT INTO line_operation (line_id, operator_id, role, valid_from, valid_to)
    VALUES (?, ?, ?, ?, ?)
  `);
  for (const row of uniqueRows) {
    insert.run(row.lineId, row.operatorId, row.role, row.validFrom, row.validTo);
    tally("line_operation");
  }
}

function officialLang(region) {
  if (region === "jp") return "ja";
  if (region === "kr") return "ko";
  return "zh-Hant";
}

function fieldName(field, bcp47) {
  if (field === "kana" || field === "katakana") return { lang: bcp47 || "ja", form: "kana" };
  if (field === "romaji") return { lang: bcp47 || "en", form: "romaji" };
  if (field === "en") return { lang: "en", form: "official" };
  if (field === "zh_Hant") return { lang: bcp47 || "zh-Hant", form: "official" };
  if (field === "zh_Hans") return { lang: bcp47 || "zh-Hans", form: "official" };
  if (bcp47) return { lang: bcp47, form: "official" };
  return null;
}

function rememberLookup(map, key, id) {
  if (!map.has(key)) map.set(key, id);
  else if (map.get(key) !== id) map.set(key, null);
}

function fillNames(db, ledger, tally) {
  if (!hasTable(db, "name")) return;
  const retired = new Set();
  for (const event of ledger.events) {
    if (event.event === "retire") retired.add(event.id);
  }
  const live = (id) => ledger.entities.has(id) && !retired.has(id);
  const opByName = new Map();
  const lpByLine = new Map();
  const cxByGroup = new Map();
  const stByCode = new Map();
  const stByDeriv = new Map();
  for (const ref of ledger.refs) {
    if (!live(ref.id)) continue;
    const region = String(ref.id).split(":")[1];
    if (ref.scheme === "package-operator") rememberLookup(opByName, `${region}\0${ref.value}`, ref.id);
    else if (ref.scheme === "package-line") rememberLookup(lpByLine, `${region}\0${ref.value}`, ref.id);
    else if (ref.scheme === "group-code") rememberLookup(cxByGroup, `${region}\0${ref.value}`, ref.id);
    else if (ref.scheme === "station-code") rememberLookup(stByCode, `${region}\0${ref.value}`, ref.id);
    else if (ref.scheme === "derivation" && String(ref.id).startsWith("st:")) rememberLookup(stByDeriv, ref.value, ref.id);
  }
  const rows = [];
  const seen = new Set();
  const push = (entityId, region, lang, form, value, source, status = null) => {
    if (!entityId || !live(entityId) || value === null || value === undefined || value === "") return;
    const text = String(value);
    const key = [entityId, region, lang, form, text, source, status ?? ""].join("\0");
    if (seen.has(key)) return;
    seen.add(key);
    rows.push({ entityId, region, lang, form, value: text, source, status });
  };
  const pushBracket = (entityId, region, lang, official, source) => {
    for (const row of bracketNameRows(official)) {
      push(entityId, region, lang, row.form, row.value, source, row.status);
    }
  };
  if (hasTable(db, "operator")) {
    for (const row of db.prepare("SELECT country_code, name, short_name FROM operator").all()) {
      const region = String(row.country_code).toLowerCase();
      if (!REGIONS.includes(region)) continue;
      const op = opByName.get(`${region}\0${row.name}`);
      if (!op) continue;
      const lang = officialLang(region);
      push(op, region, lang, "official", row.name, "operator.name");
      push(op, region, lang, "short", row.short_name, "operator.short_name");
    }
  }
  if (hasTable(db, "line")) {
    for (const row of db.prepare("SELECT id, country_code, name, name_roma, line_code FROM line").all()) {
      const region = String(row.country_code).toLowerCase();
      if (!REGIONS.includes(region)) continue;
      const lp = lpByLine.get(`${region}\0${row.id}`);
      if (!lp) continue;
      push(lp, region, officialLang(region), "official", row.name, "line.name");
      push(lp, region, "en", "romaji", row.name_roma, "line.name_roma");
      push(lp, region, "und", "alias", row.line_code, "line.line_code");
    }
  }
  if (hasTable(db, "station")) {
    for (const row of db.prepare("SELECT country_code, code, name, name_roma FROM station").all()) {
      const region = String(row.country_code).toLowerCase();
      if (!REGIONS.includes(region)) continue;
      const cx = cxByGroup.get(`${region}\0${row.code}`);
      if (!cx) continue;
      push(cx, region, officialLang(region), "official", row.name, "station.name");
      pushBracket(cx, region, officialLang(region), row.name, "station.name");
      push(cx, region, "en", "romaji", row.name_roma, "station.name_roma");
    }
  }
  if (hasTable(db, "station_english") && hasTable(db, "station")) {
    const english = db.prepare(`
      SELECT s.country_code AS country_code, s.code AS code, e.en AS en, e.status AS status
        FROM station_english e
        JOIN station s ON s.id = e.station_id
    `).all();
    for (const row of english) {
      const region = String(row.country_code).toLowerCase();
      const cx = cxByGroup.get(`${region}\0${row.code}`);
      if (!cx) continue;
      push(cx, region, "en", "official", row.en, "station_english.en", row.status ?? null);
    }
  }
  if (hasTable(db, "station_name")) {
    const bcp47 = new Map();
    if (hasTable(db, "name_field")) {
      for (const row of db.prepare("SELECT field, bcp47 FROM name_field").all()) bcp47.set(row.field, row.bcp47 ?? null);
    }
    for (const row of db.prepare("SELECT country_code, key, field, value FROM station_name WHERE key_type = 'code'").all()) {
      const region = String(row.country_code).toLowerCase();
      if (!REGIONS.includes(region)) continue;
      const mapped = fieldName(row.field, bcp47.get(row.field) ?? null);
      if (!mapped) continue;
      let cx = cxByGroup.get(`${region}\0${row.key}`);
      if (!cx) {
        const st = stByCode.get(`${region}\0${row.key}`);
        const parent = st ? ledger.entities.get(st)?.parent : null;
        if (parent && live(parent)) cx = parent;
      }
      if (!cx) continue;
      push(cx, region, mapped.lang, mapped.form, row.value, "station_name.value");
    }
  }
  if (hasTable(db, "line_station") && hasTable(db, "station") && hasTable(db, "line") && hasTable(db, "operator")) {
    const stops = db.prepare(`
      SELECT lower(l.country_code) AS region, s.code AS code, s.name AS cx_name,
             o.name AS operator_name, ls.name AS stop_name
        FROM line_station ls
        JOIN station s ON s.id = ls.station_id
        JOIN line l ON l.id = ls.line_id
        JOIN operator o ON o.id = l.operator_id
       WHERE ls.name <> s.name
    `).all();
    for (const row of stops) {
      if (!REGIONS.includes(row.region)) continue;
      const op = opByName.get(`${row.region}\0${row.operator_name}`);
      const cx = cxByGroup.get(`${row.region}\0${row.code}`);
      if (!op || !cx) continue;
      const st = stByDeriv.get(`${cx}|${op}`);
      if (!st || row.stop_name === row.cx_name) continue;
      push(st, row.region, officialLang(row.region), "official", row.stop_name, "line_station.name");
      pushBracket(st, row.region, officialLang(row.region), row.stop_name, "line_station.name");
    }
  }
  rows.sort((a, b) => compareId(a.entityId, b.entityId)
    || compareText(a.source, b.source)
    || compareText(a.lang, b.lang)
    || compareText(a.form, b.form)
    || compareText(a.value, b.value)
    || compareText(a.status ?? "", b.status ?? ""));
  const insert = db.prepare(`
    INSERT INTO name (entity_id, region, lang, form, value, valid_from, valid_to, source, status)
    VALUES (?, ?, ?, ?, ?, NULL, NULL, ?, ?)
  `);
  for (const row of rows) {
    insert.run(row.entityId, row.region, row.lang, row.form, row.value, row.source, row.status);
    tally("name");
  }
}
