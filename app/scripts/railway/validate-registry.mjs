#!/usr/bin/env node
// P0 checks for the identity ledger: canonical lines, references, coverage, append-only history.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";

import { ID_RE, REGIONS, classifyLedgerName, compareId, operationEventWithdrawn, operationIntervalsOverlap, parseLedger, withdrawnOperationPairs } from "../build/rail-database/registry.mjs";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

function parseArgs(argv) {
  const options = {
    root: path.resolve("data/registry"),
    db: path.resolve("data/rail.db"),
    base: null,
    noBase: false,
    freeze: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--root") options.root = path.resolve(argv[++index]);
    else if (argument === "--db") options.db = path.resolve(argv[++index]);
    else if (argument === "--base") options.base = argv[++index];
    else if (argument === "--no-base") options.noBase = true;
    else if (argument === "--freeze") options.freeze = true;
    else throw new Error(`unknown option: ${argument}`);
  }
  return options;
}

function kindOf(id) {
  return String(id).split(":")[0];
}

function regionOf(id) {
  return String(id).split(":")[1];
}

const KEY_SCHEME = {
  op: "package-operator",
  lp: "package-line",
  cx: "group-code",
  st: "derivation",
  ls: "derivation",
  ln: "crosswalk",
  rp: "route-pattern",
  fc: "facility",
};

function pushMap(map, key, value) {
  const list = map.get(key);
  if (list) list.push(value);
  else map.set(key, [value]);
}

