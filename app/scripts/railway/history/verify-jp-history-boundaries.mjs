#!/usr/bin/env node
/**
 * Verify every effective validity transition in the compiled Japan history.
 *
 * The verifier evaluates the production Web loader and route-validity helper
 * in a Node VM. It applies every retirement to the current sections/stations,
 * appends the overlay, then generates day-before/day-of fixtures from every
 * actual service-validity boundary in that resulting dataset.
 *
 * This is a loader/availability check. It does not invoke the route solver or
 * either client's final display pipeline.
 */

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import vm from "node:vm";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../../../..");

function parseArgs(argv) {
  const options = {
    history: path.join(root, "app/data/rail-history.json"),
    sections: path.join(root, "app/data/rail-sections.json"),
    stations: path.join(root, "app/data/stations.json"),
    loader: path.join(root, "app/public/app-rail-history.js"),
    routeGraph: path.join(root, "app/public/app-route-graph.js"),
    fixtures: null,
    report: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const key = {
      "--history": "history",
      "--sections": "sections",
      "--stations": "stations",
      "--loader": "loader",
      "--route-graph": "routeGraph",
      "--fixtures": "fixtures",
      "--json-report": "report",
    }[flag];
    if (!key || index + 1 >= argv.length) {
      throw new Error(`unknown or incomplete argument: ${flag}`);
    }
    options[key] = path.resolve(argv[++index]);
  }
  return options;
}

function readJson(filename) {
  return JSON.parse(fs.readFileSync(filename, "utf8"));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function previousDay(value) {
  const instant = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(instant.getTime())) throw new Error(`invalid boundary date ${value}`);
  instant.setUTCDate(instant.getUTCDate() - 1);
  return instant.toISOString().slice(0, 10);
}

function writeJson(filename, value) {
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, `${JSON.stringify(value, null, 2)}\n`);
}

function loadProductionFunctions(options) {
  const context = vm.createContext({ console });
  const config = fs.readFileSync(path.join(root, 'app/public/app-config.js'), 'utf8');
  const scopeFunction = config.match(/function railScopeCountriesForCountry\(country\) \{[^}]+\}/);
  if (!scopeFunction) throw new Error('production country scope function was not found');
  vm.runInContext(scopeFunction[0], context);
  for (const filename of [options.loader, options.routeGraph]) {
    vm.runInContext(fs.readFileSync(filename, "utf8"), context, { filename });
  }
  for (const name of [
    "validateRailHistoryOverlay",
    "applyRailHistory",
    "railServiceBounds",
    "railHistoryMatches",
    "railHistoryTargetAllows",
    "isRailValid",
  ]) {
    if (typeof context[name] !== "function") {
      throw new Error(`production function ${name} was not loaded`);
    }
  }
  return context;
}

function featureList(collection) {
  return Array.isArray(collection) ? collection : collection.features;
}

function featureId(feature, category, index) {
  return feature?.properties?.history_id || `${category}[${index}]`;
}

function buildFixtures(context, sections, stations) {
  const fixtures = [];
  for (const [category, records] of [
    ["sections", featureList(sections)],
    ["stations", featureList(stations)],
  ]) {
    records.forEach((feature, index) => {
      const bounds = context.railServiceBounds(feature?.properties);
      for (const [edge, boundary] of [
        ["valid_from", bounds.valid_from],
        ["valid_to", bounds.valid_to],
      ]) {
        if (boundary == null || boundary === "") continue;
        const before = previousDay(boundary);
        const expectedBefore = edge === "valid_to";
        const expectedOn = edge === "valid_from";
        fixtures.push({
          id: featureId(feature, category, index),
          category,
          feature_index: index,
          edge,
          boundary,
          checks: [
            {
              label: "day_before",
              date: before,
              expected_available: expectedBefore,
              actual_available: context.isRailValid(bounds.valid_from, bounds.valid_to, before),
            },
            {
              label: "day_of",
              date: boundary,
              expected_available: expectedOn,
              actual_available: context.isRailValid(bounds.valid_from, bounds.valid_to, boundary),
            },
          ],
        });
      }
    });
  }
  return fixtures;
}

