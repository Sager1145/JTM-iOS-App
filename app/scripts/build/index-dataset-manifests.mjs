// Add or check manifest train identities using existing parts, without solving routes.
// Run from any directory: node app/scripts/build/index-dataset-manifests.mjs [--check]
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dataDir = fileURLToPath(new URL("../../data/", import.meta.url));
const check = process.argv.includes("--check");
const directories = fs.readdirSync(dataDir).filter((name) =>
  name.startsWith("sample-data") || name.endsWith("loop-data"));
let partCount = 0;
let manifestCount = 0;
for (const directory of directories) {
  const manifestPath = path.join(dataDir, directory, "manifest.json");
  if (!fs.existsSync(manifestPath)) continue;
  const source = fs.readFileSync(manifestPath, "utf8");
  const manifest = JSON.parse(source);
  const identities = Object.create(null);
  for (const name of manifest.parts) {
    const part = JSON.parse(fs.readFileSync(path.join(dataDir, directory, `${name}.json`), "utf8"));
    if (typeof part.train?.id !== "string" || !part.train.id.trim()) {
      throw new Error(`${directory}/${name} requires a nonempty train.id.`);
    }
    identities[name] = part.train.id;
    partCount += 1;
  }
  if (check || manifest.part_train_ids !== undefined) {
    const actual = manifest.part_train_ids;
    if (!actual || typeof actual !== "object" || Array.isArray(actual) ||
        Object.keys(actual).length !== Object.keys(identities).length ||
        Object.entries(identities).some(([name, id]) => actual[name] !== id)) {
      throw new Error(`${directory}/manifest.json has missing or incorrect train identities.`);
    }
  } else {
    // Insert only the optional field, preserving every existing byte of content.
    const end = source.lastIndexOf("}");
    const before = source.slice(0, end).trimEnd();
    const field = JSON.stringify(identities, null, 2).replace(/\n/g, "\n  ");
    fs.writeFileSync(manifestPath, `${before},\n  "part_train_ids": ${field}\n}${source.slice(end + 1)}`);
  }
  manifestCount += 1;
}
console.log(`${check ? "Checked" : "Indexed"} ${manifestCount} manifests and ${partCount} parts.`);
