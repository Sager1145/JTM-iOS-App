#!/usr/bin/env node
// P0 checks for the identity ledger: canonical lines, references, coverage, append-only history.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";

import { ID_RE, REGIONS, classifyLedgerName, parseLedger } from "../build/rail-database/registry.mjs";

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
};

function pushMap(map, key, value) {
  const list = map.get(key);
  if (list) list.push(value);
  else map.set(key, [value]);
}

function referenceViolations(ledger) {
  const violations = [];
  const retired = new Map();
  const refSeen = new Map();
  for (const ref of ledger.refs) {
    if (!ledger.entities.has(ref.id)) violations.push(`ref target missing ${ref.id}`);
    const key = `${regionOf(ref.id)}\0${ref.scheme}\0${ref.value}\0${ref.from ?? ""}`;
    if (refSeen.has(key)) violations.push(`duplicate ref ${ref.scheme} ${ref.value}`);
    else refSeen.set(key, ref.id);
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
  }
  const keyRefs = new Map();
  for (const ref of ledger.refs) {
    const kind = kindOf(ref.id);
    if (KEY_SCHEME[kind] !== ref.scheme) continue;
    // A dated package-operator ref is a rename of the same op, not a second key.
    if (kind === "op" && ref.from) continue;
    keyRefs.set(ref.id, (keyRefs.get(ref.id) ?? 0) + 1);
  }
  for (const entity of ledger.entities.values()) {
    const scheme = KEY_SCHEME[kindOf(entity.id)];
    if (!scheme) continue;
    const count = keyRefs.get(entity.id) ?? 0;
    if (count !== 1) violations.push(`key ref ${entity.id} has ${count} ${scheme}`);
  }
  const knownRuns = new Set(ledger.runs.map((run) => run.run));
  const checkRun = (record, label) => {
    if (!knownRuns.has(record.run)) violations.push(`run missing ${label}`);
  };
  for (const entity of ledger.entities.values()) checkRun(entity, entity.id);
  for (const ref of ledger.refs) checkRun(ref, `ref ${ref.id}`);
  for (const event of ledger.events) checkRun(event, `event ${event.id}`);
  for (const alias of ledger.aliases) checkRun(alias, `alias ${alias.id}`);
  return violations;
}

function coverageViolations(dbPath, ledger) {
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
    const expected = new Set();
    for (const stop of stops) {
      const region = String(stop.country_code).toLowerCase();
      const lps = (liveLp.get(stop.line_id) ?? []).filter((id) => regionOf(id) === region);
      const cxs = liveCx.get(`${region}\0${stop.code}`) ?? [];
      const ops = liveOp.get(`${region}\0${stop.operator_name}`) ?? [];
      if (lps.length !== 1 || cxs.length !== 1 || ops.length !== 1) {
        violations.push(`line_station ${stop.line_id}#${stop.seq} unresolved`);
        continue;
      }
      const sts = liveSt.get(`${region}\0${cxs[0]}|${ops[0]}`) ?? [];
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
  } finally {
    db.close();
  }
  return violations;
}

function git(args, cwd) {
  const env = { ...process.env };
  for (const key of ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR"]) {
    delete env[key];
  }
  return execFileSync("git", args, { cwd, env, maxBuffer: 64 * 1024 * 1024 });
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

export function collectViolations({ root, db, base, freeze }) {
  const violations = [];
  if (!fs.existsSync(root)) violations.push(`ledger root missing ${root}`);
  const parsed = fs.existsSync(root) ? parseLedger(root) : { ledger: { entities: new Map(), refs: [], events: [], aliases: [] }, violations: [] };
  violations.push(...parsed.violations);
  violations.push(...referenceViolations(parsed.ledger));
  if (db) violations.push(...coverageViolations(db, parsed.ledger));
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
