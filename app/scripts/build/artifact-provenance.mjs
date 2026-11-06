// Revision stamps for generated artifacts (port fixtures, Swift expectations).
// A stamp records what the artifact was generated FROM, so a stale artifact is
// reported as "input X changed" instead of an opaque content diff.
// No timestamps: a regeneration over unchanged inputs is byte-identical.

import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export const PROVENANCE_FORMAT = "jtm-artifact-provenance/1";

export function sha256File(file) {
  return createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

export function jsRouteSolverCacheVersion(appDir) {
  const source = fs.readFileSync(path.join(appDir, "public", "app-config.js"), "utf8");
  const match = source.match(/const\s+ROUTE_SOLVER_CACHE_VERSION\s*=\s*["']([^"']+)["']/);
  if (!match) throw new Error("Cannot read ROUTE_SOLVER_CACHE_VERSION from app-config.js");
  return match[1];
}

/**
 * @param {string[]} inputs repo-relative paths (forward slashes)
 */
export function artifactProvenance({ repoDir, appDir, generator, regenerate, inputs, solverDependent = false }) {
  const paths = [...new Set(inputs)].sort();
  const hashes = {};
  const historyRevisions = {};
  for (const rel of paths) {
    const file = path.join(repoDir, rel);
    if (!fs.existsSync(file)) throw new Error(`Provenance input is missing: ${rel}`);
    hashes[rel] = sha256File(file);
    const history = rel.match(/^app\/data\/rail-history(?:-([a-z]{2}))?\.json$/);
    if (history) {
      const revision = JSON.parse(fs.readFileSync(file, "utf8"))?.revision;
      if (typeof revision !== "string" || !revision.trim()) throw new Error(`${rel} has no revision`);
      historyRevisions[history[1] ?? "jp"] = revision;
    }
  }
  return {
    format: PROVENANCE_FORMAT,
    generator,
    regenerate,
    ...(solverDependent ? { engine: { js_route_solver_cache_version: jsRouteSolverCacheVersion(appDir) } } : {}),
    history_revisions: historyRevisions,
    inputs: hashes,
  };
}
