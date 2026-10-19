#!/usr/bin/env node
// Turn sourced web-research dumps into reviewed P1 registry inputs.
// Decisions stay in the research files; this only shapes them for the minter.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { compareId, compareText, readLedger } from "../build/rail-database/registry.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const APP_DIR = path.resolve(HERE, "..", "..");
export const REVIEWED_BY = "web-research 2026-10-19";
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

const OPERATOR_SLUG = {
  "えちごトキめき鉄道": "echigo-tokimeki",
  "九州旅客鉄道": "jr-kyushu",
  "北海道旅客鉄道": "jr-hokkaido",
  "南海電気鉄道": "nankai",
  "四国旅客鉄道": "jr-shikoku",
  "富山地方鉄道": "toyama-chiho",
  "山万": "yamaman",
  "東京都": "toei",
  "東日本旅客鉄道": "jr-east",
  "東武鉄道": "tobu",
  "東海旅客鉄道": "jr-central",
  "神戸新交通": "kobe-new-transit",
  "福井鉄道": "fukui-railway",
  "立山黒部貫光": "tateyama-kurobe",
  "西日本旅客鉄道": "jr-west",
  "豊橋鉄道": "toyohashi-railway",
  "阪急電鉄": "hankyu",
};

const LINE_SLUG = {
  "日本海ひすいライン": "nihonkai-hisui",
  "日豊線": "nippo",
  "筑肥線": "chikuhi",
  "長崎線": "nagasaki",
  "鹿児島線": "kagoshima",
  "函館線": "hakodate",
  "千歳線": "chitose",
  "室蘭線": "muroran",
  "根室線": "nemuro",
  "高野線": "koya",
  "予讃線": "yosan",
  "本線": "main",
  "ユーカリが丘線": "yukarigaoka",
  "12号線大江戸線": "oedo",
  "上越線": "joetsu",
  "中央線": "chuo",
  "京葉線": "keiyo",
  "信越線": "shinetsu",
  "南武線": "nambu",
  "山手線": "yamanote",
  "奥羽線": "ou",
  "成田線": "narita",
  "水郡線": "suigun",
  "総武線": "sobu",
  "羽越線": "uetsu",
  "鶴見線": "tsurumi",
  "伊勢崎線": "isesaki",
  "小泉線": "koizumi",
  "東海道線": "tokaido",
  "ポートアイランド線": "port-island",
  "福武線": "fukubu",
  "鋼索線": "cable",
  "北陸線": "hokuriku",
  "小野田線": "onoda",
  "山陰線": "sanin",
  "山陽線": "sanyo",
  "阪和線": "hanwa",
  "東田本線": "azumada",
  "今津線": "imazu",
  "東北線": "tohoku",
};

function pretty(doc) {
  return `${JSON.stringify(doc, null, 2)}\n`;
}

function sourcesOf(row) {
  return Array.isArray(row?.sources) ? row.sources.map(String) : [];
}

function lpKey(lpIds) {
  return [...(lpIds ?? [])].map(String).sort(compareId).join(",");
}

function lineSlug(operator, officialName) {
  const op = OPERATOR_SLUG[operator];
  const line = LINE_SLUG[officialName];
  if (!op || !line) throw new Error(`no slug for ${operator} / ${officialName}`);
  return `${op}/${line}`;
}