function referenceViolations(ledger) {
  const violations = [];
  const retired = new Map();
  const retiredIds = new Set(ledger.events.filter((event) => event.event === "retire").map((event) => event.id));
  const refSeen = new Map();
  const transferredRefs = new Set();
  for (const ref of ledger.refs) {
    if (!ledger.entities.has(ref.id)) violations.push(`ref target missing ${ref.id}`);
    const key = `${regionOf(ref.id)}\0${ref.scheme}\0${ref.value}\0${ref.from ?? ""}`;
    // An operator merge / line-operator move re-appends a ref for the new holder once the old holder retired.
    if (refSeen.has(key) && !(refSeen.get(key) !== ref.id && retiredIds.has(refSeen.get(key)))) {
      violations.push(`duplicate ref ${ref.scheme} ${ref.value}`);
    } else if (refSeen.has(key)) transferredRefs.add(ref);
    refSeen.set(key, ref.id);
  }
  for (const entity of ledger.entities.values()) {
    const kind = kindOf(entity.id);
    if (entity.parent && !ledger.entities.has(entity.parent)) violations.push(`orphan parent ${entity.id}`);
    if (entity.part && !ledger.entities.has(entity.part)) violations.push(`orphan part ${entity.id}`);
    if (kind === "st" && !String(entity.parent ?? "").startsWith("cx:")) violations.push(`st parent ${entity.id}`);
    if (kind === "ls") {
      if (!String(entity.parent ?? "").startsWith("st:")) violations.push(`ls parent ${entity.id}`);
      if (!String(entity.part ?? "").startsWith("lp:")) violations.push(`ls part ${entity.id}`);
    }
  }
  for (const event of ledger.events) {
    if (!ledger.entities.has(event.id)) violations.push(`event target missing ${event.id}`);
    if (event.value && ID_RE.test(event.value) && !ledger.entities.has(event.value)) {
      violations.push(`event value missing ${event.value}`);
    }
    if (event.event === "retire") retired.set(event.id, (retired.get(event.id) ?? 0) + 1);
  }
  for (const [id, count] of retired) {
    if (count > 1) violations.push(`multiple retire ${id}`);
  }
  const aliased = new Set(ledger.aliases.map((alias) => alias.old));
  for (const event of ledger.events) {
    if (event.event !== "retire" || aliased.has(event.id)) continue;
    if (!String(event.why ?? "").startsWith("absent from inputs")) violations.push(`retire without alias ${event.id}`);
  }
  violations.push(...operationViolations(ledger, retired));
  for (const event of ledger.events) {
    if (event.event !== "member") continue;
    if (kindOf(event.id) !== "rp" || !ID_RE.test(event.id)) {
      violations.push(`member event ${event.id}`);
      continue;
    }
    if (retired.has(event.id)) continue;
    const liveLp = kindOf(event.value) === "lp" && ledger.entities.has(event.value) && !retired.has(event.value);
    if (!liveLp) violations.push(`member not live ${event.value}`);
  }
  for (const alias of ledger.aliases) {
    if (!ledger.entities.has(alias.id)) violations.push(`alias target missing ${alias.id}`);
    else if ((alias.scheme === "operator-merge" || alias.scheme === "line-operator") && retiredIds.has(alias.id)) {
      violations.push(`alias target retired ${alias.id}`);
    }
  }
  for (const ref of ledger.refs) {
    if (ref.scheme !== "derivation" || kindOf(ref.id) !== "st" || ref.from) continue;
    if (!ledger.entities.has(ref.id) || retiredIds.has(ref.id)) continue;
    const op = String(ref.value).split("|")[1] ?? "";
    if (retiredIds.has(op)) violations.push(`live st from retired op ${ref.id}`);
  }
  const keyRefs = new Map();
  for (const ref of ledger.refs) {
    const kind = kindOf(ref.id);
    if (KEY_SCHEME[kind] !== ref.scheme) continue;
    // A dated package-operator ref is a rename of the same op, not a second key.
    if (kind === "op" && ref.from) continue;
    if (transferredRefs.has(ref)) continue;
    keyRefs.set(ref.id, (keyRefs.get(ref.id) ?? 0) + 1);
  }
  for (const entity of ledger.entities.values()) {
    const scheme = KEY_SCHEME[kindOf(entity.id)];
    if (!scheme) continue;
    const count = keyRefs.get(entity.id) ?? 0;
    if (count !== 1) violations.push(`key ref ${entity.id} has ${count} ${scheme}`);
  }
  const knownRuns = new Set((ledger.runs ?? []).map((run) => run.run));
  const checkRun = (record, label) => {
    if (!knownRuns.has(record.run)) violations.push(`run missing ${label}`);
  };
  for (const entity of ledger.entities.values()) checkRun(entity, entity.id);
  for (const ref of ledger.refs) checkRun(ref, `ref ${ref.id}`);
  for (const event of ledger.events) checkRun(event, `event ${event.id}`);
  for (const alias of ledger.aliases) checkRun(alias, `alias ${alias.id}`);
  return violations;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function operationViolations(ledger, retired) {
  const violations = [];
  const liveKind = (id, kind) => ledger.entities.has(id) && kindOf(id) === kind && !retired.has(id);
  const withdrawn = withdrawnOperationPairs(ledger.events);
  const endByKey = new Map();
  for (const event of ledger.events) {
    if (event.event !== "operation" && event.event !== "operation-end") continue;
    if (operationEventWithdrawn(event, withdrawn)) continue;
    if (!liveKind(event.id, "lp")) violations.push(`operation not live ${event.id}`);
    if (!liveKind(event.value, "op")) violations.push(`operation not live ${event.value}`);
    if (event.event === "operation-end") {
      if (!ISO_DATE.test(String(event.on ?? ""))) violations.push(`operation date ${event.id}`);
    } else if (event.on != null && event.on !== "" && !ISO_DATE.test(String(event.on))) {
      violations.push(`operation date ${event.id}`);
    }
    if (event.event === "operation-end") {
      endByKey.set(`${event.id}\0${event.value ?? ""}\0${event.why ?? ""}`, event.on ?? null);
    }
  }
  const byLp = new Map();
  for (const event of ledger.events) {
    if (event.event !== "operation" || operationEventWithdrawn(event, withdrawn)) continue;
    const key = `${event.id}\0${event.value ?? ""}\0${event.why ?? ""}`;
    const interval = { from: event.on ?? null, to: endByKey.has(key) ? endByKey.get(key) : null };
    if (!byLp.has(event.id)) byLp.set(event.id, []);
    byLp.get(event.id).push(interval);
  }
  for (const [lp, intervals] of byLp) {
    for (const interval of intervals) {
      if (interval.from && interval.to && String(interval.from) >= String(interval.to)) {
        violations.push(`operation empty ${lp}`);
        break;
      }
    }
    let overlapped = false;
    for (let i = 0; i < intervals.length && !overlapped; i += 1) {
      for (let j = i + 1; j < intervals.length; j += 1) {
        if (operationIntervalsOverlap(intervals[i], intervals[j])) {
          violations.push(`operation overlap ${lp}`);
          overlapped = true;
          break;
        }
      }
    }
  }
  return violations;
}

function readRegionDoc(root, region, name, schema, listKey) {
  const file = path.join(root, region, name);
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) return null;
  const doc = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!doc || doc.schema !== schema || !Array.isArray(doc[listKey])) return { bad: true };
  return doc;
}

