#!/usr/bin/env node

// Backfill route-section identities from the already-solved Japanese sample.
// The affected imports had station pairs but omitted line_names entirely;
// two Kokura intervals also recorded only one of two coincident legal lines.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const appDirectory = path.resolve(scriptDirectory, "..", "..");
const dataDirectory = path.join(appDirectory, "data");
const storePath = path.join(dataDirectory, "train-store.json");
const sampleDirectory = path.join(dataDirectory, "sample-data");
const manifest = JSON.parse(fs.readFileSync(path.join(sampleDirectory, "manifest.json"), "utf8"));
const store = JSON.parse(fs.readFileSync(storePath, "utf8"));

const partByTrainID = new Map(
  manifest.parts.map((partName) => {
    const part = JSON.parse(
      fs.readFileSync(path.join(sampleDirectory, `${partName}.json`), "utf8"),
    );
    return [part.train.id, part];
  }),
);

function mergeUnique(current, additions) {
  return [...new Set([...(current || []), ...additions])];
}

let changedSections = 0;
for (const train of store.trains) {
  const part = partByTrainID.get(train.id);
  if (!part) throw new Error(`${train.id}: no solved sample part`);

  for (const [index, section] of (train.route_sections || []).entries()) {
    const features = (part.route?.features || []).filter(
      (feature) => feature.properties?.segment_index === index,
    );
    if (!features.length) throw new Error(`${train.id} section ${index + 1}: no solved feature`);

    const solvedLines = [
      ...new Set(features.flatMap((feature) => feature.properties.required_line_names || [])),
    ];
    const solvedOperators = [
      ...new Set(features.flatMap((feature) => feature.properties.required_operator_names || [])),
    ];
    const nextLines = mergeUnique(section.line_names, solvedLines);
    const nextOperators = mergeUnique(section.operator_names, solvedOperators);
    const linesChanged = JSON.stringify(nextLines) !== JSON.stringify(section.line_names || []);
    const operatorsChanged =
      solvedOperators.length > 0 &&
      JSON.stringify(nextOperators) !== JSON.stringify(section.operator_names || []);

    if (!linesChanged && !operatorsChanged) continue;
    if (linesChanged) section.line_names = nextLines;
    if (operatorsChanged) section.operator_names = nextOperators;
    changedSections += 1;
  }
}

fs.writeFileSync(storePath, `${JSON.stringify(store, null, 2)}\n`);
console.log(`repaired route constraints in ${changedSections} Japanese sample sections`);