export function buildLineGroups(records) {
  const byKey = new Map();
  for (const row of records ?? []) {
    if (!row || byKey.has(row.key)) continue;
    byKey.set(row.key, row);
  }
  const pending = [];
  for (const row of byKey.values()) {
    if (row.decision === "not-a-railway" || row.decision === "unverified" || row.decision == null) continue;
    if (row.decision !== "one-line" && row.decision !== "split") continue;
    const researchGroups = Array.isArray(row.groups) ? row.groups : [];
    const chosen = row.decision === "one-line" ? researchGroups.slice(0, 1) : researchGroups;
    for (const group of chosen) {
      const lp = Array.isArray(group.lp) ? group.lp.map(String).sort(compareId) : [];
      pending.push({
        base: lineSlug(group.operator, group.officialName),
        lp,
        why: String(row.note ?? ""),
        source: sourcesOf(row).join(" "),
        sources: sourcesOf(row),
        note: String(row.note ?? ""),
      });
    }
  }
  const buckets = new Map();
  for (const item of pending) {
    if (!buckets.has(item.base)) buckets.set(item.base, []);
    buckets.get(item.base).push(item);
  }
  const groups = [];
  for (const [base, items] of buckets) {
    items.sort((a, b) => compareText(lpKey(a.lp), lpKey(b.lp)));
    items.forEach((item, index) => {
      groups.push({
        slug: index === 0 ? base : `${base}-${index + 1}`,
        lp: item.lp,
        why: item.why,
        source: item.source,
        sources: item.sources,
        note: item.note,
        reviewedBy: REVIEWED_BY,
      });
    });
  }
  groups.sort((a, b) => compareText(a.slug, b.slug) || compareText(lpKey(a.lp), lpKey(b.lp)));
  return { schema: "jtm-line-crosswalk/1", groups };
}

export function indexFromLedger(ledger, region) {
  const retired = new Set(ledger.events.filter((event) => event.event === "retire").map((event) => event.id));
  const live = (id) => ledger.entities.has(id) && !retired.has(id) && String(id).split(":")[1] === region;
  const opByName = new Map();
  const stByDeriv = new Map();
  const stationsByCx = new Map();
  for (const ref of ledger.refs) {
    if (!live(ref.id)) continue;
    if (ref.scheme === "package-operator" && String(ref.id).startsWith("op:")) {
      if (!opByName.has(ref.value)) opByName.set(ref.value, new Set());
      opByName.get(ref.value).add(ref.id);
    }
    if (ref.scheme === "derivation" && String(ref.id).startsWith("st:") && !ref.from) {
      if (!stByDeriv.has(ref.value)) stByDeriv.set(ref.value, new Set());
      stByDeriv.get(ref.value).add(ref.id);
      const cx = String(ref.value).split("|")[0];
      if (!stationsByCx.has(cx)) stationsByCx.set(cx, new Set());
      stationsByCx.get(cx).add(ref.id);
    }
  }
  const nameToOp = new Map();
  for (const [name, ids] of opByName) nameToOp.set(name, ids.size === 1 ? [...ids][0] : null);
  const derivToSt = new Map();
  for (const [value, ids] of stByDeriv) derivToSt.set(value, ids.size === 1 ? [...ids][0] : null);
  return { nameToOp, derivToSt, stationsByCx };
}

function resolveName(index, name) {
  if (!name) return { ok: false, reason: "missing name" };
  if (!index.nameToOp.has(name)) return { ok: false, reason: `unknown operator ${name}` };
  const op = index.nameToOp.get(name);
  if (!op) return { ok: false, reason: `ambiguous operator ${name}` };
  return { ok: true, op };
}

function resolveStation(index, cx, op) {
  const value = `${cx}|${op}`;
  if (!index.derivToSt.has(value)) return { ok: false, reason: `unknown station ${value}` };
  const st = index.derivToSt.get(value);
  if (!st) return { ok: false, reason: `ambiguous station ${value}` };
  return { ok: true, st };
}

function linkKind(transfer) {
  if (transfer === "gate") return "gate_transfer";
  if (transfer === "street") return "street_transfer";
  return null;
}