function reviewedInputViolations(root, ledger) {
  const violations = [];
  if (!root || !fs.existsSync(root)) return violations;
  const retired = new Set(ledger.events.filter((event) => event.event === "retire").map((event) => event.id));
  const live = (id) => ledger.entities.has(id) && !retired.has(id);
  const merged = new Set(ledger.aliases.filter((alias) => alias.scheme === "operator-merge").map((alias) => `${alias.old}\0${alias.id}`));
  for (const region of REGIONS) {
    const merges = readRegionDoc(root, region, "operator-merges.json", "jtm-operator-merges/1", "merges");
    if (merges?.bad) violations.push(`operator-merges schema ${region}`);
    else if (merges) {
      const intos = new Set(merges.merges.map((item) => String(item.into ?? "")));
      const froms = new Map();
      for (const item of merges.merges) {
        const into = String(item.into ?? "");
        if (!live(into) || kindOf(into) !== "op" || regionOf(into) !== region) violations.push(`merge into not live ${into}`);
        const list = Array.isArray(item.from) ? item.from.map(String) : [];
        if (!list.length) violations.push(`merge without from ${into}`);
        for (const from of list) {
          if (from === into) violations.push(`merge from equals into ${from}`);
          if (intos.has(from)) violations.push(`merge op both into and from ${from}`);
          if (froms.has(from) && froms.get(from) !== into) violations.push(`merge from twice ${from}`);
          froms.set(from, into);
          const ok = ledger.entities.has(from) && kindOf(from) === "op" && (!retired.has(from) || merged.has(`${from}\0${into}`));
          if (!ok) violations.push(`merge from not live ${from}`);
        }
      }
    }
    const overrides = readRegionDoc(root, region, "line-operators.json", "jtm-line-operators/1", "lines");
    if (overrides?.bad) violations.push(`line-operators schema ${region}`);
    else if (overrides) {
      const seen = new Map();
      for (const item of overrides.lines) {
        const lp = String(item.lp ?? "");
        const op = String(item.op ?? "");
        if (!live(lp) || kindOf(lp) !== "lp" || regionOf(lp) !== region) violations.push(`line operator lp not live ${lp}`);
        if (!live(op) || kindOf(op) !== "op" || regionOf(op) !== region) violations.push(`line operator op not live ${op}`);
        if (seen.has(lp) && seen.get(lp) !== op) violations.push(`line operator twice ${lp}`);
        seen.set(lp, op);
      }
    }
    const generics = readRegionDoc(root, region, "generic-operators.json", "jtm-generic-operators/1", "generics");
    if (generics?.bad) violations.push(`generic-operators schema ${region}`);
    else if (generics) {
      const seenGeneric = new Set();
      for (const item of generics.generics) {
        const generic = String(item.generic ?? "");
        const specifics = Array.isArray(item.specifics) ? item.specifics.map(String) : [];
        if (!live(generic) || kindOf(generic) !== "op" || regionOf(generic) !== region) violations.push(`generic operator not live ${generic}`);
        if (seenGeneric.has(generic)) violations.push(`generic operator twice ${generic}`);
        seenGeneric.add(generic);
        if (!specifics.length) violations.push(`generic operator without specifics ${generic}`);
        for (const op of specifics) {
          if (!live(op) || kindOf(op) !== "op" || regionOf(op) !== region) violations.push(`specific operator not live ${op}`);
          if (op === generic) violations.push(`generic operator in own specifics ${generic}`);
        }
      }
      for (const item of generics.generics) {
        const generic = String(item.generic ?? "");
        for (const other of generics.generics) {
          const specifics = Array.isArray(other.specifics) ? other.specifics.map(String) : [];
          if (specifics.includes(generic) && Array.isArray(item.specifics) && item.specifics.map(String).includes(String(other.generic))) {
            violations.push(`generic operators mutually specific ${generic}`);
          }
        }
      }
    }
  }
  return violations;
}

