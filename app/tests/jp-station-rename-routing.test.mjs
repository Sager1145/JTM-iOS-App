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

const RENAME_IDS = [
  "jp.station-rename.hankyu.hk01.osaka-umeda.kobe",
  "jp.station-rename.hankyu.hk01.osaka-umeda.takarazuka",
  "jp.station-rename.hanshin.hs01.osaka-umeda",
  "jp.station-rename.hankyu.hk86.kyoto-kawaramachi",
  "jp.station-rename.hanshin.hs13.naruo-mukogawajoshidai-mae",
];

function featureCoordinates(feature) {
  const coordinates = feature.geometry?.coordinates || [];
  return coordinates.length && typeof coordinates[0]?.[0] === "number"
    ? coordinates
    : coordinates.flat();
}

function injectRenameOverlay(overlay, stations, events) {
  const alreadyCompiled = (event) =>
    overlay.stations.some((feature) =>
      feature.properties?.history_id?.startsWith(`${event.id}.`),
    );
  const present = events.filter(alreadyCompiled);
  if (present.length) {
    assert.equal(
      present.length,
      events.length,
      "rename overlay must be all-or-none",
    );
    return overlay;
  }

  for (const event of events) {
    const current = stations.features.filter(({ properties }) =>
      properties.station_name === event.after.station &&
      properties.line_name === event.after.line &&
      properties.operator === event.after.operator
    );
    assert.ok(current.length > 0, `${event.id}: current membership`);
    for (const [index, historical] of
      event.geometry.historical_stations.entries()) {
      const matches = current.filter(
        (feature) =>
          JSON.stringify(feature.geometry) ===
          JSON.stringify(historical.geometry),
      );
      assert.equal(matches.length, 1, `${event.id}: exact geometry identity`);
      const currentProperties = matches[0].properties;
      overlay.stations.push({
        ...structuredClone(historical),
        properties: {
          ...structuredClone(historical.properties),
          n02_station_code: currentProperties.n02_station_code,
          n02_group_code: currentProperties.n02_group_code,
          station_code_basis: "exact_current_geometry_identity",
          history_id: `${event.id}.test.stations.${index}`,
          service_validity: [null, event.date],
          valid_to: event.date,
          source: "test-compiled reviewed station rename",
        },
      });
    }
    const coordinates = current.flatMap(featureCoordinates);
    const epsilon = 1e-8;
    overlay.retirements.push({
      history_id: `${event.id}.test.current.stations`,
      match: {
        line_name: event.after.line,
        operator: event.after.operator,
        bbox: [
          Math.min(...coordinates.map(([lon]) => lon)) - epsilon,
          Math.min(...coordinates.map(([, lat]) => lat)) - epsilon,
          Math.max(...coordinates.map(([lon]) => lon)) + epsilon,
          Math.max(...coordinates.map(([, lat]) => lat)) + epsilon,
        ],
        targets: ["stations"],
      },
      valid_from: event.date,
      source: "test-compiled reviewed station rename",
    });
  }
  overlay.revision = `${overlay.revision}-station-rename-routing-test`;
  return overlay;
}

function rawTrain(route, target, date, role) {
  const section = {
    from: route.origin,
    to: target,
    from_n02_station_code: route.originCode,
    to_n02_station_code: null,
    line_names: [route.line],
    operator_names: [route.operator],
  };
  return {
    id: `rename-route-${route.id}-${role}`,
    date,
    number: `Rename route ${route.id}`,
    train_type: "",
    company: "",
    origin: route.origin,
    destination: target,
    direction: "down",
    visible: true,
    style: { color: "#3355AA" },
    route_policy: { institution_filter_mode: "hard" },
    route_sections: [section],
    stops: [
      {
        name: route.origin,
        n02_station_code: route.originCode,
        departure: "00:00",
        stop_type: "origin",
        ride_segment: true,
      },
      {
        name: target,
        arrival: "00:01",
        stop_type: "destination",
        ride_segment: false,
      },
    ],
  };
}

function rawCodedLeg(leg, date, role) {
  const section = {
    from: leg.from,
    to: leg.to,
    from_n02_station_code: leg.fromCode,
    to_n02_station_code: leg.toCode,
    line_names: [leg.line],
    operator_names: [leg.operator],
  };
  return {
    id: `rename-coded-${leg.id}-${role}`,
    date,
    number: `Rename coded route ${leg.id}`,
    train_type: "",
    company: leg.operator,
    origin: leg.from,
    destination: leg.to,
    direction: "down",
    visible: true,
    style: { color: "#3355AA" },
    route_policy: { institution_filter_mode: "hard" },
    route_sections: [section],
    stops: [
      {
        name: leg.from,
        n02_station_code: leg.fromCode,
        departure: "00:00",
        stop_type: "origin",
        ride_segment: true,
      },
      {
        name: leg.to,
        n02_station_code: leg.toCode,
        arrival: "00:01",
        stop_type: "destination",
        ride_segment: false,
      },
    ],
  };
}

