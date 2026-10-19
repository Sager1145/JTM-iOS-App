import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { KEY_ORDERS, appendLedger, canonical, mint, nextSeq, readLedger, reports } from "../build/rail-database/registry.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const MINT = path.resolve(HERE, "../build/mint-registry.mjs");
const VALIDATE = path.resolve(HERE, "validate-registry.mjs");
const AT = "2026-10-19";

function applySchema(db) {
  db.exec(`
    CREATE TABLE operator (
      id INTEGER PRIMARY KEY,
      country_code TEXT NOT NULL,
      name TEXT NOT NULL,
      short_name TEXT,
      display_label TEXT
    );
    CREATE TABLE line (
      id TEXT PRIMARY KEY,
      country_code TEXT NOT NULL,
      operator_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      line_code TEXT,
      railway_identity TEXT,
      interval_count INTEGER NOT NULL DEFAULT 0
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
