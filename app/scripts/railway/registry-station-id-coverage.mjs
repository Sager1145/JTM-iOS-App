// Station-id coverage of the committed ride stores.
//
// Mirrors RegistryIdentityUpgrade: trim, NFKC, the Taiwan company table, and
// StationCodeAliases, then the fail-closed station and operator rules. It does
// not write operator_id or station_id back onto a ride.
//
// From app/: node scripts/railway/registry-station-id-coverage.mjs
// Stores: app/data/train-store*.json and app/data/sample-data*/**/train-store*.json
// Bundles: app/data/registry-bundle/<region>.json
// Report: docs/reports/registry/station-id-coverage-20261019.md

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const STORE_NAME = /^train-store(?:-([a-z]{2}))?\.json$/i;
const LINE_EMBEDDING = new Set(["MTR", "LR", "MLM"]);

// OperatorBranding.taiwanCompanyLabels. A spelling it does not list stays as it is.
const TAIWAN_COMPANY_LABELS = new Map([
  ["國營臺灣鐵路股份有限公司", "台鐵"],
  ["臺灣鐵路股份有限公司", "台鐵"],
  ["台灣鐵路股份有限公司", "台鐵"],
  ["交通部臺灣鐵路管理局", "台鐵"],
  ["臺灣鐵路管理局", "台鐵"],
  ["台灣鐵路管理局", "台鐵"],
  ["臺鐵", "台鐵"],
  ["台鐵", "台鐵"],
  ["台灣高速鐵路股份有限公司", "台灣高鐵"],
  ["臺灣高速鐵路股份有限公司", "台灣高鐵"],
  ["台灣高速鐵路", "台灣高鐵"],
  ["臺灣高速鐵路", "台灣高鐵"],
  ["臺灣高鐵", "台灣高鐵"],
  ["台灣高鐵", "台灣高鐵"],
  ["臺北大眾捷運股份有限公司", "台北捷運"],
  ["台北大眾捷運股份有限公司", "台北捷運"],
  ["臺北捷運", "台北捷運"],
  ["台北捷運", "台北捷運"],
  ["新北大眾捷運股份有限公司", "新北捷運"],
  ["新北捷運股份有限公司", "新北捷運"],
  ["新北捷運", "新北捷運"],
  ["桃園大眾捷運股份有限公司", "桃園捷運"],
  ["桃園捷運股份有限公司", "桃園捷運"],
  ["桃園捷運", "桃園捷運"],
  ["臺中捷運股份有限公司", "台中捷運"],
  ["台中捷運股份有限公司", "台中捷運"],
  ["臺中捷運", "台中捷運"],
  ["台中捷運", "台中捷運"],
  ["高雄捷運股份有限公司", "高雄捷運"],
  ["高雄捷運", "高雄捷運"],
  ["農業部林業及自然保育署阿里山林業鐵路及文化資產管理處", "阿里山林鐵"],
  ["農業部阿里山林業鐵路及文化資產管理處", "阿里山林鐵"],
  ["阿里山林業鐵路及文化資產管理處", "阿里山林鐵"],
  ["阿里山林業鐵路", "阿里山林鐵"],
  ["阿里山林鐵", "阿里山林鐵"],
]);

export function fileRegion(name) {
  const match = STORE_NAME.exec(name);
  if (!match) return null;
  return (match[1] || "jp").toLowerCase();
}

export function canonicalStationCode(code) {
  const segments = String(code).split("-");
  if (segments.length < 3) return String(code);
  const last = segments[segments.length - 1];
  const secondLast = segments[segments.length - 2];
  if (LINE_EMBEDDING.has(secondLast)) return `${secondLast}-${last}`;
  if (segments[0] === "TRAM") return `TRAM-${last}`;
  if (segments[1] === "NETWORK") {
    const kept = segments.slice();
    kept.splice(1, 1);
    return kept.join("-");
  }
  return String(code);
}

export function normalizeCompany(value, region) {
  const folded = String(value ?? "").trim().normalize("NFKC");
  if (String(region || "").toLowerCase() !== "tw") return folded;
  return folded
    .split("/")
    .map((part) => {
      const trimmed = part.trim();
      return TAIWAN_COMPANY_LABELS.get(trimmed) ?? trimmed;
    })
    .filter((part) => part !== "")
    .join("/");
}