function coverageViolations(dbPath, ledger, root = null) {
  const violations = [];
  if (!fs.existsSync(dbPath)) {
    violations.push(`db missing ${dbPath}`);
    return violations;
  }
  const db = new DatabaseSync(dbPath, { readOnly: true });
  try {
    const retired = new Set(ledger.events.filter((event) => event.event === "retire").map((event) => event.id));
    const live = (id) => ledger.entities.has(id) && !retired.has(id);
    const liveLp = new Map();
    const liveCx = new Map();
    const liveOp = new Map();
    const liveSt = new Map();
    const liveLs = new Map();
    for (const ref of ledger.refs) {
      if (!live(ref.id)) continue;
      if (ref.scheme === "package-line" && kindOf(ref.id) === "lp") pushMap(liveLp, ref.value, ref.id);
      if (ref.scheme === "package-operator" && kindOf(ref.id) === "op") pushMap(liveOp, `${regionOf(ref.id)}\0${ref.value}`, ref.id);
      if (ref.scheme === "group-code" && kindOf(ref.id) === "cx") pushMap(liveCx, `${regionOf(ref.id)}\0${ref.value}`, ref.id);
      if (ref.scheme === "derivation" && kindOf(ref.id) === "st") pushMap(liveSt, `${regionOf(ref.id)}\0${ref.value}`, ref.id);
      if (ref.scheme === "derivation" && kindOf(ref.id) === "ls") pushMap(liveLs, `${regionOf(ref.id)}\0${ref.value}`, ref.id);
    }
    const lines = db.prepare("SELECT id, country_code FROM line").all();
    const lineIds = new Set();
    for (const line of lines) {
      lineIds.add(line.id);
      const ids = (liveLp.get(line.id) ?? []).filter((id) => regionOf(id) === String(line.country_code).toLowerCase());
      if (ids.length !== 1) violations.push(`line ${line.id} has ${ids.length} live lp`);
    }
    for (const [value, ids] of liveLp) {
      if (!lineIds.has(value)) violations.push(`orphan live lp ${ids[0]}`);
    }
    const stops = db.prepare(`
      SELECT ls.line_id, ls.seq, s.code AS code, l.country_code, o.name AS operator_name
        FROM line_station ls
        JOIN station s ON s.id = ls.station_id
        JOIN line l ON l.id = ls.line_id
        JOIN operator o ON o.id = l.operator_id
    `).all();
    const overrideOf = new Map();
    for (const region of REGIONS) {
      const doc = root ? readRegionDoc(root, region, "line-operators.json", "jtm-line-operators/1", "lines") : null;
      if (doc && !doc.bad) for (const item of doc.lines) overrideOf.set(String(item.lp), String(item.op));
    }
    const genericOf = new Map();
    for (const region of REGIONS) {
      const doc = root ? readRegionDoc(root, region, "generic-operators.json", "jtm-generic-operators/1", "generics") : null;
      if (doc && !doc.bad) for (const item of doc.generics) genericOf.set(String(item.generic), new Set((item.specifics ?? []).map(String)));
    }
    const resolveStop = (stop) => {
      const region = String(stop.country_code).toLowerCase();
      const lps = (liveLp.get(stop.line_id) ?? []).filter((id) => regionOf(id) === region);
      const cxs = liveCx.get(`${region}\0${stop.code}`) ?? [];
      const overrideOp = lps.length === 1 ? overrideOf.get(lps[0]) : null;
      const ops = overrideOp ? [overrideOp] : liveOp.get(`${region}\0${stop.operator_name}`) ?? [];
      return { region, lps, cxs, ops };
    };
    const opsAtCx = new Map();
    if (genericOf.size) {
      for (const stop of stops) {
        const { region, cxs, ops } = resolveStop(stop);
        if (cxs.length !== 1 || ops.length !== 1) continue;
        const key = `${region}\0${cxs[0]}`;
        if (!opsAtCx.has(key)) opsAtCx.set(key, new Set());
        opsAtCx.get(key).add(ops[0]);
      }
    }
    const expected = new Set();
    for (const stop of stops) {
      const { region, lps, cxs, ops } = resolveStop(stop);
      if (lps.length !== 1 || cxs.length !== 1 || ops.length !== 1) {
        violations.push(`line_station ${stop.line_id}#${stop.seq} unresolved`);
        continue;
      }
      let op = ops[0];
      const specifics = genericOf.get(op);
      if (specifics) {
        const present = [...specifics].filter((id) => opsAtCx.get(`${region}\0${cxs[0]}`)?.has(id));
        if (present.length === 1) op = present[0];
      }
      const sts = liveSt.get(`${region}\0${cxs[0]}|${op}`) ?? [];
      if (sts.length !== 1) {
        violations.push(`line_station ${stop.line_id}#${stop.seq} unresolved`);
        continue;
      }
      const key = `${region}\0${lps[0]}|${sts[0]}`;
      expected.add(key);
      const found = liveLs.get(key) ?? [];
      if (found.length !== 1) violations.push(`line_station ${stop.line_id}#${stop.seq} has ${found.length} live ls`);
    }
    for (const [key, ids] of liveLs) {
      if (!expected.has(key)) violations.push(`orphan live ls ${ids[0]}`);
    }
    for (const entity of ledger.entities.values()) {
      if (entity.parent && !ledger.entities.has(entity.parent)) violations.push(`orphan parent ${entity.id}`);
    }
    violations.push(...lineOperationViolations(db));
  } finally {
    db.close();
  }
  return violations;
}

