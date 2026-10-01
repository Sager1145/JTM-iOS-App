import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

import {
  evaluateAppScripts,
  makeSandbox,
} from "../scripts/lib/app-family-sandbox.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const APP_DIR = path.join(HERE, "..");
const readJson = (relative) =>
  JSON.parse(fs.readFileSync(path.join(APP_DIR, relative), "utf8"));

function loadHistory() {
  const context = makeSandbox({ userAgent: "jp-station-opening-loader-test" });
  evaluateAppScripts(context);
  context.console = { log() {}, warn() {}, error() {}, info() {} };
  Object.assign(context, {
    __overlay: readJson("data/rail-history.json"),
    __sections: readJson("data/rail-sections.json"),
    __stations: readJson("data/stations.json"),
  });
  vm.runInContext(
    `activeCountry = "jp";
     loadRailHistoryOverlay(__overlay, "jp");
     applyLoadedRailHistoryToStations(__stations, "jp");
     applyLoadedRailHistoryToSections(__sections, __stations, "jp");`,
    context,
  );
  return context;
}

function plain(value) {
  return JSON.parse(JSON.stringify(value));
}

test("reviewed current-package stations begin exactly on their opening day", () => {
  const context = loadHistory();
  const openings = [
    {
      name: "テクノさかき",
      code: "002223",
      neighbour: "西上田",
      neighbourCode: "002243",
      before: "1999-03-31",
      opening: "1999-04-01",
    },
    {
      name: "屋代高校前",
      code: "002132",
      neighbour: "屋代",
      neighbourCode: "002152",
      before: "2001-03-21",
      opening: "2001-03-22",
    },
    {
      name: "信濃国分寺",
      code: "002303",
      neighbour: "大屋",
      neighbourCode: "002322",
      before: "2002-03-28",
      opening: "2002-03-29",
    },
    {
      name: "千曲",
      code: "002173",
      neighbour: "戸倉",
      neighbourCode: "002185",
      before: "2009-03-13",
      opening: "2009-03-14",
    },
    {
      name: "青山",
      code: "000782",
      neighbour: "盛岡",
      neighbourCode: "000794",
      before: "2006-03-17",
      opening: "2006-03-18",
    },
  ];

  for (const opening of openings) {
    context.__code = opening.code;
    context.__neighbourCode = opening.neighbourCode;
    context.__before = opening.before;
    context.__opening = opening.opening;
    const result = plain(
      vm.runInContext(
        `(() => {
          const station = __stations.features.find(
            (feature) => stationCode(feature) === __code,
          );
          const neighbour = __stations.features.find(
            (feature) => stationCode(feature) === __neighbourCode,
          );
          const available = (feature, date) =>
            filterStationCandidatesByRideDate([feature], date).length === 1;
          return {
            station: {
              name: stationName(station),
              validFrom: station.properties.valid_from,
              before: available(station, __before),
              opening: available(station, __opening),
              undated: available(station, null),
            },
            neighbour: {
              name: stationName(neighbour),
              before: available(neighbour, __before),
              opening: available(neighbour, __opening),
              undated: available(neighbour, null),
            },
          };
        })()`,
        context,
      ),
    );

    assert.deepEqual(result.station, {
      name: opening.name,
      validFrom: opening.opening,
      before: false,
      opening: true,
      undated: true,
    });
    assert.deepEqual(result.neighbour, {
      name: opening.neighbour,
      before: true,
      opening: true,
      undated: true,
    });
  }
});