export function buildStationFacilities(records, index) {
  const facilities = [];
  const links = [];
  const unresolved = [];
  const mixed = [];
  const seenCx = new Set();
  for (const row of records ?? []) {
    const decision = row?.decision ?? null;
    if (decision == null || decision === "unverified") continue;
    const facilityDecision = decision === "shared-facility" || decision === "boundary";
    const separate = decision === "separate-stations";
    if (!facilityDecision && !separate) continue;
    const cx = String(row.cx ?? "");
    if (row.transfer === "mixed") {
      mixed.push({
        cx,
        name: String(row.name ?? ""),
        decision,
        note: String(row.note ?? ""),
      });
    }
    if (seenCx.has(cx)) {
      unresolved.push({ cx, name: String(row.name ?? ""), decision, reason: "duplicate cx" });
      continue;
    }
    seenCx.add(cx);
    let members = new Set();
    if (facilityDecision) {
      const sharedBy = Array.isArray(row.sharedBy) ? row.sharedBy : [];
      const stations = [];
      let failed = null;
      for (const company of sharedBy) {
        const op = resolveName(index, company);
        if (!op.ok) {
          failed = op.reason;
          break;
        }
        const st = resolveStation(index, cx, op.op);
        if (!st.ok) {
          failed = st.reason;
          break;
        }
        stations.push(st.st);
      }
      const manager = resolveName(index, row.manager);
      if (!failed && !manager.ok) failed = manager.reason;
      if (!failed && new Set(stations).size !== stations.length) failed = "duplicate station";
      if (!failed && stations.length < 2) failed = "fewer than two stations";
      if (failed) {
        unresolved.push({ cx, name: String(row.name ?? ""), decision, reason: failed });
        continue;
      }
      const sorted = stations.sort(compareId);
      members = new Set(sorted);
      facilities.push({
        cx,
        kind: decision === "boundary" ? "boundary" : "shared",
        stations: sorted,
        manager: manager.op,
        sources: sourcesOf(row),
        note: String(row.note ?? ""),
        reviewedBy: REVIEWED_BY,
      });
    }
    const kind = linkKind(row.transfer);
    if (!kind) continue;
    const stations = [...(index.stationsByCx.get(cx) ?? [])].sort(compareId);
    for (let i = 0; i < stations.length; i += 1) {
      for (let j = i + 1; j < stations.length; j += 1) {
        const a = stations[i];
        const b = stations[j];
        if (members.has(a) && members.has(b)) continue;
        links.push({
          cx,
          a,
          b,
          kind,
          sources: sourcesOf(row),
          note: String(row.note ?? ""),
          reviewedBy: REVIEWED_BY,
        });
      }
    }
  }
  facilities.sort((a, b) => compareId(a.cx, b.cx) || compareText(a.stations.join(","), b.stations.join(",")));
  links.sort((a, b) => compareId(a.a, b.a) || compareId(a.b, b.b) || compareText(a.kind, b.kind));
  unresolved.sort((a, b) => compareId(a.cx, b.cx) || compareText(a.reason, b.reason));
  mixed.sort((a, b) => compareId(a.cx, b.cx) || compareText(a.name, b.name));
  return {
    doc: { schema: "jtm-station-facilities/1", facilities, links },
    report: { "facility-unresolved": unresolved, "facility-transfer-mixed": mixed },
  };
}

function dateField(value) {
  return typeof value === "string" && ISO_DATE.test(value) ? value : null;
}

export function buildOperatorAliases(doc) {
  const aliases = [];
  const multiple = [];
  const seenAlias = new Set();
  const seenMultiple = new Set();
  for (const row of doc?.companies ?? []) {
    const text = String(row.company ?? "");
    const ops = Array.isArray(row.ops) ? row.ops.map(String).sort(compareId) : [];
    const entry = {
      text,
      sources: sourcesOf(row),
      note: String(row.note ?? ""),
      reviewedBy: REVIEWED_BY,
    };
    if (row.decision === "alias") {
      if (ops.length !== 1 || seenAlias.has(text)) continue;
      seenAlias.add(text);
      aliases.push({ text, op: ops[0], sources: entry.sources, note: entry.note, reviewedBy: REVIEWED_BY });
    } else if (row.decision === "multiple") {
      if (ops.length < 2 || seenMultiple.has(text)) continue;
      seenMultiple.add(text);
      multiple.push({ text, ops, sources: entry.sources, note: entry.note, reviewedBy: REVIEWED_BY });
    }
  }
  aliases.sort((a, b) => compareText(a.text, b.text) || compareId(a.op, b.op));
  multiple.sort((a, b) => compareText(a.text, b.text));
  return { schema: "jtm-operator-aliases/1", aliases, multiple };
}

