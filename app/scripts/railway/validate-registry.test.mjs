import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { BRACKET_STATUS_MARKERS, KEY_ORDERS, appendLedger, bracketNameRows, canonical, loadRegistryTables, mint, nextSeq, operationIntervalsOverlap, planHistoryCrosswalk, planLineOperationRows, readLedger, reports, splitBracketName } from "../build/rail-database/registry.mjs";
import { buildHistoryCrosswalk } from "./registry-history-crosswalk.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const MINT = path.resolve(HERE, "../build/mint-registry.mjs");
const VALIDATE = path.resolve(HERE, "validate-registry.mjs");
const EXPORT = path.resolve(HERE, "../build/export-registry-bundle.mjs");
const AT = "2026-10-19";

function applySchema(db) {
  db.exec(`
    CREATE TABLE operator (
      id INTEGER PRIMARY KEY,
      country_code TEXT NOT NULL,
      name TEXT NOT NULL,
      short_name TEXT,
      display_label TEXT,
      logo_path TEXT
    );
    CREATE TABLE line (
      id TEXT PRIMARY KEY,
      country_code TEXT NOT NULL,
      operator_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      line_code TEXT,
      railway_identity TEXT,
      interval_count INTEGER NOT NULL DEFAULT 0,
      rank INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE station (
      id INTEGER PRIMARY KEY,
      country_code TEXT NOT NULL,
      code TEXT NOT NULL,
      name TEXT NOT NULL,
      name_norm TEXT NOT NULL,
      lon REAL NOT NULL,
      lat REAL NOT NULL
    );
    CREATE TABLE line_station (
      line_id TEXT NOT NULL,
      seq INTEGER NOT NULL,
      station_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      lon REAL NOT NULL,
      lat REAL NOT NULL,
      PRIMARY KEY (line_id, seq)
    );
    CREATE TABLE source_station (
      id INTEGER PRIMARY KEY,
      country_code TEXT NOT NULL,
      ord INTEGER NOT NULL,
      station_code TEXT NOT NULL,
      group_code TEXT NOT NULL,
      station_id INTEGER,
      name TEXT NOT NULL,
      line_name TEXT NOT NULL,
      operator TEXT NOT NULL,
      display_lon REAL,
      display_lat REAL
    );
  `);
  const operator = db.prepare("INSERT INTO operator (id, country_code, name, short_name, display_label) VALUES (?, ?, ?, ?, ?)");
  operator.run(1, "JP", "JR東日本", "JR東", "JR東日本");
  operator.run(2, "JP", "京王電鉄", "京王", "京王電鉄");
  const line = db.prepare("INSERT INTO line (id, country_code, operator_id, name, line_code, railway_identity, interval_count) VALUES (?, ?, ?, ?, ?, ?, ?)");
  line.run("jp-jr-yamanote", "JP", 1, "山手線", "JY", null, 2);
  line.run("jp-jr-chuo", "JP", 1, "中央線", "JC", null, 1);
  const station = db.prepare("INSERT INTO station (id, country_code, code, name, name_norm, lon, lat) VALUES (?, ?, ?, ?, ?, ?, ?)");
  station.run(1, "JP", "100", "東京", "東京", 139.767, 35.681);
  station.run(2, "JP", "200", "新宿", "新宿", 139.7, 35.689);
  const stop = db.prepare("INSERT INTO line_station (line_id, seq, station_id, name, lon, lat) VALUES (?, ?, ?, ?, ?, ?)");
  stop.run("jp-jr-yamanote", 0, 1, "東京", 139.767, 35.681);
  stop.run("jp-jr-yamanote", 1, 2, "新宿", 139.7, 35.689);
  stop.run("jp-jr-chuo", 0, 2, "新宿", 139.701, 35.69);
  const source = db.prepare(`INSERT INTO source_station
    (country_code, ord, station_code, group_code, station_id, name, line_name, operator, display_lon, display_lat)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  source.run("JP", 1, "100A", "100", 1, "東京", "山手線", "JR東日本", 139.767, 35.681);
  source.run("JP", 2, "200A", "200", 2, "新宿", "山手線", "JR東日本", 139.7, 35.689);
  source.run("JP", 3, "200B", "200", 2, "新宿", "中央線", "JR東日本", 139.701, 35.69);
}

function openFixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "jtm-reg-"));
  const dbPath = path.join(dir, "rail.db");
  const root = path.join(dir, "registry");
  fs.mkdirSync(root);
  const db = new DatabaseSync(dbPath);
  applySchema(db);
  return { dir, dbPath, root, db };
}

function snapshot(root) {
  const out = new Map();
  const walk = (dir) => {
    if (!fs.existsSync(dir)) return;
    for (const name of fs.readdirSync(dir)) {
      const abs = path.join(dir, name);
      if (fs.statSync(abs).isDirectory()) walk(abs);
      else if (name.endsWith(".jsonl")) out.set(path.relative(root, abs), fs.readFileSync(abs));
    }
  };
  walk(root);
  return out;
}

function sameSnapshot(left, right) {
  assert.deepEqual([...left.keys()].sort(), [...right.keys()].sort());
  for (const [key, value] of left) assert.ok(right.get(key).equals(value), key);
}

function refId(ledger, scheme, value) {
  const found = ledger.refs.find((ref) => ref.scheme === scheme && ref.value === value);
  return found?.id ?? null;
}

function seal(additions, runId, at = AT) {
  additions.runs.push({ rec: { run: runId, at, tool: "mint-registry/1", inputs: [] } });
  return additions;
}

function freeze(root) {
  fs.writeFileSync(path.join(root, "phase0-freeze.json"), `${JSON.stringify({ protectedFiles: [], registryInputs: [] })}\n`);
}

function assertLiveLineStops(db, ledger) {
  const retired = new Set(ledger.events.filter((event) => event.event === "retire").map((event) => event.id));
  const deriv = new Map(ledger.refs.filter((ref) => ref.scheme === "derivation").map((ref) => [ref.id, ref.value]));
  const lineOfLp = new Map(ledger.refs.filter((ref) => ref.scheme === "package-line").map((ref) => [ref.id, ref.value]));
  const opOfName = new Map(ledger.refs.filter((ref) => ref.scheme === "package-operator" && !retired.has(ref.id)).map((ref) => [ref.value, ref.id]));
  const cxOfCode = new Map(ledger.refs.filter((ref) => ref.scheme === "group-code" && !retired.has(ref.id)).map((ref) => [ref.value, ref.id]));
  const lineOp = new Map(db.prepare("SELECT id, operator_id FROM line").all().map((row) => [row.id, row.operator_id]));
  const opName = new Map(db.prepare("SELECT id, name FROM operator").all().map((row) => [row.id, row.name]));
  const stops = db.prepare(`
    SELECT l.id AS line_id, s.code AS code
      FROM line_station ls
      JOIN line l ON l.id = ls.line_id
      JOIN station s ON s.id = ls.station_id
  `).all();
  let live = 0;
  for (const [id, entity] of ledger.entities) {
    if (!id.startsWith("ls:") || retired.has(id)) continue;
    live += 1;
    assert.equal(retired.has(entity.parent), false, id);
    const stDeriv = deriv.get(entity.parent);
    assert.ok(stDeriv, id);
    const [cx, op] = stDeriv.split("|");
    const lineId = lineOfLp.get(entity.part);
    assert.ok(lineId, id);
    assert.equal(op, opOfName.get(opName.get(lineOp.get(lineId))), id);
    const groups = stops.filter((stop) => stop.line_id === lineId).map((stop) => cxOfCode.get(stop.code));
    assert.ok(groups.includes(cx), id);
  }
  assert.equal(live, new Set(stops.map((stop) => `${stop.line_id}\0${stop.code}`)).size);
}

function runNode(script, args) {
  return spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });
}

test("canonical omits empty fields and keeps non-ASCII", () => {
  assert.equal(canonical({ run: 1, id: "op:jp:1", slug: "", parent: null }, KEY_ORDERS.entity), '{"id":"op:jp:1","run":1}');
  assert.equal(
    canonical({ run: 1, id: "cx:jp:1", scheme: "group-code", value: "東京" }, KEY_ORDERS.ref),
    '{"id":"cx:jp:1","scheme":"group-code","value":"東京","run":1}',
  );
  const entities = new Map([["op:jp:2", {}], ["op:jp:10", {}], ["lp:jp:4", {}]]);
  assert.equal(nextSeq(entities, "jp", "op"), 11);
  assert.equal(nextSeq(entities, "jp", "st"), 1);
});

test("first mint creates ids and the second mint is byte-identical", () => {
  const fixture = openFixture();
  try {
    const first = seal(mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 1, at: AT }), 1);
    appendLedger(fixture.root, first);
    const ledger = readLedger(fixture.root);
    assert.equal(refId(ledger, "package-operator", "JR東日本"), "op:jp:1");
    assert.equal(refId(ledger, "package-operator", "京王電鉄"), "op:jp:2");
    assert.equal(refId(ledger, "package-line", "jp-jr-yamanote"), "lp:jp:1");
    assert.equal(refId(ledger, "package-line", "jp-jr-chuo"), "lp:jp:2");
    assert.equal(refId(ledger, "group-code", "100"), "cx:jp:1");
    assert.equal(refId(ledger, "group-code", "200"), "cx:jp:2");
    assert.equal(refId(ledger, "derivation", "cx:jp:1|op:jp:1"), "st:jp:1");
    assert.equal(refId(ledger, "derivation", "cx:jp:2|op:jp:1"), "st:jp:2");
    assert.equal(refId(ledger, "derivation", "lp:jp:1|st:jp:1"), "ls:jp:1");
    assert.equal(refId(ledger, "derivation", "lp:jp:1|st:jp:2"), "ls:jp:2");
    assert.equal(refId(ledger, "derivation", "lp:jp:2|st:jp:2"), "ls:jp:3");
    assert.equal(ledger.entities.get("ls:jp:1").parent, "st:jp:1");
    assert.equal(ledger.entities.get("ls:jp:1").part, "lp:jp:1");
    assert.equal(ledger.events.length, 0);
    const before = snapshot(fixture.root);
    const second = mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 2, at: "2026-10-20" });
    assert.equal(second.entities.length, 0);
    assert.equal(second.refs.length, 0);
    assert.equal(second.events.length, 0);
    appendLedger(fixture.root, second);
    sameSnapshot(before, snapshot(fixture.root));
    const ok = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath]);
    assert.equal(ok.status, 0, ok.stdout + ok.stderr);
    assert.match(ok.stdout, /^OK entities=\d+ refs=\d+ events=0 aliases=0\n$/);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("changing line.name keeps the package line id", () => {
  const fixture = openFixture();
  try {
    appendLedger(fixture.root, mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 1, at: AT }));
    const before = refId(readLedger(fixture.root), "package-line", "jp-jr-yamanote");
    fixture.db.prepare("UPDATE line SET name = ? WHERE id = ?").run("山手", "jp-jr-yamanote");
    const again = mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 2, at: AT });
    assert.equal(again.entities.length, 0);
    assert.equal(again.events.length, 0);
    assert.equal(refId(readLedger(fixture.root), "package-line", "jp-jr-yamanote"), before);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("removing a line appends retire events and keeps the old id", () => {
  const fixture = openFixture();
  try {
    appendLedger(fixture.root, seal(mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 1, at: AT }), 1));
    const lpFile = fs.readFileSync(path.join(fixture.root, "jp", "lp.jsonl"));
    fixture.db.prepare("DELETE FROM line_station WHERE line_id = ?").run("jp-jr-chuo");
    fixture.db.prepare("DELETE FROM line WHERE id = ?").run("jp-jr-chuo");
    const again = seal(mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 2, at: AT }), 2);
    assert.equal(again.entities.length, 0);
    const retired = again.events.map((item) => item.rec.id).sort();
    assert.deepEqual(retired, ["lp:jp:2", "ls:jp:3"]);
    appendLedger(fixture.root, again);
    const ledger = readLedger(fixture.root);
    assert.equal(ledger.entities.has("lp:jp:2"), true);
    assert.equal(fs.readFileSync(path.join(fixture.root, "jp", "lp.jsonl")).equals(lpFile), true);
    assert.equal(ledger.events.filter((event) => event.event === "retire" && event.id === "lp:jp:2").length, 1);
    const ok = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath]);
    assert.equal(ok.status, 0, ok.stdout + ok.stderr);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("adding a station appends ids after the current maximum", () => {
  const fixture = openFixture();
  try {
    appendLedger(fixture.root, mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 1, at: AT }));
    const before = snapshot(fixture.root);
    fixture.db.prepare("INSERT INTO station (id, country_code, code, name, name_norm, lon, lat) VALUES (?, ?, ?, ?, ?, ?, ?)")
      .run(3, "JP", "300", "渋谷", "渋谷", 139.7, 35.658);
    fixture.db.prepare("INSERT INTO line_station (line_id, seq, station_id, name, lon, lat) VALUES (?, ?, ?, ?, ?, ?)")
      .run("jp-jr-yamanote", 2, 3, "渋谷", 139.7, 35.658);
    const again = mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 2, at: AT });
    appendLedger(fixture.root, again);
    const ledger = readLedger(fixture.root);
    assert.equal(refId(ledger, "group-code", "300"), "cx:jp:3");
    assert.equal(refId(ledger, "derivation", "cx:jp:3|op:jp:1"), "st:jp:3");
    assert.equal(refId(ledger, "derivation", "lp:jp:1|st:jp:3"), "ls:jp:4");
    assert.equal(nextSeq(ledger.entities, "jp", "cx"), 4);
    for (const [rel, bytes] of before) {
      const current = fs.readFileSync(path.join(fixture.root, rel));
      assert.ok(current.subarray(0, bytes.length).equals(bytes), rel);
    }
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

function mintBase() {
  const fixture = openFixture();
  appendLedger(fixture.root, seal(mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 1, at: AT }), 1));
  fixture.db.close();
  return fixture;
}

function replaceLine(file, index, next) {
  const lines = fs.readFileSync(file, "utf8").split("\n");
  if (lines.at(-1) === "") lines.pop();
  lines[index] = next;
  fs.writeFileSync(file, `${lines.join("\n")}\n`);
}

test("validator rejects an edited line, a deleted line, reordered lines, a duplicate id, and a spaced line", () => {
  const fixture = mintBase();
  try {
    const edited = path.join(fixture.dir, "edited");
    fs.cpSync(fixture.root, edited, { recursive: true });
    const opFile = path.join(edited, "jp", "op.jsonl");
    const lines = fs.readFileSync(opFile, "utf8").trimEnd().split("\n");
    const parsed = JSON.parse(lines[1]);
    lines[1] = JSON.stringify({ run: parsed.run, id: parsed.id });
    fs.writeFileSync(opFile, `${lines.join("\n")}\n`);
    const editedRun = runNode(VALIDATE, ["--root", edited, "--db", fixture.dbPath]);
    assert.equal(editedRun.status, 1);
    assert.match(editedRun.stdout, /not canonical/);

    const deleted = path.join(fixture.dir, "deleted");
    fs.cpSync(fixture.root, deleted, { recursive: true });
    const lpLines = fs.readFileSync(path.join(deleted, "jp", "lp.jsonl"), "utf8").trimEnd().split("\n");
    lpLines.pop();
    fs.writeFileSync(path.join(deleted, "jp", "lp.jsonl"), `${lpLines.join("\n")}\n`);
    const deletedRun = runNode(VALIDATE, ["--root", deleted, "--db", fixture.dbPath]);
    assert.equal(deletedRun.status, 1);
    assert.match(deletedRun.stdout, /missing|live lp/);

    const reordered = path.join(fixture.dir, "reordered");
    fs.cpSync(fixture.root, reordered, { recursive: true });
    const entity = path.join(reordered, "jp", "lp.jsonl");
    const entityLines = fs.readFileSync(entity, "utf8").trimEnd().split("\n");
    const swapped = [entityLines[0], entityLines[2], entityLines[1]];
    fs.writeFileSync(entity, `${swapped.join("\n")}\n`);
    const reorderedRun = runNode(VALIDATE, ["--root", reordered, "--db", fixture.dbPath]);
    assert.equal(reorderedRun.status, 1);
    assert.match(reorderedRun.stdout, /seq not increasing/);

    const duplicate = path.join(fixture.dir, "duplicate");
    fs.cpSync(fixture.root, duplicate, { recursive: true });
    const dupFile = path.join(duplicate, "jp", "op.jsonl");
    const dupLines = fs.readFileSync(dupFile, "utf8").trimEnd().split("\n");
    fs.writeFileSync(dupFile, `${[...dupLines, dupLines[1]].join("\n")}\n`);
    const duplicateRun = runNode(VALIDATE, ["--root", duplicate, "--db", fixture.dbPath]);
    assert.equal(duplicateRun.status, 1);
    assert.match(duplicateRun.stdout, /duplicate id/);

    const spaced = path.join(fixture.dir, "spaced");
    fs.cpSync(fixture.root, spaced, { recursive: true });
    replaceLine(path.join(spaced, "jp", "op.jsonl"), 1, '{ "id": "op:jp:1", "run": 1 }');
    const spacedRun = runNode(VALIDATE, ["--root", spaced, "--db", fixture.dbPath]);
    assert.equal(spacedRun.status, 1);
    assert.match(spacedRun.stdout, /not canonical/);
  } finally {
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("--base rejects a rewritten ledger file", () => {
  const fixture = mintBase();
  const env = {
    ...process.env,
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_AUTHOR_NAME: "test",
    GIT_AUTHOR_EMAIL: "test@example.com",
    GIT_COMMITTER_NAME: "test",
    GIT_COMMITTER_EMAIL: "test@example.com",
  };
  try {
    execFileSync("git", ["init", "-b", "main"], { cwd: fixture.root, env });
    execFileSync("git", ["config", "user.email", "test@example.com"], { cwd: fixture.root, env });
    execFileSync("git", ["config", "user.name", "test"], { cwd: fixture.root, env });
    execFileSync("git", ["config", "core.autocrlf", "false"], { cwd: fixture.root, env });
    execFileSync("git", ["add", "."], { cwd: fixture.root, env });
    execFileSync("git", ["commit", "-m", "base"], { cwd: fixture.root, env });
    const file = path.join(fixture.root, "runs.jsonl");
    const text = fs.readFileSync(file, "utf8").replaceAll("mint-registry/1", "mint-registry/9");
    fs.writeFileSync(file, text);
    const still = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(still.status, 0, still.stdout + still.stderr);
    const rejected = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath]);
    assert.equal(rejected.status, 1, rejected.stdout + rejected.stderr);
    assert.match(rejected.stdout, /prefix/);
  } finally {
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("mint CLI refuses without a freeze, then mints idempotently", () => {
  const fixture = openFixture();
  try {
    const missing = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(missing.status, 1);
    assert.match(missing.stdout, /phase 0 freeze missing/);
    fs.writeFileSync(path.join(fixture.root, "phase0-freeze.json"), `${JSON.stringify({ protectedFiles: [], registryInputs: [] })}\n`);
    const dry = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT, "--dry-run"]);
    assert.equal(dry.status, 0, dry.stdout + dry.stderr);
    assert.match(dry.stdout, /op\.jsonl \+/);
    assert.equal(fs.readdirSync(fixture.root).some((name) => name.endsWith(".jsonl")), false);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const before = snapshot(fixture.root);
    const second = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(second.status, 0, second.stdout + second.stderr);
    assert.match(second.stdout, /no changes/);
    sameSnapshot(before, snapshot(fixture.root));
    const ok = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath]);
    assert.equal(ok.status, 0, ok.stdout + ok.stderr);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("operator transfer", () => {
  const fixture = openFixture();
  try {
    appendLedger(fixture.root, seal(mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 1, at: AT }), 1));
    fixture.db.prepare("UPDATE line SET operator_id = 2 WHERE id = ?").run("jp-jr-chuo");
    const again = mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 2, at: AT });
    const retired = again.events.filter((item) => item.rec.event === "retire").map((item) => item.rec.id).sort();
    assert.deepEqual(retired, ["ls:jp:3"]);
    const minted = again.entities.find((item) => item.rec.id === "ls:jp:4");
    assert.equal(minted.rec.parent, "st:jp:3");
    assert.equal(minted.rec.part, "lp:jp:2");
    appendLedger(fixture.root, seal(again, 2));
    const ledger = readLedger(fixture.root);
    assert.equal(refId(ledger, "derivation", "lp:jp:2|st:jp:3"), "ls:jp:4");
    assert.equal(ledger.entities.get("st:jp:3").parent, "cx:jp:2");
    assertLiveLineStops(fixture.db, ledger);
    const passed = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(passed.status, 0, passed.stdout + passed.stderr);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("reappeared input mints nothing and the CLI exits 1", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    fixture.db.prepare("DELETE FROM line_station WHERE line_id = ?").run("jp-jr-chuo");
    fixture.db.prepare("DELETE FROM line WHERE id = ?").run("jp-jr-chuo");
    const retired = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT, "--allow-retire"]);
    assert.equal(retired.status, 0, retired.stdout + retired.stderr);
    const before = snapshot(fixture.root);
    fixture.db.prepare("INSERT INTO line (id, country_code, operator_id, name, line_code, railway_identity, interval_count) VALUES (?, ?, ?, ?, ?, ?, ?)")
      .run("jp-jr-chuo", "JP", 1, "中央線", "JC", null, 1);
    fixture.db.prepare("INSERT INTO line_station (line_id, seq, station_id, name, lon, lat) VALUES (?, ?, ?, ?, ?, ?)")
      .run("jp-jr-chuo", 0, 2, "新宿", 139.701, 35.69);
    const again = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT, "--allow-retire"]);
    assert.equal(again.status, 1, again.stdout + again.stderr);
    assert.match(again.stdout, /reappeared/);
    sameSnapshot(before, snapshot(fixture.root));
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("crash after ref rename resumes without duplicate ids", () => {
  const fixture = openFixture();
  try {
    const first = seal(mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 1, at: AT }), 1);
    process.env.JTM_REGISTRY_CRASH_AFTER = "refs";
    assert.throws(() => appendLedger(fixture.root, first), /injected crash/);
    assert.equal(fs.existsSync(path.join(fixture.root, "jp", "op.ref.jsonl")), true);
    assert.equal(fs.existsSync(path.join(fixture.root, "jp", "op.jsonl")), false);
    delete process.env.JTM_REGISTRY_CRASH_AFTER;
    const partial = readLedger(fixture.root);
    const again = mint(fixture.db, partial, { region: "jp", runId: 1, at: AT });
    assert.equal(again.refs.length, 0);
    assert.equal(again.events.length, 0);
    const ids = again.entities.map((item) => item.rec.id);
    assert.equal(new Set(ids).size, ids.length);
    const keyIds = [...new Set(partial.refs.filter((ref) => ["package-operator", "package-line", "group-code", "derivation"].includes(ref.scheme)).map((ref) => ref.id))].sort();
    assert.deepEqual(keyIds, [...ids].sort());
    appendLedger(fixture.root, seal(again, 1));
    const ledger = readLedger(fixture.root);
    assert.equal(refId(ledger, "package-operator", "JR東日本"), "op:jp:1");
    assert.equal(refId(ledger, "derivation", "lp:jp:1|st:jp:1"), "ls:jp:1");
    const passed = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(passed.status, 0, passed.stdout + passed.stderr);
    const third = mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 2, at: AT });
    assert.equal(third.entities.length, 0);
    assert.equal(third.refs.length, 0);
  } finally {
    delete process.env.JTM_REGISTRY_CRASH_AFTER;
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("entities without key refs fail validation", () => {
  const fixture = mintBase();
  try {
    const refFile = path.join(fixture.root, "jp", "op.ref.jsonl");
    const [header] = fs.readFileSync(refFile, "utf8").split("\n");
    fs.writeFileSync(refFile, `${header}\n`);
    const bad = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(bad.status, 1);
    assert.match(bad.stdout, /key ref op:jp:1 has 0 package-operator/);
  } finally {
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("station codes shared by several operators are assigned to none", () => {
  const fixture = openFixture();
  try {
    fixture.db.prepare("INSERT INTO line (id, country_code, operator_id, name, line_code, railway_identity, interval_count) VALUES (?, ?, ?, ?, ?, ?, ?)")
      .run("jp-keio-line", "JP", 2, "京王線", "KO", null, 1);
    fixture.db.prepare("INSERT INTO line_station (line_id, seq, station_id, name, lon, lat) VALUES (?, ?, ?, ?, ?, ?)")
      .run("jp-keio-line", 0, 2, "新宿", 139.7, 35.689);
    fixture.db.prepare(`INSERT INTO source_station
      (country_code, ord, station_code, group_code, station_id, name, line_name, operator, display_lon, display_lat)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run("JP", 4, "SHARED", "200", 2, "新宿", "京王線", "京王電鉄", 139.7, 35.689);
    fixture.db.prepare(`INSERT INTO source_station
      (country_code, ord, station_code, group_code, station_id, name, line_name, operator, display_lon, display_lat)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run("JP", 5, "SHARED", "200", 2, "新宿", "山手線", "JR東日本", 139.7, 35.689);
    appendLedger(fixture.root, seal(mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 1, at: AT }), 1));
    const ledger = readLedger(fixture.root);
    assert.equal(refId(ledger, "station-code", "SHARED"), null);
    assert.equal(refId(ledger, "station-code", "200A"), "st:jp:2");
    const report = reports(fixture.db, ledger, "jp");
    assert.deepEqual(report["station-code-conflict"], [
      { value: "SHARED", candidates: ["st:jp:2", "st:jp:3"] },
    ]);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("same-operator-split-names uses source station names", () => {
  const fixture = openFixture();
  try {
    fixture.db.prepare(`INSERT INTO source_station
      (country_code, ord, station_code, group_code, station_id, name, line_name, operator, display_lon, display_lat)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run("JP", 4, "200C", "200", 2, "新宿駅", "中央線", "JR東日本", 139.701, 35.69);
    appendLedger(fixture.root, seal(mint(fixture.db, readLedger(fixture.root), { region: "jp", runId: 1, at: AT }), 1));
    const report = reports(fixture.db, readLedger(fixture.root), "jp");
    const row = report["same-operator-split-names"].find((item) => item.cx === "cx:jp:2");
    assert.ok(row);
    assert.deepEqual(row.names, ["新宿", "新宿駅"]);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("external_ref rejects a duplicate region, scheme, and value", () => {
  const sql = fs.readFileSync(path.resolve(HERE, "../build/rail-database/schema.sql"), "utf8");
  const slice = sql.slice(sql.indexOf("-- Identity registry")).replace(/CREATE VIEW[\s\S]*/, "");
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(slice);
    db.prepare("INSERT INTO registry_entity (id, kind, region) VALUES ('lp:jp:1', 'lp', 'jp')").run();
    db.prepare("INSERT INTO registry_entity (id, kind, region) VALUES ('lp:tw:1', 'lp', 'tw')").run();
    const insert = db.prepare("INSERT INTO external_ref (entity_id, scheme, value, region) VALUES (?, 'package-line', 'L1', ?)");
    insert.run("lp:jp:1", "jp");
    insert.run("lp:tw:1", "tw");
    assert.throws(() => insert.run("lp:jp:1", "jp"));
  } finally {
    db.close();
  }
});

test("changing a package line id mints a new lp and retires the old one", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    fixture.db.prepare("UPDATE line_station SET line_id = ? WHERE line_id = ?").run("jp-jr-yamanote-b", "jp-jr-yamanote");
    fixture.db.prepare("UPDATE line SET id = ? WHERE id = ?").run("jp-jr-yamanote-b", "jp-jr-yamanote");
    const before = snapshot(fixture.root);
    const refused = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(refused.status, 1, refused.stdout + refused.stderr);
    assert.match(refused.stdout, /retire refused/);
    assert.match(refused.stdout, /jp lp 1/);
    assert.match(refused.stdout, /jp ls 2/);
    sameSnapshot(before, snapshot(fixture.root));
    const allowed = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT, "--allow-retire"]);
    assert.equal(allowed.status, 0, allowed.stdout + allowed.stderr);
    const ledger = readLedger(fixture.root);
    assert.equal(refId(ledger, "package-line", "jp-jr-yamanote-b"), "lp:jp:3");
    assert.ok(ledger.events.some((event) => event.event === "retire" && event.id === "lp:jp:1"));
    assert.equal(ledger.entities.has("lp:jp:1"), true);
    const passed = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(passed.status, 0, passed.stdout + passed.stderr);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("line crosswalk mints ln once and does not reassign an lp", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    fs.mkdirSync(path.join(fixture.root, "jp"), { recursive: true });
    const crosswalkPath = path.join(fixture.root, "jp", "line-crosswalk.json");
    const writeCrosswalk = (groups) => {
      fs.writeFileSync(crosswalkPath, `${JSON.stringify({ schema: "jtm-line-crosswalk/1", groups })}\n`);
    };
    writeCrosswalk([{ slug: "jr-pair", lp: ["lp:jp:2", "lp:jp:1"], why: "paired", source: "adr" }]);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const ledger = readLedger(fixture.root);
    assert.equal(ledger.entities.get("ln:jp:1").slug, "jr-pair");
    assert.equal(refId(ledger, "crosswalk", "lp:jp:1,lp:jp:2"), "ln:jp:1");
    const lineEvents = ledger.events.filter((event) => event.event === "line");
    assert.deepEqual(lineEvents.map((event) => event.id).sort(), ["lp:jp:1", "lp:jp:2"]);
    assert.equal(lineEvents[0].value, "ln:jp:1");
    assert.equal(lineEvents[0].why, "paired");
    const before = snapshot(fixture.root);
    const second = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(second.status, 0, second.stdout + second.stderr);
    assert.match(second.stdout, /no changes/);
    sameSnapshot(before, snapshot(fixture.root));
    writeCrosswalk([
      { slug: "jr-pair", lp: ["lp:jp:1", "lp:jp:2"], why: "paired", source: "adr" },
      { slug: "steal", lp: ["lp:jp:1"], why: "no", source: "adr" },
    ]);
    const third = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(third.status, 0, third.stdout + third.stderr);
    assert.match(third.stdout, /crosswalk-conflict 1/);
    sameSnapshot(before, snapshot(fixture.root));
    const report = JSON.parse(fs.readFileSync(path.join(fixture.root, "jp", "station-derivation-exceptions.json"), "utf8"));
    assert.equal(report["crosswalk-conflict"].length, 1);
    assert.equal(report["crosswalk-conflict"][0].slug, "steal");
    assert.deepEqual(report["crosswalk-conflict"][0].assigned, [{ lp: "lp:jp:1", ln: "ln:jp:1" }]);
    const passed = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(passed.status, 0, passed.stdout + passed.stderr);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("operator rename keeps op, line, and station ids", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const before = readLedger(fixture.root);
    const op = refId(before, "package-operator", "JR東日本");
    const lp = refId(before, "package-line", "jp-jr-yamanote");
    const tokyo = refId(before, "derivation", "cx:jp:1|op:jp:1");
    const shinjuku = refId(before, "derivation", "cx:jp:2|op:jp:1");
    fs.writeFileSync(path.join(fixture.root, "jp", "operator-renames.json"), `${JSON.stringify({
      schema: "jtm-operator-renames/1",
      renames: [
        { op, name: "JR東日本新", from: AT, source: "test" },
        { op: "op:jp:99", name: "ない会社", from: AT, source: "test" },
      ],
    })}\n`);
    fixture.db.prepare("UPDATE operator SET name = ?, display_label = ? WHERE id = ?").run("JR東日本新", "JR東日本新", 1);
    const again = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(again.status, 0, again.stdout + again.stderr);
    assert.match(again.stdout, /operator-rename-invalid 1/);
    const ledger = readLedger(fixture.root);
    assert.equal(refId(ledger, "package-operator", "JR東日本"), op);
    assert.equal(refId(ledger, "package-operator", "JR東日本新"), op);
    assert.equal(ledger.refs.find((ref) => ref.scheme === "package-operator" && ref.value === "JR東日本新").from, AT);
    assert.equal(refId(ledger, "package-operator", "ない会社"), null);
    assert.equal(refId(ledger, "package-line", "jp-jr-yamanote"), lp);
    assert.equal(refId(ledger, "package-line", "jp-jr-chuo"), "lp:jp:2");
    assert.equal(refId(ledger, "derivation", `cx:jp:1|${op}`), tokyo);
    assert.equal(refId(ledger, "derivation", `cx:jp:2|${op}`), shinjuku);
    assert.equal(ledger.events.some((event) => event.event === "retire"), false);
    const passed = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(passed.status, 0, passed.stdout + passed.stderr);
    const report = JSON.parse(fs.readFileSync(path.join(fixture.root, "jp", "station-derivation-exceptions.json"), "utf8"));
    assert.equal(report["operator-rename-invalid"].length, 1);
    assert.equal(report["operator-rename-invalid"][0].op, "op:jp:99");
    const repeat = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(repeat.status, 0, repeat.stdout + repeat.stderr);
    assert.match(repeat.stdout, /no changes/);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("operator rename is rejected when another live operator holds the name", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const before = readLedger(fixture.root);
    const op1 = refId(before, "package-operator", "JR東日本");
    const op2 = refId(before, "package-operator", "京王電鉄");
    const dated = canonical({
      id: op2, scheme: "package-operator", value: "共有名", from: "2020-01-01", run: 1,
    }, KEY_ORDERS.ref);
    fs.appendFileSync(path.join(fixture.root, "jp", "op.ref.jsonl"), `${dated}\n`);
    fs.writeFileSync(path.join(fixture.root, "jp", "operator-renames.json"), `${JSON.stringify({
      schema: "jtm-operator-renames/1",
      renames: [{ op: op1, name: "共有名", from: AT, source: "test" }],
    })}\n`);
    const again = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(again.status, 0, again.stdout + again.stderr);
    assert.match(again.stdout, /operator-rename-invalid/);
    const ledger = readLedger(fixture.root);
    assert.equal(ledger.refs.some((ref) => ref.scheme === "package-operator" && ref.value === "共有名" && ref.id === op1), false);
    assert.equal(ledger.refs.find((ref) => ref.id === op2 && ref.value === "共有名").from, "2020-01-01");
    const report = JSON.parse(fs.readFileSync(path.join(fixture.root, "jp", "station-derivation-exceptions.json"), "utf8"));
    assert.equal(report["operator-rename-invalid"].length, 1);
    assert.equal(report["operator-rename-invalid"][0].op, op1);
    assert.equal(report["operator-rename-invalid"][0].name, "共有名");
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("an operator name held by two live ops mints nothing and exits 1", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const op2 = refId(readLedger(fixture.root), "package-operator", "京王電鉄");
    const dated = canonical({
      id: op2, scheme: "package-operator", value: "JR東日本", from: "2020-01-01", run: 1,
    }, KEY_ORDERS.ref);
    fs.appendFileSync(path.join(fixture.root, "jp", "op.ref.jsonl"), `${dated}\n`);
    const before = snapshot(fixture.root);
    const again = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT, "--allow-retire"]);
    assert.equal(again.status, 1, again.stdout + again.stderr);
    assert.match(again.stdout, /operator-name-ambiguous/);
    sameSnapshot(before, snapshot(fixture.root));
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("renaming an operator without a mapping is refused", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const before = snapshot(fixture.root);
    fixture.db.prepare("UPDATE operator SET name = ? WHERE name = ?").run("JR東日本新", "JR東日本");
    const refused = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(refused.status, 1, refused.stdout + refused.stderr);
    assert.match(refused.stdout, /retire refused/);
    sameSnapshot(before, snapshot(fixture.root));
    const allowed = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT, "--allow-retire"]);
    assert.equal(allowed.status, 0, allowed.stdout + allowed.stderr);
    const ledger = readLedger(fixture.root);
    assert.notEqual(refId(ledger, "package-operator", "JR東日本新"), "op:jp:1");
    assert.ok(ledger.events.some((event) => event.event === "retire" && event.id === "op:jp:1"));
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("route pattern mints an rp, a key ref, and member events", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    fs.writeFileSync(path.join(fixture.root, "jp", "route-patterns.json"), `${JSON.stringify({
      schema: "jtm-route-patterns/1",
      patterns: [{
        slug: "jr-pair",
        lp: ["lp:jp:2", "lp:jp:1"],
        kind: "through-run",
        why: "test",
        source: "test",
      }],
    })}\n`);
    const minted = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(minted.status, 0, minted.stdout + minted.stderr);
    const ledger = readLedger(fixture.root);
    assert.equal(ledger.entities.get("rp:jp:1").slug, "jr-pair");
    assert.equal(refId(ledger, "route-pattern", "lp:jp:1,lp:jp:2"), "rp:jp:1");
    const members = ledger.events.filter((event) => event.event === "member").map((event) => event.value).sort();
    assert.deepEqual(members, ["lp:jp:1", "lp:jp:2"]);
    const before = snapshot(fixture.root);
    const repeat = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(repeat.status, 0, repeat.stdout + repeat.stderr);
    assert.match(repeat.stdout, /no changes/);
    sameSnapshot(before, snapshot(fixture.root));
    const passed = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(passed.status, 0, passed.stdout + passed.stderr);

    const retiredMember = path.join(fixture.dir, "retired-member");
    fs.cpSync(fixture.root, retiredMember, { recursive: true });
    const retire = canonical({ id: "lp:jp:2", event: "retire", on: AT, why: "test", run: 1 }, KEY_ORDERS.event);
    fs.appendFileSync(path.join(retiredMember, "jp", "events.jsonl"), `${retire}\n`);
    const memberBad = runNode(VALIDATE, ["--root", retiredMember, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(memberBad.status, 1);
    assert.match(memberBad.stdout, /member not live lp:jp:2/);

    const missingKey = path.join(fixture.dir, "missing-key");
    fs.cpSync(fixture.root, missingKey, { recursive: true });
    const refFile = path.join(missingKey, "jp", "rp.ref.jsonl");
    const [header] = fs.readFileSync(refFile, "utf8").split("\n");
    fs.writeFileSync(refFile, `${header}\n`);
    const keyBad = runNode(VALIDATE, ["--root", missingKey, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(keyBad.status, 1);
    assert.match(keyBad.stdout, /key ref rp:jp:1 has 0 route-pattern/);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("registry bundle is deterministic and drops conflicted or retired ids", () => {
  const fixture = openFixture();
  try {
    fixture.db.prepare("INSERT INTO line (id, country_code, operator_id, name, line_code, railway_identity, interval_count) VALUES (?, ?, ?, ?, ?, ?, ?)")
      .run("jp-keio-line", "JP", 2, "京王線", "KO", null, 1);
    fixture.db.prepare("INSERT INTO line_station (line_id, seq, station_id, name, lon, lat) VALUES (?, ?, ?, ?, ?, ?)")
      .run("jp-keio-line", 0, 2, "新宿", 139.7, 35.689);
    fixture.db.prepare(`INSERT INTO source_station
      (country_code, ord, station_code, group_code, station_id, name, line_name, operator, display_lon, display_lat)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run("JP", 4, "SHARED", "200", 2, "新宿", "京王線", "京王電鉄", 139.7, 35.689);
    fixture.db.prepare(`INSERT INTO source_station
      (country_code, ord, station_code, group_code, station_id, name, line_name, operator, display_lon, display_lat)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run("JP", 5, "SHARED", "200", 2, "新宿", "山手線", "JR東日本", 139.7, 35.689);
    fixture.db.exec("CREATE TABLE operator_alias (id INTEGER PRIMARY KEY, scope TEXT, alias TEXT, label TEXT)");
    fixture.db.prepare("INSERT INTO operator_alias (scope, alias, label) VALUES (?, ?, ?)").run("JP", "JR East", "JR東日本");
    fixture.db.prepare("UPDATE operator SET logo_path = ? WHERE name = ?").run("/logos/jr-east.svg", "JR東日本");
    fixture.db.prepare("UPDATE line SET rank = ? WHERE id = ?").run(4, "jp-jr-yamanote");
    fixture.db.prepare("UPDATE line_station SET name = ? WHERE line_id = ?").run("新宿駅", "jp-jr-chuo");
    fixture.db.prepare("UPDATE station SET name = ?, lon = ? WHERE code = ?").run("東京（丸の内）", 139.767126, "100");
    fixture.db.prepare("UPDATE line_station SET name = ? WHERE station_id = ?").run("東京（丸の内）", 1);
    fixture.db.prepare(
      "INSERT INTO operator (id, country_code, name, short_name, display_label, logo_path) VALUES (?, ?, ?, ?, ?, ?)",
    ).run(3, "JP", "架空鉄道", null, "架空", null);
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const out = path.join(fixture.dir, "bundle");
    const exported = runNode(EXPORT, ["--db", fixture.dbPath, "--root", fixture.root, "--out", out]);
    assert.equal(exported.status, 0, exported.stdout + exported.stderr);
    const file = path.join(out, "jp.json");
    const text = fs.readFileSync(file);
    const again = runNode(EXPORT, ["--db", fixture.dbPath, "--root", fixture.root, "--out", out]);
    assert.equal(again.status, 0, again.stdout + again.stderr);
    assert.ok(fs.readFileSync(file).equals(text));
    const check = runNode(EXPORT, ["--db", fixture.dbPath, "--root", fixture.root, "--out", out, "--check"]);
    assert.equal(check.status, 0, check.stdout + check.stderr);
    const bundle = JSON.parse(text.toString("utf8"));
    assert.equal(bundle.schema, "jtm-registry-bundle/2");
    assert.equal(bundle.stationCodes.SHARED, undefined);
    assert.equal(bundle.stationCodes["200A"], "st:jp:2");
    assert.equal(bundle.lines["jp-jr-yamanote"], "lp:jp:1");
    assert.deepEqual(bundle.groupCodes["200"], ["st:jp:2", "st:jp:3"]);
    assert.equal(bundle.stationOperator["st:jp:1"], "op:jp:1");
    assert.ok(bundle.operators["op:jp:1"].names.includes("JR東日本"));
    assert.ok(bundle.operators["op:jp:1"].names.includes("JR東"));
    assert.ok(bundle.operators["op:jp:1"].names.includes("JR East"));
    assert.equal(bundle.operators["op:jp:1"].label, "JR東日本");
    assert.equal(bundle.operators["op:jp:1"].logo, "/logos/jr-east.svg");
    assert.equal(bundle.operators["op:jp:1"].identity, "jp.jr-east");
    assert.equal(bundle.operators["op:jp:2"].identity, "jp.keio");
    assert.equal(bundle.operators["op:jp:3"].identity, null);
    assert.equal(bundle.operators["op:jp:3"].label, "架空");
    assert.equal(bundle.operators["op:jp:3"].logo, null);
    assert.deepEqual(bundle.stations["st:jp:2"].codes, ["200A", "200B"]);
    for (const station of Object.values(bundle.stations)) {
      assert.equal(station.codes.includes("SHARED"), false);
    }
    assert.equal(bundle.stations["st:jp:1"].name, "東京（丸の内）");
    assert.deepEqual(bundle.stations["st:jp:1"].parts, {
      base: "東京", bracket: "丸の内", kind: "subname", position: "suffix",
    });
    assert.equal(bundle.stations["st:jp:1"].cx, "cx:jp:1");
    assert.equal(bundle.stations["st:jp:1"].group, "100");
    assert.equal(bundle.stations["st:jp:1"].op, "op:jp:1");
    assert.deepEqual(bundle.stations["st:jp:1"].lines, ["lp:jp:1"]);
    assert.equal(bundle.stations["st:jp:1"].ln, undefined);
    assert.equal(bundle.stations["st:jp:2"].name, "新宿");
    assert.equal(bundle.stations["st:jp:2"].parts, undefined);
    assert.deepEqual(bundle.stations["st:jp:2"].lines, ["lp:jp:1", "lp:jp:2"]);
    assert.equal(bundle.complexes["cx:jp:1"].name, "東京（丸の内）");
    assert.deepEqual(bundle.complexes["cx:jp:1"].stations, ["st:jp:1"]);
    assert.equal(bundle.complexes["cx:jp:1"].lon, Number((139.767126).toFixed(5)));
    assert.notEqual(bundle.complexes["cx:jp:1"].lon, 139.767126);
    assert.equal(bundle.complexes["cx:jp:1"].lat, 35.681);
    assert.deepEqual(bundle.complexes["cx:jp:2"].stations, ["st:jp:2", "st:jp:3"]);
    assert.equal(bundle.lineParts["lp:jp:1"].packageLine, "jp-jr-yamanote");
    assert.equal(bundle.lineParts["lp:jp:1"].name, "山手線");
    assert.equal(bundle.lineParts["lp:jp:1"].op, "op:jp:1");
    assert.equal(bundle.lineParts["lp:jp:1"].rank, 4);
    assert.equal(bundle.lineParts["lp:jp:1"].ln, undefined);
    assert.equal(/[:,]\s/.test(text.toString("utf8")), false);
    fs.writeFileSync(file, text.toString("utf8").replace("JR東", "JR西"));
    const drifted = runNode(EXPORT, ["--db", fixture.dbPath, "--root", fixture.root, "--out", out, "--check"]);
    assert.equal(drifted.status, 1);
    assert.match(drifted.stdout, /bundle differs jp/);

    fixture.db.prepare("DELETE FROM line_station WHERE line_id = ? AND station_id = ?").run("jp-jr-yamanote", 1);
    const retired = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT, "--allow-retire"]);
    assert.equal(retired.status, 0, retired.stdout + retired.stderr);
    const after = runNode(EXPORT, ["--db", fixture.dbPath, "--root", fixture.root, "--out", out]);
    assert.equal(after.status, 0, after.stdout + after.stderr);
    const next = JSON.parse(fs.readFileSync(file, "utf8"));
    assert.equal(next.stationOperator["st:jp:1"], undefined);
    assert.equal(next.stationCodes["100A"], undefined);
    assert.equal(next.lines["jp-jr-yamanote"], "lp:jp:1");
    assert.equal(Object.values(next.stationOperator).includes("st:jp:1"), false);
    assert.equal(Object.values(next.groupCodes).some((ids) => ids.includes("st:jp:1")), false);
    assert.equal(next.stations["st:jp:1"], undefined);
    assert.equal((next.complexes["cx:jp:1"]?.stations ?? []).includes("st:jp:1"), false);
    assert.equal(next.lineParts["lp:jp:1"].packageLine, "jp-jr-yamanote");
    for (const station of Object.values(next.stations)) {
      assert.equal(station.codes.includes("100A"), false);
    }
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

function openHistoryDb() {
  const db = new DatabaseSync(":memory:");
  db.exec(`
    CREATE TABLE operator (id INTEGER PRIMARY KEY, country_code TEXT, name TEXT);
    CREATE TABLE line (id TEXT PRIMARY KEY, country_code TEXT, operator_id INTEGER, name TEXT);
    CREATE TABLE "interval" (id INTEGER PRIMARY KEY, line_id TEXT);
    CREATE TABLE interval_vertex (
      interval_id INTEGER, seq INTEGER, lon REAL, lat REAL,
      PRIMARY KEY (interval_id, seq)
    );
    CREATE TABLE registry_entity (id TEXT PRIMARY KEY, kind TEXT, region TEXT, retired TEXT);
    CREATE TABLE external_ref (entity_id TEXT, scheme TEXT, value TEXT, valid_from TEXT);
  `);
  const operator = db.prepare("INSERT INTO operator (id, country_code, name) VALUES (?, 'JP', ?)");
  operator.run(1, "JR東日本");
  operator.run(2, "京王電鉄");
  const line = db.prepare("INSERT INTO line (id, country_code, operator_id, name) VALUES (?, 'JP', ?, ?)");
  line.run("line-a", 1, "山手線");
  line.run("line-b", 1, "山手線");
  line.run("line-c", 1, "山手線");
  line.run("line-other", 1, "山手線2");
  line.run("line-keio", 2, "京王線");
  const interval = db.prepare('INSERT INTO "interval" (id, line_id) VALUES (?, ?)');
  const vertex = db.prepare("INSERT INTO interval_vertex (interval_id, seq, lon, lat) VALUES (?, 0, ?, ?)");
  interval.run(1, "line-a");
  vertex.run(1, 139, 35);
  interval.run(2, "line-b");
  vertex.run(2, 140, 36);
  interval.run(3, "line-c");
  vertex.run(3, 139, 35);
  interval.run(4, "line-other");
  vertex.run(4, 139, 35);
  interval.run(5, "line-keio");
  vertex.run(5, 139.5, 35.5);
  const entity = db.prepare("INSERT INTO registry_entity (id, kind, region, retired) VALUES (?, ?, 'jp', ?)");
  entity.run("lp:jp:1", "lp", null);
  entity.run("lp:jp:2", "lp", null);
  entity.run("lp:jp:3", "lp", "2020-01-01");
  entity.run("lp:jp:4", "lp", null);
  entity.run("op:jp:1", "op", null);
  entity.run("op:jp:9", "op", null);
  const ref = db.prepare("INSERT INTO external_ref (entity_id, scheme, value, valid_from) VALUES (?, ?, ?, NULL)");
  ref.run("lp:jp:1", "package-line", "line-a");
  ref.run("lp:jp:2", "package-line", "line-b");
  ref.run("lp:jp:3", "package-line", "line-c");
  ref.run("lp:jp:4", "package-line", "line-keio");
  ref.run("op:jp:1", "package-operator", "JR東日本");
  ref.run("op:jp:1", "package-operator", "京王電鉄");
  ref.run("op:jp:9", "package-operator", "京王電鉄");
  return db;
}

test("history crosswalk resolves unique, multiple, and unmatched package lines", () => {
  const db = openHistoryDb();
  try {
    const doc = buildHistoryCrosswalk(db, {
      retirements: [{
        history_id: "edge",
        match: { line_name: "山手線", operator: "JR東日本", bbox: [139, 35, 139, 35] },
        valid_to: "1990-01-01",
      }],
      identity_periods: [
        {
          history_id: "one",
          match: { line_name: "山手線", operator: "JR東日本", bbox: [138.9, 34.9, 139.1, 35.1] },
          valid_from: "2001-01-01",
          valid_to: "2010-01-01",
        },
        {
          history_id: "many",
          match: { line_name: "山手線", operator: "JR東日本", bbox: [138, 34, 141, 37] },
          valid_to: "2015-01-01",
        },
        {
          history_id: "none",
          match: { line_name: "山手線", operator: "JR東日本", bbox: [100, 0, 101, 1] },
        },
        {
          history_id: "numbered",
          match: { line_name: "山手線", operator: "JR東日本", bbox: [138.9, 34.9, 139.1, 35.1] },
        },
        {
          history_id: "other-operator",
          match: { line_name: "京王線", operator: "京王電鉄", bbox: [139, 35, 140, 36] },
          valid_from: "2000-01-01",
        },
      ],
    });
    const byId = new Map(doc.entries.map((entry) => [entry.history_id, entry]));
    assert.equal(doc.schema, "jtm-history-crosswalk/1");
    assert.deepEqual(doc.entries.map((entry) => entry.history_id), ["edge", "many", "none", "numbered", "one", "other-operator"]);
    assert.equal(byId.get("one").status, "unique");
    assert.deepEqual(byId.get("one").lp, ["lp:jp:1"]);
    assert.equal(byId.get("one").op, "op:jp:1");
    assert.equal(byId.get("one").kind, "identity_period");
    assert.equal(byId.get("edge").status, "unique");
    assert.equal(byId.get("edge").kind, "retirement");
    assert.deepEqual(byId.get("edge").lp, ["lp:jp:1"]);
    assert.equal(byId.get("many").status, "multiple");
    assert.deepEqual(byId.get("many").lp, ["lp:jp:1", "lp:jp:2"]);
    assert.equal(byId.get("none").status, "unmatched");
    assert.deepEqual(byId.get("none").lp, []);
    assert.equal(byId.get("numbered").status, "unique");
    assert.deepEqual(byId.get("numbered").lp, ["lp:jp:1"]);
    assert.equal(byId.get("other-operator").status, "unique");
    assert.equal(byId.get("other-operator").op, null);
  } finally {
    db.close();
  }
});

test("identity periods append operation events once and skip undated periods", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const crosswalk = {
      schema: "jtm-history-crosswalk/1",
      entries: [
        {
          history_id: "dated",
          kind: "identity_period",
          match: { line_name: "山手線", operator: "JR東日本", bbox: [139, 35, 140, 36] },
          valid_from: "2001-01-01",
          valid_to: "2010-01-01",
          lp: ["lp:jp:1"],
          op: "op:jp:1",
          status: "unique",
        },
        {
          history_id: "open",
          kind: "identity_period",
          match: { line_name: "中央線", operator: "JR東日本", bbox: [139, 35, 140, 36] },
          valid_to: "2012-04-01",
          lp: ["lp:jp:2"],
          op: "op:jp:1",
          status: "unique",
        },
        {
          history_id: "undated",
          kind: "identity_period",
          match: { line_name: "山手線", operator: "JR東日本", bbox: [139, 35, 140, 36] },
          lp: ["lp:jp:1"],
          op: "op:jp:1",
          status: "unique",
        },
        {
          history_id: "multi",
          kind: "identity_period",
          match: { line_name: "山手線", operator: "JR東日本", bbox: [139, 35, 140, 36] },
          valid_from: "1999-01-01",
          lp: ["lp:jp:1", "lp:jp:2"],
          op: "op:jp:1",
          status: "multiple",
        },
        {
          history_id: "missing",
          kind: "identity_period",
          match: { line_name: "無い線", operator: "JR東日本", bbox: [0, 0, 1, 1] },
          valid_from: "1999-01-01",
          lp: [],
          op: null,
          status: "unmatched",
        },
        {
          history_id: "retired-line",
          kind: "retirement",
          match: { line_name: "山手線", operator: "JR東日本", bbox: [139, 35, 140, 36] },
          valid_to: "1980-01-01",
          lp: ["lp:jp:1"],
          op: "op:jp:1",
          status: "unique",
        },
      ],
    };
    fs.mkdirSync(path.join(fixture.root, "jp"), { recursive: true });
    fs.writeFileSync(path.join(fixture.root, "jp", "history-crosswalk.json"), `${JSON.stringify(crosswalk, null, 2)}\n`);
    const minted = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(minted.status, 0, minted.stdout + minted.stderr);
    assert.equal(minted.stdout.includes("retire refused"), false);
    const ledger = readLedger(fixture.root);
    const operations = ledger.events.filter((event) => event.event === "operation" || event.event === "operation-end");
    assert.deepEqual(operations.map((event) => [event.event, event.id, event.on ?? null, event.why]), [
      ["operation", "lp:jp:1", "2001-01-01", "dated"],
      ["operation-end", "lp:jp:1", "2010-01-01", "dated"],
      ["operation", "lp:jp:2", null, "open"],
      ["operation-end", "lp:jp:2", "2012-04-01", "open"],
    ]);
    assert.equal(ledger.events.some((event) => event.why === "undated" || event.why === "retired-line" || event.why === "multi"), false);
    const report = JSON.parse(fs.readFileSync(path.join(fixture.root, "jp", "station-derivation-exceptions.json"), "utf8"));
    assert.deepEqual(report["history-period-undated"].map((row) => row.history_id), ["undated"]);
    assert.deepEqual(report["history-unresolved"].map((row) => [row.history_id, row.status]), [
      ["missing", "unmatched"],
      ["multi", "multiple"],
    ]);
    const before = snapshot(fixture.root);
    const again = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(again.status, 0, again.stdout + again.stderr);
    assert.match(again.stdout, /no changes/);
    sameSnapshot(before, snapshot(fixture.root));
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("overlapping operation intervals are rejected and adjacent ones are not", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    fs.writeFileSync(path.join(fixture.root, "jp", "history-crosswalk.json"), `${JSON.stringify({
      schema: "jtm-history-crosswalk/1",
      entries: [{
        history_id: "dated",
        kind: "identity_period",
        match: { line_name: "山手線", operator: "JR東日本", bbox: [139, 35, 140, 36] },
        valid_from: "2001-01-01",
        valid_to: "2010-01-01",
        lp: ["lp:jp:1"],
        op: "op:jp:1",
        status: "unique",
      }],
    })}\n`);
    const minted = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(minted.status, 0, minted.stdout + minted.stderr);
    const passed = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(passed.status, 0, passed.stdout + passed.stderr);

    const overlap = path.join(fixture.dir, "overlap");
    fs.cpSync(fixture.root, overlap, { recursive: true });
    const overlapping = canonical({
      id: "lp:jp:1", event: "operation", value: "op:jp:1", on: "2005-06-01", why: "clash", run: 2,
    }, KEY_ORDERS.event);
    fs.appendFileSync(path.join(overlap, "jp", "events.jsonl"), `${overlapping}\n`);
    const rejected = runNode(VALIDATE, ["--root", overlap, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(rejected.status, 1);
    assert.match(rejected.stdout, /operation overlap lp:jp:1/);

    const adjacent = path.join(fixture.dir, "adjacent");
    fs.cpSync(fixture.root, adjacent, { recursive: true });
    const nextStart = canonical({
      id: "lp:jp:1", event: "operation", value: "op:jp:1", on: "2010-01-01", why: "next", run: 2,
    }, KEY_ORDERS.event);
    const nextEnd = canonical({
      id: "lp:jp:1", event: "operation-end", value: "op:jp:1", on: "2020-01-01", why: "next", run: 2,
    }, KEY_ORDERS.event);
    fs.appendFileSync(path.join(adjacent, "jp", "events.jsonl"), `${nextStart}\n${nextEnd}\n`);
    const accepted = runNode(VALIDATE, ["--root", adjacent, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(accepted.status, 0, accepted.stdout + accepted.stderr);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("unequal overlapping identity periods are withheld on both sides and compensated", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const period = (historyId, from, to) => ({
      history_id: historyId,
      kind: "identity_period",
      match: { line_name: "山手線", operator: "JR東日本", bbox: [139, 35, 140, 36] },
      valid_from: from,
      valid_to: to,
      lp: ["lp:jp:1"],
      op: "op:jp:1",
      status: "unique",
    });
    const write = (entries) => {
      fs.writeFileSync(path.join(fixture.root, "jp", "history-crosswalk.json"), `${JSON.stringify({
        schema: "jtm-history-crosswalk/1", entries,
      }, null, 2)}\n`);
    };
    write([period("left", "2001-01-01", "2005-01-01"), period("right", "2005-01-01", "2010-01-01")]);
    const minted = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(minted.status, 0, minted.stdout + minted.stderr);
    write([period("left", "2001-01-01", "2010-01-01"), period("right", "2005-01-01", "2012-01-01")]);
    const compensated = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(compensated.status, 0, compensated.stdout + compensated.stderr);
    const ledger = readLedger(fixture.root);
    const operations = ledger.events.filter((event) => event.event === "operation");
    assert.deepEqual(operations.map((event) => [event.why, event.on]), [
      ["left", "2001-01-01"],
      ["right", "2005-01-01"],
    ]);
    const withdrawn = ledger.events.filter((event) => event.event === "operation-withdrawn");
    assert.deepEqual(withdrawn.map((event) => [event.id, event.value, event.on, event.why]), [
      ["lp:jp:1", "op:jp:1", "2001-01-01", "left"],
      ["lp:jp:1", "op:jp:1", "2005-01-01", "right"],
    ]);
    const report = JSON.parse(fs.readFileSync(path.join(fixture.root, "jp", "station-derivation-exceptions.json"), "utf8"));
    assert.deepEqual(report["history-unresolved"].map((row) => [row.history_id, row.status]), [
      ["left", "overlap"],
      ["right", "overlap"],
    ]);
    const passed = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(passed.status, 0, passed.stdout + passed.stderr);
    const hidden = path.join(fixture.dir, "hidden-overlap");
    fs.cpSync(fixture.root, hidden, { recursive: true });
    const clash = canonical({
      id: "lp:jp:1", event: "operation", value: "op:jp:1", on: "2004-01-01", why: "clash", run: 3,
    }, KEY_ORDERS.event);
    const withdrawnClash = canonical({
      id: "lp:jp:1", event: "operation-withdrawn", value: "op:jp:1", on: "2004-01-01", why: "clash", run: 3,
    }, KEY_ORDERS.event);
    fs.appendFileSync(path.join(hidden, "jp", "events.jsonl"), `${clash}\n${withdrawnClash}\n`);
    const ignored = runNode(VALIDATE, ["--root", hidden, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(ignored.status, 0, ignored.stdout + ignored.stderr);
    const before = snapshot(fixture.root);
    const again = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(again.status, 0, again.stdout + again.stderr);
    assert.match(again.stdout, /no changes/);
    sameSnapshot(before, snapshot(fixture.root));
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("a unique row with several line ids is multiple, not overlap", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    fs.writeFileSync(path.join(fixture.root, "jp", "history-crosswalk.json"), `${JSON.stringify({
      schema: "jtm-history-crosswalk/1",
      entries: [{
        history_id: "split",
        kind: "identity_period",
        match: { line_name: "山手線", operator: "JR東日本", bbox: [139, 35, 140, 36] },
        valid_from: "1990-01-01",
        lp: ["lp:jp:1", "lp:jp:2"],
        op: "op:jp:1",
        status: "unique",
      }],
    }, null, 2)}\n`);
    const minted = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(minted.status, 0, minted.stdout + minted.stderr);
    const report = JSON.parse(fs.readFileSync(path.join(fixture.root, "jp", "station-derivation-exceptions.json"), "utf8"));
    assert.deepEqual(report["history-unresolved"].map((row) => [row.history_id, row.status]), [["split", "multiple"]]);
    assert.equal(readLedger(fixture.root).events.some((event) => event.why === "split"), false);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("line_operation bounds the current operator and rejects overlaps", () => {
  const entities = ["lp:jp:1", "op:jp:1", "op:jp:2", "ln:jp:1"];
  const ledger = {
    entities: new Map(entities.map((id) => [id, { id }])),
    refs: [],
    events: [
      { id: "lp:jp:1", event: "line", value: "ln:jp:1" },
      { id: "lp:jp:1", event: "operation", value: "op:jp:1", on: "2001-01-01", why: "dated" },
      { id: "lp:jp:1", event: "operation-end", value: "op:jp:1", on: "2010-01-01", why: "dated" },
    ],
  };
  const changed = planLineOperationRows(ledger, [{ lp: "lp:jp:1", lineId: "ln:jp:1", operatorId: "op:jp:2" }]);
  assert.deepEqual(changed.omitted, []);
  assert.deepEqual(changed.rows.map((row) => [row.operatorId, row.validFrom, row.validTo]), [
    ["op:jp:1", "2001-01-01", "2010-01-01"],
    ["op:jp:2", "2010-01-01", null],
  ]);
  const same = planLineOperationRows(ledger, [{ lp: "lp:jp:1", lineId: "ln:jp:1", operatorId: "op:jp:1" }]);
  assert.deepEqual(same.rows.map((row) => row.operatorId), ["op:jp:1"]);
  const open = {
    ...ledger,
    events: [
      { id: "lp:jp:1", event: "operation", value: "op:jp:1", why: "open" },
    ],
  };
  const unclean = planLineOperationRows(open, [{ lp: "lp:jp:1", lineId: "lp:jp:1", operatorId: "op:jp:2" }]);
  assert.deepEqual(unclean.omitted, ["lp:jp:1"]);
  assert.equal(unclean.rows.some((row) => row.operatorId === "op:jp:2"), false);
  const bare = planLineOperationRows(
    { entities: ledger.entities, refs: [], events: [] },
    [{ lp: "lp:jp:1", lineId: "lp:jp:1", operatorId: "op:jp:1" }],
  );
  assert.deepEqual(bare.rows, [{
    lp: "lp:jp:1", lineId: "lp:jp:1", operatorId: "op:jp:1", role: "operator", validFrom: null, validTo: null,
  }]);
  const withdrawn = planLineOperationRows({
    entities: ledger.entities,
    refs: [],
    events: [
      ...ledger.events,
      { id: "lp:jp:1", event: "operation-withdrawn", value: "op:jp:1", on: "2001-01-01", why: "dated" },
    ],
  }, [{ lp: "lp:jp:1", lineId: "ln:jp:1", operatorId: "op:jp:1" }]);
  assert.deepEqual(withdrawn.rows.map((row) => [row.validFrom, row.validTo]), [[null, null]]);
  const grouped = planLineOperationRows(ledger, [
    { lp: "lp:jp:1", lineId: "ln:jp:1", operatorId: "op:jp:1" },
    { lp: "lp:jp:2", lineId: "ln:jp:1", operatorId: "op:jp:1" },
  ]);
  assert.deepEqual(grouped.omitted, []);
  assert.deepEqual(grouped.rows.map((row) => [row.lineId, row.operatorId, row.validFrom, row.validTo]), [
    ["ln:jp:1", "op:jp:1", "2001-01-01", "2010-01-01"],
  ]);
  const moved = planLineOperationRows(ledger, [
    { lp: "lp:jp:1", lineId: "ln:jp:1", operatorId: "op:jp:2" },
    { lp: "lp:jp:2", lineId: "ln:jp:1", operatorId: "op:jp:2" },
  ]);
  assert.deepEqual(moved.rows.map((row) => [row.operatorId, row.validFrom, row.validTo]), [
    ["op:jp:1", "2001-01-01", "2010-01-01"],
    ["op:jp:2", "2010-01-01", null],
  ]);
  const splitOps = planLineOperationRows({
    entities: new Map([...entities, "lp:jp:2"].map((id) => [id, { id }])),
    refs: [],
    events: [
      { id: "lp:jp:1", event: "line", value: "ln:jp:1" },
      { id: "lp:jp:2", event: "line", value: "ln:jp:1" },
    ],
  }, [
    { lp: "lp:jp:1", lineId: "ln:jp:1", operatorId: "op:jp:1" },
    { lp: "lp:jp:2", lineId: "ln:jp:1", operatorId: "op:jp:2" },
  ]);
  assert.deepEqual(splitOps.rows, []);
  assert.deepEqual(splitOps.omitted, ["lp:jp:1", "lp:jp:2"]);
  for (const planned of [changed, same, bare, withdrawn, grouped, moved]) {
    const intervals = planned.rows.map((row) => ({ from: row.validFrom, to: row.validTo }));
    for (let i = 0; i < intervals.length; i += 1) {
      for (let j = i + 1; j < intervals.length; j += 1) {
        assert.equal(operationIntervalsOverlap(intervals[i], intervals[j]), false);
      }
    }
  }

  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const minted = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(minted.status, 0, minted.stdout + minted.stderr);
    fixture.db.exec(`CREATE TABLE line_operation (
      line_id TEXT, operator_id TEXT, role TEXT, valid_from TEXT, valid_to TEXT
    )`);
    const insert = fixture.db.prepare("INSERT INTO line_operation (line_id, operator_id, role, valid_from, valid_to) VALUES (?, ?, 'operator', ?, ?)");
    insert.run("lp:jp:1", "op:jp:1", "2001-01-01", "2010-01-01");
    insert.run("lp:jp:1", "op:jp:2", "2005-01-01", "2012-01-01");
    const rejected = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(rejected.status, 1);
    assert.match(rejected.stdout, /line_operation overlap lp:jp:1/);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("history crosswalk equates a blank operator and matches station points", () => {
  const db = new DatabaseSync(":memory:");
  db.exec(`
    CREATE TABLE operator (id INTEGER PRIMARY KEY, country_code TEXT, name TEXT);
    CREATE TABLE line (id TEXT PRIMARY KEY, country_code TEXT, operator_id INTEGER, name TEXT);
    CREATE TABLE "interval" (id INTEGER PRIMARY KEY, line_id TEXT);
    CREATE TABLE interval_vertex (
      interval_id INTEGER, seq INTEGER, lon REAL, lat REAL,
      PRIMARY KEY (interval_id, seq)
    );
    CREATE TABLE line_station (
      line_id TEXT, seq INTEGER, station_id INTEGER, name TEXT, lon REAL, lat REAL,
      PRIMARY KEY (line_id, seq)
    );
    CREATE TABLE registry_entity (id TEXT PRIMARY KEY, kind TEXT, region TEXT, retired TEXT);
    CREATE TABLE external_ref (entity_id TEXT, scheme TEXT, value TEXT, valid_from TEXT);
  `);
  db.prepare("INSERT INTO operator (id, country_code, name) VALUES (1, 'JP', '')").run();
  db.prepare("INSERT INTO line (id, country_code, operator_id, name) VALUES ('line-blank', 'JP', 1, '空白線')").run();
  db.prepare('INSERT INTO "interval" (id, line_id) VALUES (1, ?)').run("line-blank");
  db.prepare("INSERT INTO interval_vertex (interval_id, seq, lon, lat) VALUES (1, 0, 0, 0)").run();
  db.prepare("INSERT INTO line_station (line_id, seq, station_id, name, lon, lat) VALUES (?, 0, 1, ?, ?, ?)").run(
    "line-blank", "駅A", 139.5, 35.5,
  );
  db.prepare("INSERT INTO registry_entity (id, kind, region, retired) VALUES ('lp:jp:1', 'lp', 'jp', NULL)").run();
  db.prepare("INSERT INTO external_ref (entity_id, scheme, value, valid_from) VALUES ('lp:jp:1', 'package-line', 'line-blank', NULL)").run();
  const match = {
    line_name: "空白線",
    operator: null,
    station_name: "駅A",
    targets: ["stations"],
    bbox: [139, 35, 140, 36],
  };
  try {
    const doc = buildHistoryCrosswalk(db, {
      identity_periods: [{ history_id: "station", match }],
      retirements: [],
    });
    assert.equal(doc.entries[0].status, "unique");
    assert.deepEqual(doc.entries[0].lp, ["lp:jp:1"]);
    assert.equal(doc.entries[0].match.operator, "");
    const empty = buildHistoryCrosswalk(db, {
      identity_periods: [{ history_id: "station", match: { ...match, operator: "" } }],
      retirements: [],
    });
    assert.deepEqual(empty.entries[0].lp, ["lp:jp:1"]);
    const vertices = buildHistoryCrosswalk(db, {
      identity_periods: [{
        history_id: "vertex",
        match: { line_name: "空白線", operator: "", bbox: [139, 35, 140, 36] },
      }],
      retirements: [],
    });
    assert.equal(vertices.entries[0].status, "unmatched");
  } finally {
    db.close();
  }
});

test("splitBracketName keeps one group and classifies status markers exactly", () => {
  const split = splitBracketName;
  assert.deepEqual(split("西鉄福岡（天神）"), {
    base: "西鉄福岡", bracket: "天神", kind: "subname", position: "suffix",
  });
  assert.deepEqual(split("西鉄福岡（天神） "), {
    base: "西鉄福岡", bracket: "天神", kind: "subname", position: "suffix",
  });
  assert.deepEqual(split("広島港（宇品）"), {
    base: "広島港", bracket: "宇品", kind: "subname", position: "suffix",
  });
  assert.deepEqual(split("粟島（大阪屋ショップ前）"), {
    base: "粟島", bracket: "大阪屋ショップ前", kind: "subname", position: "suffix",
  });
  assert.deepEqual(split("上環 (西港城) 總站"), {
    base: "上環 總站", bracket: "西港城", kind: "subname", position: "infix",
  });
  assert.deepEqual(split("上環  (西港城)  總站"), {
    base: "上環 總站", bracket: "西港城", kind: "subname", position: "infix",
  });
  assert.deepEqual(split("山景 (北)"), {
    base: "山景", bracket: "北", kind: "subname", position: "suffix",
  });
  assert.deepEqual(split("洞噶（预留）"), {
    base: "洞噶", bracket: "预留", kind: "status", position: "suffix", status: "reserved",
  });
  assert.equal(split("洞噶（預留）").status, "reserved");
  assert.equal(split("洞噶（预留站）").kind, "subname");
  assert.equal(split("駅（計画中）").status, "planned");
  assert.equal(split("駅（仮称）").status, "planned");
  assert.equal(split("駅（建設中）").status, "planned");
  assert.equal(split("旧駅（廃止）").status, "closed");
  assert.equal(split("站（廢止）").status, "closed");
  assert.equal(split("站（已关闭）").status, "closed");
  assert.deepEqual(split("Foo (Closed)"), {
    base: "Foo", bracket: "Closed", kind: "status", position: "suffix", status: "closed",
  });
  assert.equal(split("駅（運休）").status, "suspended");
  assert.equal(split("站（停运）").status, "suspended");
  assert.equal(split("駅（旧）").status, "historical");
  assert.equal(split("站（舊站）").status, "historical");
  assert.equal(split("駅〈旧〉").status, "historical");
  assert.equal(split("駅<old>").status, "historical");
  assert.equal(split("駅（FORMER）").status, "historical");
  assert.equal(split("駅（ 旧 ）").status, "historical");
  assert.equal(split("東京"), null);
  assert.equal(split("（预留）"), null);
  assert.equal(split("foo（ ）"), null);
  assert.equal(split("foo（bar"), null);
  assert.equal(split("a（b)"), null);
  assert.equal(split("a (b) (c)"), null);
  assert.equal(split("a（b（c））"), null);
  assert.equal(split("a〈b>"), null);
  for (const [status, words] of Object.entries(BRACKET_STATUS_MARKERS)) {
    for (const word of words) assert.equal(split(`駅（${word}）`).status, status, word);
  }
  assert.deepEqual(bracketNameRows("洞噶（预留）"), [
    { form: "base", value: "洞噶", status: null },
    { form: "bracket", value: "预留", status: "reserved" },
  ]);
  assert.deepEqual(bracketNameRows("西鉄福岡（天神）"), [
    { form: "base", value: "西鉄福岡", status: null },
    { form: "bracket", value: "天神", status: "subname" },
  ]);
  assert.deepEqual(bracketNameRows("a (b) (c)"), []);
});

test("bracketed names export deterministically and unsplit names are reported", () => {
  const fixture = openFixture();
  try {
    const insert = fixture.db.prepare("INSERT INTO station (id, country_code, code, name, name_norm, lon, lat) VALUES (?, 'JP', ?, ?, ?, 1, 1)");
    insert.run(3, "300", "西鉄福岡（天神）", "西鉄福岡（天神）");
    insert.run(4, "301", "西鉄福岡", "西鉄福岡");
    insert.run(5, "302", "洞噶（预留）", "洞噶（预留）");
    insert.run(6, "303", "a (b) (c)", "a (b) (c)");
    insert.run(7, "304", "（预留）", "（预留）");
    insert.run(8, "305", "旧駅（廃止）", "旧駅（廃止）");
    insert.run(9, "306", "元町（旧）", "元町（旧）");
    fixture.db.prepare("UPDATE line_station SET name = ? WHERE line_id = ? AND seq = ?").run("foo（bar", "jp-jr-yamanote", 0);
    fixture.db.prepare("UPDATE line_station SET name = ? WHERE line_id = ? AND seq = ?").run("上環 (西港城) 總站", "jp-jr-yamanote", 1);
    freeze(fixture.root);
    const minted = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(minted.status, 0, minted.stdout + minted.stderr);
    const exceptions = JSON.parse(fs.readFileSync(path.join(fixture.root, "jp", "station-derivation-exceptions.json"), "utf8"));
    assert.deepEqual(
      exceptions["bracket-name-unsplit"].map((row) => `${row.source}|${row.name}|${row.code}|${row.line ?? ""}`),
      [
        "line_station|foo（bar|100|jp-jr-yamanote",
        "station|a (b) (c)|303|",
        "station|（预留）|304|",
      ],
    );
    const out = path.join(fixture.dir, "bundle");
    const exported = runNode(EXPORT, ["--db", fixture.dbPath, "--root", fixture.root, "--out", out]);
    assert.equal(exported.status, 0, exported.stdout + exported.stderr);
    const file = path.join(out, "jp.json");
    const text = fs.readFileSync(file);
    const again = runNode(EXPORT, ["--db", fixture.dbPath, "--root", fixture.root, "--out", out]);
    assert.equal(again.status, 0, again.stdout + again.stderr);
    assert.ok(fs.readFileSync(file).equals(text));
    const check = runNode(EXPORT, ["--db", fixture.dbPath, "--root", fixture.root, "--out", out, "--check"]);
    assert.equal(check.status, 0, check.stdout + check.stderr);
    const bundle = JSON.parse(text.toString("utf8"));
    const names = bundle.bracketedNames;
    assert.deepEqual(Object.keys(names), Object.keys(names).slice().sort((a, b) => (a < b ? -1 : a > b ? 1 : 0)));
    assert.deepEqual(names["西鉄福岡（天神）"], {
      base: "西鉄福岡", bracket: "天神", kind: "subname", position: "suffix",
    });
    assert.equal("status" in names["西鉄福岡（天神）"], false);
    assert.deepEqual(names["洞噶（预留）"], {
      base: "洞噶", bracket: "预留", kind: "status", position: "suffix", status: "reserved",
    });
    assert.equal(names["旧駅（廃止）"].status, "closed");
    assert.equal(names["元町（旧）"].status, "historical");
    assert.deepEqual(names["上環 (西港城) 總站"], {
      base: "上環 總站", bracket: "西港城", kind: "subname", position: "infix",
    });
    assert.equal(names["a (b) (c)"], undefined);
    assert.equal(bundle.baseNameCounts["西鉄福岡"], 2);
    assert.equal(bundle.baseNameCounts["洞噶"], 1);
    assert.equal(bundle.baseNameCounts["旧駅"], 1);
    assert.equal(bundle.baseNameCounts["元町"], 1);
    assert.equal(bundle.baseNameCounts["上環 總站"], 0);
    assert.equal(Object.keys(bundle.baseNameCounts).includes("西鉄福岡"), true);
    assert.equal(bundle.baseNameCounts["東京"], undefined);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

function addKeioAtShinjuku(db) {
  db.prepare("INSERT INTO line (id, country_code, operator_id, name, line_code, railway_identity, interval_count) VALUES (?, ?, ?, ?, ?, ?, ?)")
    .run("jp-keio-line", "JP", 2, "京王線", "KO", null, 1);
  db.prepare("INSERT INTO line_station (line_id, seq, station_id, name, lon, lat) VALUES (?, ?, ?, ?, ?, ?)")
    .run("jp-keio-line", 0, 2, "新宿", 139.7, 35.689);
}

function writeFacilities(root, doc) {
  fs.mkdirSync(path.join(root, "jp"), { recursive: true });
  fs.writeFileSync(path.join(root, "jp", "station-facilities.json"), `${JSON.stringify(doc, null, 2)}\n`);
}

test("a reviewed facility mints once and loads facility rows", () => {
  const fixture = openFixture();
  try {
    addKeioAtShinjuku(fixture.db);
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    writeFacilities(fixture.root, {
      schema: "jtm-station-facilities/1",
      facilities: [{
        cx: "cx:jp:2",
        kind: "shared",
        stations: ["st:jp:3", "st:jp:2"],
        manager: "op:jp:1",
        sources: ["https://example.test/facility"],
        note: "共用",
        reviewedBy: "web-research 2026-10-19",
      }],
      links: [],
    });
    const minted = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(minted.status, 0, minted.stdout + minted.stderr);
    assert.equal(minted.stdout.includes("retire refused"), false);
    const ledger = readLedger(fixture.root);
    assert.equal(ledger.entities.get("fc:jp:1").slug, "shared");
    assert.equal(ledger.entities.get("fc:jp:1").parent, "cx:jp:2");
    assert.equal(refId(ledger, "facility", "cx:jp:2|st:jp:2,st:jp:3"), "fc:jp:1");
    assert.deepEqual(
      ledger.events.filter((event) => event.event === "facility").map((event) => event.id).sort(),
      ["st:jp:2", "st:jp:3"],
    );
    assert.equal(ledger.events.find((event) => event.event === "manager").value, "op:jp:1");
    const before = snapshot(fixture.root);
    const again = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(again.status, 0, again.stdout + again.stderr);
    assert.match(again.stdout, /no changes/);
    sameSnapshot(before, snapshot(fixture.root));
    const passed = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(passed.status, 0, passed.stdout + passed.stderr);
    const out = path.join(fixture.dir, "bundle");
    const exported = runNode(EXPORT, ["--db", fixture.dbPath, "--root", fixture.root, "--out", out, "--region", "jp"]);
    assert.equal(exported.status, 0, exported.stdout + exported.stderr);
    const bundle = JSON.parse(fs.readFileSync(path.join(out, "jp.json"), "utf8"));
    assert.deepEqual(bundle.facilities["fc:jp:1"], {
      stations: ["st:jp:2", "st:jp:3"],
      manager: "op:jp:1",
      kind: "shared",
    });
    assert.deepEqual(bundle.links, []);
    const sql = fs.readFileSync(path.resolve(HERE, "../build/rail-database/schema.sql"), "utf8");
    const slice = sql.slice(sql.indexOf("-- Identity registry")).replace(/CREATE VIEW[\s\S]*/, "");
    const db = new DatabaseSync(":memory:");
    db.exec(slice);
    loadRegistryTables(db, fixture.root);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM station_facility").get().n, 1);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM station_facility_member").get().n, 2);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM station_link").get().n, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM station_operator WHERE role = 'manager'").get().n, 2);
    assert.equal(db.prepare("SELECT source FROM station_facility").get().source, "https://example.test/facility");
    db.close();
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("facility and link violations are rejected", () => {
  const fixture = openFixture();
  try {
    addKeioAtShinjuku(fixture.db);
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const clean = path.join(fixture.dir, "clean");
    fs.cpSync(fixture.root, clean, { recursive: true });
    const reviewed = "web-research 2026-10-19";
    const base = {
      sources: ["https://example.test/facility"],
      note: "共用",
      reviewedBy: reviewed,
    };
    const linked = path.join(fixture.dir, "linked");
    fs.cpSync(clean, linked, { recursive: true });
    writeFacilities(linked, {
      schema: "jtm-station-facilities/1",
      facilities: [{
        cx: "cx:jp:2", kind: "shared", stations: ["st:jp:2", "st:jp:3"], manager: "op:jp:1", ...base,
      }],
      links: [{
        cx: "cx:jp:2", a: "st:jp:3", b: "st:jp:2", kind: "gate_transfer", ...base,
      }],
    });
    const sameFacility = runNode(MINT, ["--db", fixture.dbPath, "--root", linked, "--region", "jp", "--at", AT]);
    assert.equal(sameFacility.status, 0, sameFacility.stdout + sameFacility.stderr);
    const rejected = runNode(VALIDATE, ["--root", linked, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(rejected.status, 1);
    assert.match(rejected.stdout, /link facility st:jp:2/);

    const duplicate = path.join(fixture.dir, "duplicate-link");
    fs.cpSync(linked, duplicate, { recursive: true });
    const again = canonical({
      id: "st:jp:2", event: "link", value: "st:jp:3", why: "gate_transfer", run: 3,
    }, KEY_ORDERS.event);
    fs.appendFileSync(path.join(duplicate, "jp", "events.jsonl"), `${again}\n`);
    const dup = runNode(VALIDATE, ["--root", duplicate, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(dup.status, 1);
    assert.match(dup.stdout, /link duplicate st:jp:2/);

    const reversed = path.join(fixture.dir, "reversed-link");
    fs.cpSync(linked, reversed, { recursive: true });
    const backwards = canonical({
      id: "st:jp:3", event: "link", value: "st:jp:2", why: "gate_transfer", run: 3,
    }, KEY_ORDERS.event);
    fs.appendFileSync(path.join(reversed, "jp", "events.jsonl"), `${backwards}\n`);
    const order = runNode(VALIDATE, ["--root", reversed, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(order.status, 1);
    assert.match(order.stdout, /link order st:jp:3/);

    const parent = path.join(fixture.dir, "bad-parent");
    fs.cpSync(clean, parent, { recursive: true });
    fs.writeFileSync(path.join(parent, "jp", "station-facilities.json"), `${JSON.stringify({
      schema: "jtm-station-facilities/1",
      facilities: [{
        cx: "cx:jp:1", kind: "boundary", stations: ["st:jp:2", "st:jp:3"], manager: "op:jp:2", ...base,
      }],
      links: [],
    }, null, 2)}\n`);
    const parentMint = runNode(MINT, ["--db", fixture.dbPath, "--root", parent, "--region", "jp", "--at", AT]);
    assert.equal(parentMint.status, 0, parentMint.stdout + parentMint.stderr);
    const parentBad = runNode(VALIDATE, ["--root", parent, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(parentBad.status, 1);
    assert.match(parentBad.stdout, /facility member st:jp:2/);

    const twice = path.join(fixture.dir, "two-facilities");
    fs.cpSync(clean, twice, { recursive: true });
    fs.writeFileSync(path.join(twice, "jp", "station-facilities.json"), `${JSON.stringify({
      schema: "jtm-station-facilities/1",
      facilities: [
        { cx: "cx:jp:2", kind: "shared", stations: ["st:jp:2", "st:jp:3"], manager: "op:jp:1", ...base },
        { cx: "cx:jp:2", kind: "boundary", stations: ["st:jp:2"], manager: "op:jp:2", ...base },
      ],
      links: [],
    }, null, 2)}\n`);
    const twiceMint = runNode(MINT, ["--db", fixture.dbPath, "--root", twice, "--region", "jp", "--at", AT]);
    assert.equal(twiceMint.status, 0, twiceMint.stdout + twiceMint.stderr);
    const twiceBad = runNode(VALIDATE, ["--root", twice, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(twiceBad.status, 1);
    assert.match(twiceBad.stdout, /facility station st:jp:2/);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("operator alias text is exported and must not name another operator", () => {
  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const file = path.join(fixture.root, "jp", "operator-aliases.json");
    const write = (text, op) => {
      fs.writeFileSync(file, `${JSON.stringify({
        schema: "jtm-operator-aliases/1",
        aliases: [{ text, op, sources: ["https://example.test/alias"], note: "旧称", reviewedBy: "web-research 2026-10-19" }],
        multiple: [{ text: "JR東日本/京王電鉄", ops: ["op:jp:1", "op:jp:2"], sources: ["https://example.test/joint"], note: "併記", reviewedBy: "web-research 2026-10-19" }],
      }, null, 2)}\n`);
    };
    write("JR東別名", "op:jp:1");
    const out = path.join(fixture.dir, "bundle");
    const exported = runNode(EXPORT, ["--db", fixture.dbPath, "--root", fixture.root, "--out", out, "--region", "jp"]);
    assert.equal(exported.status, 0, exported.stdout + exported.stderr);
    const bundle = JSON.parse(fs.readFileSync(path.join(out, "jp.json"), "utf8"));
    assert.ok(bundle.operators["op:jp:1"].names.includes("JR東別名"));
    assert.equal(bundle.operators["op:jp:1"].names.includes("JR東日本/京王電鉄"), false);
    assert.equal(bundle.operators["op:jp:2"].names.includes("JR東日本/京王電鉄"), false);
    const passed = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(passed.status, 0, passed.stdout + passed.stderr);
    write("京王電鉄", "op:jp:1");
    const collided = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(collided.status, 1);
    assert.match(collided.stdout, /alias name 京王電鉄/);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});

test("reviewed history periods mint one operation per line and a changed start is withdrawn", () => {
  const unmatched = planHistoryCrosswalk([{
    history_id: "empty",
    kind: "identity_period",
    status: "reviewed",
    lp: [],
    op: "op:jp:1",
    valid_from: "2001-01-01",
  }]);
  assert.deepEqual(unmatched.unresolved.map((row) => [row.history_id, row.status]), [["empty", "unmatched"]]);

  const fixture = openFixture();
  try {
    freeze(fixture.root);
    const first = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(first.status, 0, first.stdout + first.stderr);
    const match = { line_name: "山手線", operator: "JR東日本", bbox: [139, 35, 140, 36] };
    const write = (entries) => {
      fs.writeFileSync(path.join(fixture.root, "jp", "history-crosswalk.json"), `${JSON.stringify({
        schema: "jtm-history-crosswalk/1", entries,
      }, null, 2)}\n`);
    };
    write([{
      history_id: "rename",
      kind: "identity_period",
      match,
      valid_to: "2012-01-01",
      lp: ["lp:jp:1"],
      op: "op:jp:1",
      status: "unique",
    }]);
    const opened = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(opened.status, 0, opened.stdout + opened.stderr);
    write([
      {
        history_id: "rename",
        kind: "identity_period",
        match,
        valid_from: "2011-03-01",
        valid_to: "2012-01-01",
        lp: ["lp:jp:1"],
        op: "op:jp:1",
        status: "reviewed",
      },
      {
        history_id: "both",
        kind: "identity_period",
        match,
        valid_from: "2015-03-14",
        valid_to: "2015-03-14",
        lp: ["lp:jp:1", "lp:jp:2"],
        op: "op:jp:1",
        status: "reviewed",
      },
      {
        history_id: "still-multi",
        kind: "identity_period",
        match,
        valid_from: "1990-01-01",
        lp: ["lp:jp:1", "lp:jp:2"],
        op: "op:jp:1",
        status: "unique",
      },
    ]);
    const reviewed = runNode(MINT, ["--db", fixture.dbPath, "--root", fixture.root, "--region", "jp", "--at", AT]);
    assert.equal(reviewed.status, 0, reviewed.stdout + reviewed.stderr);
    assert.equal(reviewed.stdout.includes("retire refused"), false);
    const ledger = readLedger(fixture.root);
    const withdrawn = ledger.events.filter((event) => event.event === "operation-withdrawn" && event.why === "rename");
    assert.equal(withdrawn.length, 1);
    assert.equal(withdrawn[0].on, undefined);
    const operations = ledger.events.filter((event) => event.event === "operation" && event.why === "both");
    assert.deepEqual(operations.map((event) => event.id).sort(), ["lp:jp:1", "lp:jp:2"]);
    assert.equal(ledger.events.some((event) => event.why === "still-multi"), false);
    const report = JSON.parse(fs.readFileSync(path.join(fixture.root, "jp", "station-derivation-exceptions.json"), "utf8"));
    assert.deepEqual(report["history-unresolved"].map((row) => [row.history_id, row.status]), [["still-multi", "multiple"]]);
    const passed = runNode(VALIDATE, ["--root", fixture.root, "--db", fixture.dbPath, "--no-base"]);
    assert.equal(passed.status, 1, passed.stdout + passed.stderr);
    assert.match(passed.stdout, /operation empty lp:jp:1/);
    assert.match(passed.stdout, /operation empty lp:jp:2/);
  } finally {
    fixture.db.close();
    fs.rmSync(fixture.dir, { recursive: true, force: true });
  }
});