test("Osaka Monorail old operator selects each complete surveyed identity", () => {
  const context = loadHistory();
  const identities = [
    {
      line: "大阪モノレール線",
      sectionCount: 28,
      stationCount: 14,
      sectionBbox: [135.44162, 34.73686, 135.58262, 34.80804],
      stationBbox: [135.44162, 34.73686, 135.58262, 34.80804],
    },
    {
      line: "国際文化公園都市モノレール線(彩都線)",
      sectionCount: 10,
      stationCount: 5,
      sectionBbox: [135.52161, 34.80677, 135.53979, 34.85538],
      stationBbox: [135.52269, 34.80677, 135.53968, 34.85538],
    },
  ];

  for (const identity of identities) {
    context.__line = identity.line;
    const result = plain(
      vm.runInContext(
        `(() => {
          const selected = (features, operator) => features.filter(
            (feature) =>
              stationLineName(feature) === __line &&
              stationOperator(feature) === operator,
          );
          const historicalSections = selected(
            __sections.features,
            "大阪高速鉄道",
          );
          const historicalStations = selected(
            __stations.features,
            "大阪高速鉄道",
          );
          const currentSections = selected(__sections.features, "大阪モノレール");
          const currentStations = selected(__stations.features, "大阪モノレール");
          const historical = [...historicalSections, ...historicalStations];
          const current = [...currentSections, ...currentStations];
          const bbox = (features) => {
            const coordinates = [];
            const visit = (value) => {
              if (
                Array.isArray(value) &&
                value.length >= 2 &&
                Number.isFinite(value[0]) &&
                Number.isFinite(value[1])
              ) {
                coordinates.push(value);
              } else if (Array.isArray(value)) {
                value.forEach(visit);
              }
            };
            features.forEach((feature) => visit(feature.geometry?.coordinates));
            return [
              Math.min(...coordinates.map(([lon]) => lon)),
              Math.min(...coordinates.map(([, lat]) => lat)),
              Math.max(...coordinates.map(([lon]) => lon)),
              Math.max(...coordinates.map(([, lat]) => lat)),
            ];
          };
          const available = (feature, date) => {
            const bounds = railServiceBounds(feature.properties);
            return isRailValid(bounds.valid_from, bounds.valid_to, date);
          };
          return {
            historicalSectionCount: historicalSections.length,
            historicalStationCount: historicalStations.length,
            currentSectionCount: currentSections.length,
            currentStationCount: currentStations.length,
            historicalSectionBbox: bbox(historicalSections),
            historicalStationBbox: bbox(historicalStations),
            oldBefore: historical.every((feature) =>
              available(feature, "2020-05-31")
            ),
            oldAtRename: historical.some((feature) =>
              available(feature, "2020-06-01")
            ),
            currentBefore: current.some((feature) =>
              available(feature, "2020-05-31")
            ),
            currentAtRename: current.every((feature) =>
              available(feature, "2020-06-01")
            ),
          };
        })()`,
        context,
      ),
    );

    assert.equal(result.historicalSectionCount, identity.sectionCount);
    assert.equal(result.historicalStationCount, identity.stationCount);
    assert.equal(result.currentSectionCount, identity.sectionCount);
    assert.equal(result.currentStationCount, identity.stationCount);
    assert.deepEqual(result.historicalSectionBbox, identity.sectionBbox);
    assert.deepEqual(result.historicalStationBbox, identity.stationBbox);
    assert.equal(result.oldBefore, true, `${identity.line}: old operator before rename`);
    assert.equal(result.oldAtRename, false, `${identity.line}: old operator at rename`);
    assert.equal(result.currentBefore, false, `${identity.line}: current operator before rename`);
    assert.equal(result.currentAtRename, true, `${identity.line}: current operator at rename`);
  }
});

test("Sassho passenger service ends before the legal infrastructure closure", () => {
  const context = loadHistory();
  const result = plain(
    vm.runInContext(
      `(() => {
        const feature = __sections.features.find((candidate) =>
          candidate.properties?.history_id ===
          "jp.jrh.sassho.iryodaigaku-shintotsukawa"
        );
        const service = railServiceBounds(feature.properties);
        const infrastructure = feature.properties.infrastructure_validity;
        return {
          service,
          infrastructure,
          serviceOnLastDay: isRailValid(
            service.valid_from,
            service.valid_to,
            "2020-04-17",
          ),
          serviceAfterLastTrain: isRailValid(
            service.valid_from,
            service.valid_to,
            "2020-04-18",
          ),
          infrastructureAfterLastTrain: isRailValid(
            infrastructure[0],
            infrastructure[1],
            "2020-04-18",
          ),
          infrastructureDayBeforeClosure: isRailValid(
            infrastructure[0],
            infrastructure[1],
            "2020-05-06",
          ),
          infrastructureOnClosure: isRailValid(
            infrastructure[0],
            infrastructure[1],
            "2020-05-07",
          ),
        };
      })()`,
      context,
    ),
  );

  assert.deepEqual(result.service, {
    valid_from: null,
    valid_to: "2020-04-18",
  });
  assert.deepEqual(result.infrastructure, [null, "2020-05-07"]);
  assert.equal(result.serviceOnLastDay, true);
  assert.equal(result.serviceAfterLastTrain, false);
  assert.equal(result.infrastructureAfterLastTrain, true);
  assert.equal(result.infrastructureDayBeforeClosure, true);
  assert.equal(result.infrastructureOnClosure, false);
});