function lineOperationViolations(db) {
  const violations = [];
  const present = db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'line_operation'").get();
  if (!present) return violations;
  const rows = db.prepare("SELECT line_id, valid_from, valid_to FROM line_operation ORDER BY line_id").all();
  const byLine = new Map();
  for (const row of rows) {
    if (!byLine.has(row.line_id)) byLine.set(row.line_id, []);
    byLine.get(row.line_id).push({ from: row.valid_from ?? null, to: row.valid_to ?? null });
  }
  for (const [lineId, intervals] of byLine) {
    for (const interval of intervals) {
      if (interval.from && interval.to && String(interval.from) >= String(interval.to)) {
        violations.push(`line_operation empty ${lineId}`);
        break;
      }
    }
    let overlapped = false;
    for (let i = 0; i < intervals.length && !overlapped; i += 1) {
      for (let j = i + 1; j < intervals.length; j += 1) {
        if (operationIntervalsOverlap(intervals[i], intervals[j])) {
          violations.push(`line_operation overlap ${lineId}`);
          overlapped = true;
          break;
        }
      }
    }
  }
  return violations;
}

function git(args, cwd) {
  const env = { ...process.env };
  for (const key of ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR"]) {
    delete env[key];
  }
  return execFileSync("git", ["-c", "core.fsmonitor=false", ...args], { cwd, env, maxBuffer: 64 * 1024 * 1024 });
}

function isLedgerRel(rel) {
  if (rel === "runs.jsonl") return true;
  const match = /^([a-z]{2})\/([^/]+)$/.exec(rel);
  if (!match || !REGIONS.includes(match[1])) return false;
  return !!classifyLedgerName(match[2]);
}

function baseViolations(root, ref) {
  const violations = [];
  let top;
  try {
    top = fs.realpathSync(git(["rev-parse", "--show-toplevel"], root).toString("utf8").trim());
  } catch {
    violations.push(`base: not a git work tree ${root}`);
    return violations;
  }
  const relRoot = path.relative(top, fs.realpathSync(path.resolve(root)));
  const prefix = relRoot ? `${relRoot}/` : "";
  let listed;
  try {
    listed = git(["ls-tree", "-r", "--name-only", ref], top).toString("utf8").split("\n").filter(Boolean);
  } catch {
    violations.push(`base: cannot list ${ref}`);
    return violations;
  }
  for (const gitPath of listed) {
    if (prefix && !gitPath.startsWith(prefix)) continue;
    const rel = gitPath.slice(prefix.length);
    if (!isLedgerRel(rel)) continue;
    const abs = path.join(top, gitPath);
    if (!fs.existsSync(abs)) {
      violations.push(`base prefix: missing ${gitPath}`);
      continue;
    }
    let old;
    try {
      old = git(["show", `${ref}:${gitPath}`], top);
    } catch {
      violations.push(`base prefix: unreadable ${gitPath}`);
      continue;
    }
    const current = fs.readFileSync(abs);
    if (old.length > current.length || !current.subarray(0, old.length).equals(old)) {
      violations.push(`base prefix: ${gitPath} is not a prefix of ${ref}`);
    }
  }
  return violations;
}