test(
  "dated name-only station renames do not fall through to another operator",
  { timeout: 120_000 },
  async () => {
    const stations = readJson("data/stations.json");
    const sections = readJson("data/rail-sections.json");
    const eventsPayload = readJson("scripts/railway/jp-rail-history-events.json");
    const events = eventsPayload.temporal_events.filter((event) =>
      RENAME_IDS.includes(event.id),
    );
    assert.equal(events.length, RENAME_IDS.length);
    const overlay = injectRenameOverlay(
      readJson("data/rail-history.json"),
      stations,
      events,
    );

    const context = makeSandbox({ userAgent: "jp-station-rename-routing-test" });
    evaluateAppScripts(context);
    context.console = { log() {}, warn() {}, error() {}, info() {} };
    Object.assign(context, {
      __overlay: overlay,
      __sections: sections,
      __stations: stations,
      __matchedStops: readJson("data/matched-stops.json"),
    });
    await vm.runInContext(
      `(async () => {
        activeCountry = "jp";
        loadRailHistoryOverlay(__overlay, "jp");
        applyLoadedRailHistoryToStations(__stations, "jp");
        applyLoadedRailHistoryToSections(__sections, __stations, "jp");
        AppDatasets.installRailSections(__sections);
        AppDatasets.installStations(__stations);
        AppDatasets.installMatchedData({
          matchedRoutes: { type: "FeatureCollection", features: [] },
          matchedStops: __matchedStops,
        });
        await buildStationIndexesSliced(stationsGeoJson);
      })()`,
      context,
    );

    async function probe(route, target, date, role) {
      const train = rawTrain(route, target, date, role);
      context.__train = structuredClone(train);
      context.__section = structuredClone(train.route_sections[0]);
      const candidates = vm.runInContext(
        `resolveSectionEndpoints(__section, __train, ["4"])
          .toStations.map((feature) => ({
            name: stationName(feature),
            line: stationLineName(feature),
            operator: stationOperator(feature),
            code: stationCode(feature),
          }))`,
        context,
      );
      const result = await vm.runInContext(
        `(async () => {
          const id = appendImportedTrain(__train, null);
          const train = getTrain(id);
          const features = await RouteService.warmTrain(train);
          const solve = buildTrainRouteSolveContext(train);
          return {
            features,
            unsolvable: Boolean(solve && RouteService.isNegative(solve.cacheKey)),
          };
        })()`,
        context,
      );
      return {
        candidates: JSON.parse(JSON.stringify(candidates)),
        features: JSON.parse(JSON.stringify(result.features)),
        outcome: result.unsolvable ? "unsolvable" : "solved",
      };
    }

    async function probeCodedLeg(leg, date, role) {
      const train = rawCodedLeg(leg, date, role);
      context.__train = structuredClone(train);
      context.__section = structuredClone(train.route_sections[0]);
      const endpoints = vm.runInContext(
        `(() => {
          const endpoints = resolveSectionEndpoints(__section, __train, ["4"]);
          const summarize = (features) => features.map((feature) => ({
            name: stationName(feature),
            line: stationLineName(feature),
            operator: stationOperator(feature),
            code: stationCode(feature),
          }));
          return {
            from: summarize(endpoints.fromStations),
            to: summarize(endpoints.toStations),
          };
        })()`,
        context,
      );
      const result = await vm.runInContext(
        `(async () => {
          const id = appendImportedTrain(__train, null);
          const train = getTrain(id);
          const features = await RouteService.warmTrain(train);
          const solve = buildTrainRouteSolveContext(train);
          return {
            features,
            unsolvable: Boolean(solve && RouteService.isNegative(solve.cacheKey)),
          };
        })()`,
        context,
      );
      return {
        endpoints: JSON.parse(JSON.stringify(endpoints)),
        features: JSON.parse(JSON.stringify(result.features)),
        outcome: result.unsolvable ? "unsolvable" : "solved",
      };
    }

    const umedaRoutes = [
      {
        id: "hankyu-kobe",
        origin: "十三",
        originCode: "006970",
        old: "梅田",
        current: "大阪梅田",
        line: "神戸線",
        operator: "阪急電鉄",
        targetCode: "007049",
      },
      {
        id: "hankyu-takarazuka",
        origin: "十三",
        originCode: "006968",
        old: "梅田",
        current: "大阪梅田",
        line: "宝塚線",
        operator: "阪急電鉄",
        targetCode: "007048",
      },
      {
        id: "hanshin-main",
        origin: "福島",
        originCode: "007098",
        old: "梅田",
        current: "大阪梅田",
        line: "本線",
        operator: "阪神電気鉄道",
        targetCode: "007071",
      },
    ];

    for (const route of umedaRoutes) {
      const newBefore = await probe(
        route,
        route.current,
        "2019-09-30",
        "new-before",
      );
      assert.equal(newBefore.outcome, "unsolvable", `${route.id}: new before`);
      assert.deepEqual(newBefore.candidates, []);

      const oldBefore = await probe(
        route,
        route.old,
        "2019-09-30",
        "old-before",
      );
      assert.equal(oldBefore.outcome, "solved", `${route.id}: old before`);
      assert.ok(
        oldBefore.candidates.some(
          (candidate) =>
            candidate.name === route.old &&
            candidate.line === route.line &&
            candidate.operator === route.operator &&
            candidate.code === route.targetCode,
        ),
        `${route.id}: predecessor membership is the dated endpoint candidate`,
      );
      assert.equal(oldBefore.features.length, 1);
      assert.deepEqual(
        oldBefore.features[0].properties.required_line_names,
        [route.line],
      );
      assert.deepEqual(
        oldBefore.features[0].properties.required_operator_names,
        [route.operator],
      );
      assert.equal(oldBefore.features[0].properties.snap_distance_m.to, 0);

      const oldAfter = await probe(
        route,
        route.old,
        "2019-10-01",
        "old-after",
      );
      assert.equal(oldAfter.outcome, "unsolvable", `${route.id}: old after`);
      assert.deepEqual(
        oldAfter.candidates,
        [],
        `${route.id}: Osaka Metro 梅田 must not replace the retired membership`,
      );
      assert.deepEqual(oldAfter.features, []);

      const newAt = await probe(
        route,
        route.current,
        "2019-10-01",
        "new-at",
      );
      assert.equal(newAt.outcome, "solved", `${route.id}: new at boundary`);
      assert.ok(
        newAt.candidates.some(
          (candidate) =>
            candidate.name === route.current &&
            candidate.line === route.line &&
            candidate.operator === route.operator &&
            candidate.code === route.targetCode,
        ),
      );
      assert.equal(newAt.features.length, 1);
      assert.deepEqual(newAt.features[0].properties.required_line_names, [route.line]);
      assert.deepEqual(
        newAt.features[0].properties.required_operator_names,
        [route.operator],
      );
      assert.equal(newAt.features[0].properties.snap_distance_m.to, 0);
    }

    // The guard is name-only. A source station code continues through the
    // established code/name resolver unchanged, even when the resulting
    // historical membership is later rejected by the ride-date filter.
    const codedRoute = umedaRoutes[0];
    context.__codedTrain = rawTrain(
      codedRoute,
      codedRoute.old,
      "2019-10-01",
      "explicit-code-contract",
    );
    context.__codedEndpoint = {
      name: codedRoute.old,
      n02_station_code: codedRoute.targetCode,
    };
    const codedCandidates = vm.runInContext(
      `resolveRouteEndpointStationCandidates(
        __codedEndpoint,
        __codedTrain,
        ["4"],
        ["神戸線"],
      ).map((feature) => ({
        name: stationName(feature),
        line: stationLineName(feature),
        operator: stationOperator(feature),
        code: stationCode(feature),
      }))`,
      context,
    );
    assert.ok(
      codedCandidates.some(
        (candidate) =>
          candidate.name === codedRoute.old &&
          candidate.line === codedRoute.line &&
          candidate.operator === codedRoute.operator &&
          candidate.code === codedRoute.targetCode,
      ),
    );
    context.__undatedEndpoint = {
      name: "大阪梅田",
      n02_station_code: "007048",
    };
    const undatedStationApiCandidates = vm.runInContext(
      `resolveStationCandidates(__undatedEndpoint).map((feature) =>
        stationName(feature))`,
      context,
    );
    assert.deepEqual(
      JSON.parse(JSON.stringify(undatedStationApiCandidates)),
      ["大阪梅田"],
      "the generic undated station API keeps its written-name preference",
    );

    // The two shipped Kyo-train patterns write today's station names and
    // stable current codes even for rides before the 2019 rename. The dated
    // endpoint wrapper must select the same-code historical aliases while
    // retaining the fixtures' actual line/operator constraints.
    const historicalCodedLegs = [
      {
        id: "kyo-train-umeda-juso",
        from: "大阪梅田",
        fromCode: "007048",
        to: "十三",
        toCode: "006967",
        historicalEndpoint: "梅田",
        historicalSide: "from",
        currentEndpoint: "大阪梅田",
        line: "宝塚線",
        operator: "阪急電鉄",
      },
      {
        id: "kyo-train-karasuma-kawaramachi",
        from: "烏丸",
        fromCode: "005992",
        to: "京都河原町",
        toCode: "005990",
        historicalEndpoint: "河原町",
        historicalSide: "to",
        currentEndpoint: "京都河原町",
        line: "京都線",
        operator: "阪急電鉄",
      },
    ];
    for (const date of ["2011-05-14", "2019-03-23"]) {
      for (const leg of historicalCodedLegs) {
        const result = await probeCodedLeg(leg, date, `historical-${date}`);
        assert.equal(result.outcome, "solved", `${leg.id}: ${date}`);
        assert.ok(result.features.length > 0, `${leg.id}: ${date} geometry`);
        const endpoint = result.endpoints[leg.historicalSide];
        assert.ok(
          endpoint.some(
            (candidate) =>
              candidate.name === leg.historicalEndpoint &&
              candidate.line === leg.line &&
              candidate.operator === leg.operator,
          ),
          `${leg.id}: ${date} historical code alias`,
        );
        assert.equal(
          endpoint.some((candidate) => candidate.name === leg.currentEndpoint),
          false,
          `${leg.id}: current name is not active on ${date}`,
        );
      }
    }

    for (const leg of historicalCodedLegs) {
      const result = await probeCodedLeg(leg, "2019-10-01", "current-boundary");
      assert.equal(result.outcome, "solved", `${leg.id}: rename boundary`);
      const endpoint = result.endpoints[leg.historicalSide];
      assert.ok(
        endpoint.some((candidate) => candidate.name === leg.currentEndpoint),
        `${leg.id}: current endpoint at rename boundary`,
      );
      assert.equal(
        endpoint.some((candidate) => candidate.name === leg.historicalEndpoint),
        false,
        `${leg.id}: historical endpoint retired at boundary`,
      );
    }

    const oldNameAfterRename = await probeCodedLeg(
      {
        ...historicalCodedLegs[0],
        id: "kyo-train-old-umeda-name-after-rename",
        from: "梅田",
      },
      "2019-10-01",
      "old-name-current-code-after",
    );
    assert.equal(oldNameAfterRename.outcome, "solved");
    assert.ok(
      oldNameAfterRename.endpoints.from.some(
        (candidate) =>
          candidate.name === "大阪梅田" &&
          candidate.code === "007048" &&
          candidate.line === "宝塚線" &&
          candidate.operator === "阪急電鉄",
      ),
      "explicit code carries the old written name to the current membership",
    );
    assert.equal(
      oldNameAfterRename.endpoints.from.some(
        (candidate) => candidate.name === "梅田",
      ),
      false,
    );

    // A source code whose pool never contained the written station name is a
    // data mismatch, not a rename alias. Preserve the existing name fallback
    // and prove the real RouteService still solves from 千葉 rather than the
    // incorrectly supplied 京葉線 越中島 code.
    const wrongCode = await probeCodedLeg(
      {
        id: "wrong-code-name-fallback",
        from: "千葉",
        fromCode: "003859",
        to: "稲毛",
        toCode: "004047",
        line: "総武線",
        operator: "東日本旅客鉄道",
      },
      "2019-03-23",
      "wrong-code",
    );
    assert.equal(wrongCode.outcome, "solved");
    assert.ok(
      wrongCode.endpoints.from.some(
        (candidate) =>
          candidate.name === "千葉" &&
          candidate.line === "総武線" &&
          candidate.code === "004165",
      ),
    );
    assert.equal(
      wrongCode.endpoints.from.some((candidate) => candidate.code === "003859"),
      false,
    );

    // 十三 has three current Hankyu memberships. A valid explicitly named
    // membership must keep the ordinary shared-station expansion and solve;
    // the retired-name guard is not a blanket line/operator endpoint filter.
    const shared = {
      id: "hankyu-shared-juso",
      origin: "中津",
      originCode: "007027",
      line: "神戸線",
      operator: "阪急電鉄",
    };
    const sharedResult = await probe(
      shared,
      "十三",
      "2026-01-01",
      "shared-current",
    );
    assert.equal(sharedResult.outcome, "solved");
    assert.ok(sharedResult.candidates.length >= 3);
    assert.ok(
      sharedResult.candidates.some(
        (candidate) =>
          candidate.name === "十三" &&
          candidate.line === "神戸線" &&
          candidate.operator === "阪急電鉄" &&
          candidate.code === "006970",
      ),
    );
    assert.equal(sharedResult.features[0].properties.snap_distance_m.to, 0);
  },
);