function operatorNames(value) {
  if (Array.isArray(value)) return value;
  if (value && Array.isArray(value.names)) return value.names;
  return [];
}

export function resolveOperator(company, bundle) {
  if (company == null) return { kind: "none" };
  if (String(company).trim() === "") return { kind: "none" };
  const wanted = normalizeCompany(company, bundle.region);
  if (!wanted) return { kind: "none" };
  const matched = [];
  for (const [identifier, value] of Object.entries(bundle.operators ?? {})) {
    const hit = operatorNames(value).some(
      (name) => normalizeCompany(name, bundle.region) === wanted,
    );
    if (hit) matched.push(identifier);
  }
  if (matched.length === 1) return { kind: "unique", id: matched[0] };
  if (matched.length > 1) return { kind: "multiple" };
  return { kind: "unknown" };
}

export function resolveStation(code, operatorID, bundle) {
  const canonical = canonicalStationCode(code);
  const direct = bundle.stationCodes ?? {};
  if (Object.prototype.hasOwnProperty.call(direct, canonical)) {
    return { kind: "unique", id: direct[canonical] };
  }
  const groups = bundle.groupCodes ?? {};
  if (!Object.prototype.hasOwnProperty.call(groups, canonical)) return { kind: "unresolvable" };
  const candidates = groups[canonical] ?? [];
  if (candidates.length === 1) return { kind: "unique", id: candidates[0] };
  if (!operatorID) return { kind: "ambiguous" };
  const owners = bundle.stationOperator ?? {};
  const narrowed = candidates.filter((identifier) => owners[identifier] === operatorID);
  if (narrowed.length === 1) return { kind: "unique", id: narrowed[0] };
  return { kind: "ambiguous" };
}

function emptyStats() {
  return {
    stops: 0,
    withCode: 0,
    unique: 0,
    ambiguous: 0,
    unresolvable: 0,
    trainsWithCompany: 0,
    operatorUnique: 0,
    operatorMultiple: 0,
    operatorUnknown: 0,
  };
}

export function classify(trains, bundle) {
  const stats = emptyStats();
  const unresolved = new Map();
  for (const train of trains) {
    const company = train?.company ?? null;
    const operator = resolveOperator(company, bundle);
    if (operator.kind === "unique") stats.operatorUnique += 1;
    else if (operator.kind === "multiple") stats.operatorMultiple += 1;
    else if (operator.kind === "unknown") stats.operatorUnknown += 1;
    if (operator.kind !== "none") stats.trainsWithCompany += 1;
    const operatorID = operator.kind === "unique" ? operator.id : null;
    const stops = Array.isArray(train?.stops) ? train.stops : [];
    for (const stop of stops) {
      stats.stops += 1;
      const code = stop?.n02_station_code ?? stop?.n02StationCode ?? "";
      if (String(code) === "") continue;
      stats.withCode += 1;
      const resolved = resolveStation(code, operatorID, bundle);
      if (resolved.kind === "unique") {
        stats.unique += 1;
        continue;
      }
      if (resolved.kind === "ambiguous") stats.ambiguous += 1;
      else stats.unresolvable += 1;
      const name = String(stop?.name ?? "");
      const companyText = company == null ? "" : String(company);
      const key = `${name}\0${String(code)}\0${companyText}`;
      const row = unresolved.get(key) ?? { name, code: String(code), company: companyText, count: 0 };
      row.count += 1;
      unresolved.set(key, row);
    }
  }
  const top = [...unresolved.values()]
    .sort((a, b) => b.count - a.count
      || a.name.localeCompare(b.name)
      || a.code.localeCompare(b.code)
      || a.company.localeCompare(b.company))
    .slice(0, 20);
  return { stats, top };
}

export function listStoreFiles(dataDir) {
  const files = [];
  for (const name of fs.readdirSync(dataDir)) {
    const full = path.join(dataDir, name);
    if (fileRegion(name) && fs.statSync(full).isFile()) files.push(full);
    if (!name.startsWith("sample-data") || !fs.statSync(full).isDirectory()) continue;
    const stack = [full];
    while (stack.length) {
      const dir = stack.pop();
      for (const child of fs.readdirSync(dir)) {
        const childPath = path.join(dir, child);
        const stat = fs.statSync(childPath);
        if (stat.isDirectory()) stack.push(childPath);
        else if (fileRegion(child)) files.push(childPath);
      }
    }
  }
  return files.sort();
}