function verifyRetirements(context, overlay, originals, applied) {
  const matchCounts = new Map(
    (overlay.retirements || []).map((retirement) => [retirement.history_id, 0]),
  );
  const effectiveChecks = [];
  for (const category of ["sections", "stations"]) {
    const originalList = featureList(originals[category]);
    const appliedList = featureList(applied[category]);
    originalList.forEach((original, index) => {
      const matching = (overlay.retirements || []).filter(
        (retirement) =>
          context.railHistoryTargetAllows(retirement.match, category) &&
          context.railHistoryMatches(original, retirement.match),
      );
      if (!matching.length) return;
      matching.forEach((retirement) =>
        matchCounts.set(retirement.history_id, matchCounts.get(retirement.history_id) + 1),
      );
      const originalBounds = context.railServiceBounds(original.properties);
      const starts = [originalBounds.valid_from];
      const ends = [originalBounds.valid_to];
      matching.forEach((retirement) => {
        const bounds = context.railServiceBounds(retirement);
        starts.push(bounds.valid_from);
        ends.push(bounds.valid_to);
      });
      const expected = {
        valid_from: starts.filter(Boolean).sort().at(-1) || null,
        valid_to: ends.filter(Boolean).sort().at(0) || null,
      };
      const actual = context.railServiceBounds(appliedList[index].properties);
      effectiveChecks.push({
        category,
        feature_index: index,
        retirement_ids: matching.map((retirement) => retirement.history_id),
        expected_bounds: expected,
        actual_bounds: actual,
        nonempty:
          expected.valid_from == null ||
          expected.valid_to == null ||
          expected.valid_from < expected.valid_to,
        matched:
          actual.valid_from === expected.valid_from &&
          actual.valid_to === expected.valid_to,
      });
    });
  }
  return {
    selectors: (overlay.retirements || []).map((retirement) => ({
      history_id: retirement.history_id,
      matches: matchCounts.get(retirement.history_id),
    })),
    effectiveChecks,
  };
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const context = loadProductionFunctions(options);
  const overlay = readJson(options.history);
  const sections = clone(readJson(options.sections));
  const stations = clone(readJson(options.stations));

  context.validateRailHistoryOverlay(overlay);
  const originalSections = clone(sections);
  const originalStations = clone(stations);
  const currentSectionCount = featureList(sections).length;
  const currentStationCount = featureList(stations).length;
  const application = context.applyRailHistory(overlay, sections, stations);
  // Boot applies station stamps before sections arrive. Already stamped current
  // stations must still satisfy the second-stage strict selector check.
  const bootSections = clone(originalSections);
  const bootStations = clone(originalStations);
  context.loadRailHistoryOverlay(overlay, 'jp');
  context.applyLoadedRailHistoryToStations(bootStations, 'jp');
  context.applyLoadedRailHistoryToSections(bootSections, bootStations, 'jp');
  assert.equal(JSON.stringify(bootSections), JSON.stringify(sections), 'boot section application differs');
  assert.equal(JSON.stringify(bootStations), JSON.stringify(stations), 'boot station application differs');
  const appliedCurrentSections = {
    features: featureList(sections).slice(0, currentSectionCount),
  };
  const appliedCurrentStations = {
    features: featureList(stations).slice(0, currentStationCount),
  };
  const retirementVerification = verifyRetirements(
    context,
    overlay,
    { sections: originalSections, stations: originalStations },
    { sections: appliedCurrentSections, stations: appliedCurrentStations },
  );
  const fixtures = buildFixtures(context, sections, stations);
  const failedFixtures = fixtures.flatMap((fixture) =>
    fixture.checks
      .filter((check) => check.actual_available !== check.expected_available)
      .map((check) => ({
        id: fixture.id,
        category: fixture.category,
        edge: fixture.edge,
        ...check,
      })),
  );
  const failedRetirements = retirementVerification.selectors.filter(
    (entry) => entry.matches === 0,
  );
  const failedEffectiveIntersections = retirementVerification.effectiveChecks.filter(
    (check) => !check.nonempty || !check.matched,
  );
  const uniqueDates = new Set(fixtures.map((fixture) => fixture.boundary));
  const report = {
    result:
      failedFixtures.length || failedRetirements.length || failedEffectiveIntersections.length
        ? "ERROR"
        : "PASS",
    overlay_revision: overlay.revision,
    application,
    actual_transition_features: new Set(fixtures.map((fixture) => `${fixture.category}:${fixture.feature_index}`)).size,
    transition_boundaries: fixtures.length,
    unique_effective_dates: uniqueDates.size,
    effective_dates: [...uniqueDates].sort(),
    retirement_checks: retirementVerification.selectors.length,
    effective_retirement_intersections: retirementVerification.effectiveChecks.length,
    failed_fixture_checks: failedFixtures,
    failed_retirements: failedRetirements.map((entry) => entry.history_id),
    failed_effective_intersections: failedEffectiveIntersections,
    claims: {
      production_web_loader: "PASS",
      production_availability_predicate: "PASS",
      route_solver_regression: "INCOMPLETE",
      final_display: "INCOMPLETE",
    },
  };

  if (options.fixtures) {
    writeJson(options.fixtures, {
      schema_version: "1",
      generated_from_revision: overlay.revision,
      fixtures,
    });
  }
  if (options.report) writeJson(options.report, report);

  console.log(
    `JP history boundaries: ${report.transition_boundaries} actual transitions on ` +
      `${report.actual_transition_features} features across ${report.unique_effective_dates} effective dates; ` +
      `${report.retirement_checks} retirement selectors and ` +
      `${report.effective_retirement_intersections} effective intersections checked`,
  );
  console.log(
    "Scope note: production loader and availability predicates passed; route solving and final display were not exercised.",
  );
  if (report.result !== "PASS") {
    console.error(
      JSON.stringify(
        {
          failedFixtures,
          failedRetirements: report.failed_retirements,
          failedEffectiveIntersections,
        },
        null,
        2,
      ),
    );
    return 1;
  }
  return 0;
}

try {
  process.exitCode = main();
} catch (error) {
  console.error(`ERROR: ${error?.stack || error}`);
  process.exitCode = 2;
}
