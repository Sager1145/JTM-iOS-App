#!/usr/bin/env node

// Exhaustive consistency audit for the Japanese sample and its line badges.
//
// This deliberately checks the runtime objects rather than the compact rows:
// compact `logo: 1` is only a download flag, while RailNetwork expands it to
// the actual parent badge path used by split lines and paired alignments.

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const appDirectory = path.resolve(scriptDirectory, "..", "..");
const repositoryDirectory = path.resolve(appDirectory, "..");
const require = createRequire(import.meta.url);
const RailNetwork = require(path.join(appDirectory, "public", "rail-network.js"));

function readJSON(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(repositoryDirectory, relativePath), "utf8"));
}

function loadBranding() {
  const source = fs.readFileSync(
    path.join(appDirectory, "public", "app-operator-branding.js"),
    "utf8",
  );
  return new Function("window", `${source}\nreturn RailOperatorBranding;`)({});
}

function publicAssetExists(webPath) {
  if (!webPath?.startsWith("/rail/")) return false;
  return fs.existsSync(path.join(appDirectory, "public", webPath.slice(1)));
}

const compactPackage = readJSON("app/public/rail/jp-2025.json");
const sample = readJSON("app/data/sample-data/sample-full.json");
const manifest = readJSON("app/data/sample-data/manifest.json");
const logoCredits = readJSON("app/public/rail/logo-credits.json");
const operatorSourceManifest = readJSON("app/public/rail/operator-logos/jp/manifest.json");
const operatorBadgeManifest = readJSON("app/public/rail/operator-logos/jp-badges/manifest.json");
const branding = loadBranding();
const network = RailNetwork.buildNetworkFromCompactPackage(compactPackage);
const solvedPartByTrainID = new Map(
  manifest.parts.map((partName) => {
    const part = readJSON(`app/data/sample-data/${partName}.json`);
    return [part.train.id, part];
  }),
);

const failures = [];
const unresolvedLines = [];
const sampleLineIDs = new Set();
const seenTrainIDs = new Set();
let sectionCount = 0;

if (!network) failures.push("jp-2025.json did not build into a runtime network");
if (manifest.total !== sample.trains.length)
  failures.push(`manifest total ${manifest.total} != ${sample.trains.length} trains`);
if (manifest.solved !== sample.trains.length || manifest.unsolvable !== 0 || manifest.no_route !== 0)
  failures.push("the Japanese sample manifest is not completely solved");
if (manifest.parts.length !== sample.trains.length)
  failures.push(`manifest has ${manifest.parts.length} parts for ${sample.trains.length} trains`);

for (const line of compactPackage.lines) {
  if (!line.logo) continue;
  const artworkLineID = line.id.replace(/(?:-p?\d+)+$/, "");
  if (!logoCredits[artworkLineID]) failures.push(`${line.id}: package logo has no source credit`);
  const artworkPath = `/rail/logos/${artworkLineID}.png`;
  if (!publicAssetExists(artworkPath)) failures.push(`${line.id}: missing package artwork ${artworkPath}`);
}

for (const entry of operatorSourceManifest) {
  if (entry.status !== "downloaded") continue;
  const assetPath = `/rail/operator-logos/jp/${entry.asset}`;
  if (!publicAssetExists(assetPath)) failures.push(`${entry.operator}: missing source asset ${assetPath}`);
  if (!entry.sourcePage) failures.push(`${entry.operator}: source manifest has no sourcePage`);
}

for (const entry of operatorBadgeManifest) {
  if (entry.sourceAsset.startsWith("/rail/") && !publicAssetExists(entry.sourceAsset))
    failures.push(`${entry.operator}: missing audited source ${entry.sourceAsset}`);
  if (!publicAssetExists(entry.runtimeAsset))
    failures.push(`${entry.operator}: missing audited runtime badge ${entry.runtimeAsset}`);
  const resolved = branding.operatorLogo(entry.operator);
  if (resolved !== entry.runtimeAsset)
    failures.push(
      `${entry.operator}: branding resolves ${resolved || "no logo"}, manifest requires ` +
        entry.runtimeAsset,
    );
}