export function coverageByRegion(stores, bundles) {
  const grouped = new Map();
  for (const store of stores) {
    const fallback = fileRegion(path.basename(store.file)) || "jp";
    const trains = Array.isArray(store.document?.trains) ? store.document.trains : [];
    for (const train of trains) {
      const region = train?.region ? String(train.region).toLowerCase() : fallback;
      if (!grouped.has(region)) grouped.set(region, []);
      grouped.get(region).push(train);
    }
  }
  const regions = [...grouped.keys()].sort();
  return regions.map((region) => {
    const bundle = bundles.get(region) ?? { region, operators: {}, stationCodes: {}, groupCodes: {}, stationOperator: {} };
    const { stats, top } = classify(grouped.get(region), bundle);
    return { region, stats, top, bundleMissing: !bundles.has(region) };
  });
}

export function formatReport({ rows, storeFiles, sampleFiles, command }) {
  const lines = [
    "# Station-id coverage, 2026-10-19",
    "",
    "Measurement only. Ride stores are not rewritten.",
    "",
    `\`${command}\``,
    "",
    `Stores: ${storeFiles.length}. Sample-data stores: ${sampleFiles.length}.`,
    "",
    "| region | stops | with code | unique station | ambiguous | unresolvable | trains with company | unique operator | multiple | unknown |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  ];
  for (const row of rows) {
    const stats = row.stats;
    lines.push(`| ${row.region} | ${stats.stops} | ${stats.withCode} | ${stats.unique} | ${stats.ambiguous} | ${stats.unresolvable} | ${stats.trainsWithCompany} | ${stats.operatorUnique} | ${stats.operatorMultiple} | ${stats.operatorUnknown} |`);
  }
  lines.push("");
  for (const row of rows) {
    lines.push(`## ${row.region} unresolved`);
    lines.push("");
    if (row.bundleMissing) lines.push("No registry bundle for this region. Every coded stop is unresolvable.");
    if (!row.top.length) {
      lines.push("None.");
      lines.push("");
      continue;
    }
    lines.push("| count | name | code | company |");
    lines.push("| ---: | --- | --- | --- |");
    for (const item of row.top) {
      lines.push(`| ${item.count} | ${escapeCell(item.name)} | ${escapeCell(item.code)} | ${escapeCell(item.company)} |`);
    }
    lines.push("");
  }
  return `${lines.join("\n")}`;
}

function escapeCell(value) {
  return String(value).replace(/\|/g, "\\|").replace(/\n/g, " ");
}

export function repoRoot() {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
}

export function loadCoverage(root = repoRoot()) {
  const dataDir = path.join(root, "app", "data");
  const files = listStoreFiles(dataDir);
  const stores = files.map((file) => ({
    file,
    document: JSON.parse(fs.readFileSync(file, "utf8")),
  }));
  const bundles = new Map();
  const bundleDir = path.join(dataDir, "registry-bundle");
  if (fs.existsSync(bundleDir)) {
    for (const name of fs.readdirSync(bundleDir)) {
      if (!name.endsWith(".json")) continue;
      const document = JSON.parse(fs.readFileSync(path.join(bundleDir, name), "utf8"));
      if (document?.region) bundles.set(String(document.region).toLowerCase(), document);
    }
  }
  return {
    files,
    sampleFiles: files.filter((file) => file.includes(`${path.sep}sample-data`)),
    stores,
    bundles,
  };
}

export function writeCoverageReport(root = repoRoot()) {
  const loaded = loadCoverage(root);
  const rows = coverageByRegion(loaded.stores, loaded.bundles);
  const command = "node scripts/railway/registry-station-id-coverage.mjs";
  const markdown = formatReport({
    rows,
    storeFiles: loaded.files,
    sampleFiles: loaded.sampleFiles,
    command,
  });
  const destination = path.join(root, "docs", "reports", "registry", "station-id-coverage-20261019.md");
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, markdown);
  return { destination, rows, files: loaded.files, sampleFiles: loaded.sampleFiles };
}

const invoked = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invoked) {
  const result = writeCoverageReport();
  console.log(result.destination);
  for (const row of result.rows) {
    console.log(row.region, JSON.stringify(row.stats));
  }
}