export function buildHistoryOverrides(doc) {
  const overrides = [];
  const seen = new Set();
  for (const row of doc?.history ?? []) {
    if (row?.decision !== "fix") continue;
    const historyId = String(row.history_id ?? "");
    if (!historyId || seen.has(historyId)) continue;
    seen.add(historyId);
    const item = {
      history_id: historyId,
      lp: Array.isArray(row.lp) ? row.lp.map(String).sort(compareId) : [],
      op: String(row.op ?? ""),
    };
    const validFrom = dateField(row.valid_from);
    const validTo = dateField(row.valid_to);
    if (validFrom) item.valid_from = validFrom;
    if (validTo) item.valid_to = validTo;
    item.sources = sourcesOf(row);
    item.note = String(row.note ?? "");
    item.reviewedBy = REVIEWED_BY;
    overrides.push(item);
  }
  overrides.sort((a, b) => compareText(a.history_id, b.history_id));
  return { schema: "jtm-history-overrides/1", overrides };
}

function parseArgs(argv) {
  const scratch = path.resolve(APP_DIR, "..", "..", "research");
  const options = {
    ledger: path.join(APP_DIR, "data", "registry"),
    lines: path.join(scratch, "out-line-family.json"),
    facilities: [
      path.join(scratch, "out-facility-0.json"),
      path.join(scratch, "out-facility-1.json"),
      path.join(scratch, "out-facility-2.json"),
    ],
    companies: path.join(scratch, "out-company-history.json"),
    out: path.join(APP_DIR, "data", "registry", "jp"),
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--ledger") options.ledger = path.resolve(argv[++index]);
    else if (argument === "--lines") options.lines = path.resolve(argv[++index]);
    else if (argument === "--facilities") options.facilities = argv[++index].split(",").map((item) => path.resolve(item));
    else if (argument === "--companies") options.companies = path.resolve(argv[++index]);
    else if (argument === "--out") options.out = path.resolve(argv[++index]);
    else throw new Error(`unknown option: ${argument}`);
  }
  return options;
}

function writeReviewed(dir, name, doc) {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, name), pretty(doc));
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const lineRecords = JSON.parse(fs.readFileSync(options.lines, "utf8"));
  const facilityRecords = options.facilities.flatMap((file) => JSON.parse(fs.readFileSync(file, "utf8")));
  const companies = JSON.parse(fs.readFileSync(options.companies, "utf8"));
  const ledger = readLedger(options.ledger);
  const lines = buildLineGroups(lineRecords);
  const facilities = buildStationFacilities(facilityRecords, indexFromLedger(ledger, "jp"));
  const aliases = buildOperatorAliases(companies);
  const overrides = buildHistoryOverrides(companies);
  writeReviewed(options.out, "line-crosswalk.json", lines);
  writeReviewed(options.out, "station-facilities.json", facilities.doc);
  writeReviewed(options.out, "operator-aliases.json", aliases);
  writeReviewed(options.out, "history-overrides.json", overrides);
  writeReviewed(options.out, "facility-review-report.json", facilities.report);
  const gate = facilities.doc.links.filter((link) => link.kind === "gate_transfer").length;
  const street = facilities.doc.links.filter((link) => link.kind === "street_transfer").length;
  console.log(`groups=${lines.groups.length} facilities=${facilities.doc.facilities.length} links=${facilities.doc.links.length} gate=${gate} street=${street}`);
  console.log(`aliases=${aliases.aliases.length} multiple=${aliases.multiple.length} overrides=${overrides.overrides.length}`);
  console.log(`facility-unresolved=${facilities.report["facility-unresolved"].length} facility-transfer-mixed=${facilities.report["facility-transfer-mixed"].length}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