function freezeViolations(root) {
  const file = path.join(root, "phase0-freeze.json");
  if (!fs.existsSync(file)) return ["phase 0 freeze missing"];
  const freeze = JSON.parse(fs.readFileSync(file, "utf8"));
  const violations = [];
  for (const entry of freeze.protectedFiles ?? []) {
    const abs = path.resolve(REPO_ROOT, entry.path);
    if (!fs.existsSync(abs)) {
      violations.push(`freeze missing ${entry.path}`);
      continue;
    }
    const hash = crypto.createHash("sha256").update(fs.readFileSync(abs)).digest("hex");
    if (hash !== entry.sha256) violations.push(`freeze mismatch ${entry.path}`);
  }
  return violations;
}

function facilityViolations(ledger) {
  const violations = [];
  const retired = new Set(ledger.events.filter((event) => event.event === "retire").map((event) => event.id));
  const live = (id) => ledger.entities.has(id) && !retired.has(id);
  const derivation = new Map();
  for (const ref of ledger.refs) {
    if (ref.scheme === "derivation" && String(ref.id).startsWith("st:") && !ref.from) derivation.set(ref.id, ref.value);
  }
  const facilityOf = new Map();
  const membersOf = new Map();
  const managerOf = new Map();
  for (const event of ledger.events) {
    if (event.event === "facility" && live(event.value)) {
      if (!membersOf.has(event.value)) membersOf.set(event.value, []);
      membersOf.get(event.value).push(event.id);
      if (facilityOf.has(event.id) && facilityOf.get(event.id) !== event.value) violations.push(`facility station ${event.id}`);
      else facilityOf.set(event.id, event.value);
    } else if (event.event === "manager" && live(event.id)) {
      if (managerOf.has(event.id) && managerOf.get(event.id) !== event.value) violations.push(`facility manager ${event.id}`);
      managerOf.set(event.id, event.value);
    }
  }
  for (const entity of ledger.entities.values()) {
    if (!String(entity.id).startsWith("fc:") || !live(entity.id)) continue;
    const parent = entity.parent ?? "";
    if (!live(parent) || kindOf(parent) !== "cx") violations.push(`facility parent ${entity.id}`);
    const members = membersOf.get(entity.id) ?? [];
    if (!members.length) violations.push(`facility member ${entity.id}`);
    const operators = new Set();
    for (const stationId of members) {
      const station = ledger.entities.get(stationId);
      if (!live(stationId) || kindOf(stationId) !== "st" || station?.parent !== parent) {
        violations.push(`facility member ${stationId}`);
        continue;
      }
      const op = String(derivation.get(stationId) ?? "").split("|")[1] ?? "";
      if (!live(op) || kindOf(op) !== "op") violations.push(`facility member ${stationId}`);
      else if (operators.has(op)) violations.push(`facility operators ${entity.id}`);
      else operators.add(op);
    }
    const manager = managerOf.get(entity.id) ?? "";
    if (!live(manager) || kindOf(manager) !== "op") violations.push(`facility manager ${entity.id}`);
  }
  const seenLink = new Set();
  for (const event of ledger.events) {
    if (event.event !== "link") continue;
    const left = event.id;
    const right = event.value ?? "";
    if (compareId(left, right) >= 0) violations.push(`link order ${left}`);
    if (!live(left) || kindOf(left) !== "st" || !live(right) || kindOf(right) !== "st") {
      violations.push(`link endpoint ${left}`);
      continue;
    }
    const leftParent = ledger.entities.get(left)?.parent ?? "";
    const rightParent = ledger.entities.get(right)?.parent ?? "";
    if (!leftParent || leftParent !== rightParent || kindOf(leftParent) !== "cx") violations.push(`link complex ${left}`);
    const leftFacility = facilityOf.get(left) ?? null;
    const rightFacility = facilityOf.get(right) ?? null;
    if (leftFacility && leftFacility === rightFacility) violations.push(`link facility ${left}`);
    const key = `${left}\0${right}`;
    if (seenLink.has(key)) violations.push(`link duplicate ${left}`);
    else seenLink.add(key);
    if (event.why !== "gate_transfer" && event.why !== "street_transfer") violations.push(`link kind ${left}`);
  }
  return violations;
}