for (const train of sample.trains) {
  if (seenTrainIDs.has(train.id)) failures.push(`${train.id}: duplicate train id`);
  seenTrainIDs.add(train.id);

  const sections = train.route_sections || [];
  if (!sections.length) failures.push(`${train.id}: no route_sections`);
  const solvedPart = solvedPartByTrainID.get(train.id);
  if (!solvedPart) failures.push(`${train.id}: no matching precomputed part`);

  for (const [index, section] of sections.entries()) {
    sectionCount += 1;
    const solvedFeatures = (solvedPart?.route?.features || []).filter(
      (feature) => feature.properties?.segment_index === index,
    );
    const solvedLineNames = new Set(
      solvedFeatures.flatMap((feature) => feature.properties.required_line_names || []),
    );
    const solvedOperatorNames = new Set(
      solvedFeatures.flatMap((feature) => feature.properties.required_operator_names || []),
    );
    const sectionLineNames = new Set(section.line_names || []);
    const sectionOperatorNames = new Set(section.operator_names || []);

    if (!solvedFeatures.length) {
      failures.push(`${train.id} section ${index + 1}: no solved route feature`);
      continue;
    }
    if (!sectionLineNames.size)
      failures.push(`${train.id} section ${index + 1}: missing line constraints`);
    for (const lineName of solvedLineNames)
      if (!sectionLineNames.has(lineName))
        failures.push(`${train.id} section ${index + 1}: missing solved line ${lineName}`);
    for (const operatorName of solvedOperatorNames)
      if (sectionOperatorNames.size && !sectionOperatorNames.has(operatorName))
        failures.push(`${train.id} section ${index + 1}: missing solved operator ${operatorName}`);

    const matchingLines = compactPackage.lines.filter(
      (line) =>
        solvedLineNames.has(line.name) &&
        (!solvedOperatorNames.size ||
          [...solvedOperatorNames].some(
            (name) => branding.companyLabel(name) === branding.companyLabel(line.operator),
          )),
    );
    if (!matchingLines.length) {
      failures.push(
        `${train.id} section ${index + 1}: solved identity does not match a package line ` +
          `[${[...solvedLineNames].join("/")}; ${[...solvedOperatorNames].join("/")}]`,
      );
      continue;
    }
    for (const candidate of matchingLines) sampleLineIDs.add(candidate.id);
  }
}

for (const line of network?.lineById.values() || []) {
  const logo = branding.logoForLine(line);
  if (!logo) {
    unresolvedLines.push(line.lineId);
    continue;
  }
  if (!publicAssetExists(logo)) failures.push(`${line.lineId}: missing resolved asset ${logo}`);

  const parentLineID = line.lineId.replace(/(?:-p?\d+)+$/, "");
  if (parentLineID !== line.lineId && line.logo) {
    const parentResolution = branding.logoForLine({ ...line, lineId: parentLineID });
    if (logo !== parentResolution)
      failures.push(
        `${line.lineId}: split line resolves ${logo}, but parent ${parentLineID} resolves ` +
          `${parentResolution || "no logo"}`,
      );
  }
}

// These operators do not publish a distinct usable mark in the audited source
// set. Keeping this tiny explicit allow-list makes any newly unbadged Japanese
// line a failing change instead of a silent colour-swatch fallback.
const intentionallyUnbadged = new Set([
  "jp-万葉線-新湊港線",
  "jp-万葉線-高岡軌道線",
  "jp-鞍馬寺-鞍馬山鋼索鉄道",
]);
for (const lineID of unresolvedLines)
  if (!intentionallyUnbadged.has(lineID)) failures.push(`${lineID}: no logo resolves`);
for (const lineID of intentionallyUnbadged)
  if (!unresolvedLines.includes(lineID))
    failures.push(`${lineID}: now resolves a logo; remove it from intentionallyUnbadged`);

if (failures.length) {
  console.error(`Japan sample/branding audit: ${failures.length} failure(s)`);
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exitCode = 1;
} else {
  console.log(
    `Japan sample/branding audit: ${sample.trains.length} trains, ` +
      `${sectionCount} route sections, ${sampleLineIDs.size} sample line records, ` +
      `${compactPackage.lines.length} package lines, and ` +
      `${compactPackage.lines.length - unresolvedLines.length} resolved logos verified`,
  );
  console.log(`  ${unresolvedLines.length} intentionally unbadged lines: ${unresolvedLines.join(", ")}`);
}