function aliasViolations(root, ledger) {
  const violations = [];
  if (!root || !fs.existsSync(root)) return violations;
  const retired = new Set(ledger.events.filter((event) => event.event === "retire").map((event) => event.id));
  const live = (id) => ledger.entities.has(id) && !retired.has(id);
  const packageNames = new Map();
  for (const ref of ledger.refs) {
    if (ref.scheme !== "package-operator" || !live(ref.id)) continue;
    if (!packageNames.has(ref.id)) packageNames.set(ref.id, new Set());
    packageNames.get(ref.id).add(ref.value);
  }
  for (const region of fs.readdirSync(root)) {
    const file = path.join(root, region, "operator-aliases.json");
    if (!fs.existsSync(file) || !fs.statSync(file).isFile()) continue;
    const doc = JSON.parse(fs.readFileSync(file, "utf8"));
    if (!doc || doc.schema !== "jtm-operator-aliases/1" || !Array.isArray(doc.aliases)) {
      violations.push(`alias schema ${region}`);
      continue;
    }
    const seen = new Map();
    for (const alias of doc.aliases) {
      const text = String(alias.text ?? "");
      const op = String(alias.op ?? "");
      if (!live(op) || kindOf(op) !== "op") violations.push(`alias op ${text}`);
      if (seen.has(text) && seen.get(text) !== op) violations.push(`alias text ${text}`);
      else seen.set(text, op);
      for (const [id, names] of packageNames) {
        if (id !== op && names.has(text)) violations.push(`alias name ${text}`);
      }
    }
  }
  return violations;
}

export function collectViolations({ root, db, base, freeze }) {
  const violations = [];
  if (!fs.existsSync(root)) violations.push(`ledger root missing ${root}`);
  const parsed = fs.existsSync(root) ? parseLedger(root) : {
    ledger: { entities: new Map(), refs: [], events: [], aliases: [], runs: [] },
    violations: [],
  };
  violations.push(...parsed.violations);
  violations.push(...referenceViolations(parsed.ledger));
  violations.push(...facilityViolations(parsed.ledger));
  violations.push(...aliasViolations(root, parsed.ledger));
  violations.push(...reviewedInputViolations(root, parsed.ledger));
  if (db) violations.push(...coverageViolations(db, parsed.ledger, root));
  if (base) violations.push(...baseViolations(root, base));
  if (freeze) violations.push(...freezeViolations(root));
  return { violations, ledger: parsed.ledger };
}

function resolveDefaultBase(root) {
  try {
    const inside = git(["rev-parse", "--is-inside-work-tree"], root).toString("utf8").trim();
    if (inside !== "true") return { reason: "not a git work tree" };
  } catch {
    return { reason: "not a git work tree" };
  }
  try {
    const ref = git(["merge-base", "HEAD", "main"], root).toString("utf8").trim();
    if (!ref) return { reason: "merge-base HEAD main was empty" };
    return { ref };
  } catch {
    return { reason: "merge-base HEAD main did not resolve" };
  }
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  let base = options.base;
  if (options.noBase) base = null;
  else if (!options.base) {
    const resolved = resolveDefaultBase(options.root);
    if (resolved.ref) base = resolved.ref;
    else console.error(`base: skipped (${resolved.reason})`);
  }
  const { violations, ledger } = collectViolations({ ...options, base });
  if (violations.length) {
    for (const violation of violations) console.log(violation);
    process.exit(1);
  }
  console.log(`OK entities=${ledger.entities.size} refs=${ledger.refs.length} events=${ledger.events.length} aliases=${ledger.aliases.length}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
