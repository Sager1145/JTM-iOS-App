// =========================================================================
//  app-rail-history.js — dated rail history overlay (docs/rail-history.md,
//  ADR 0011)
//
//  Plain classic script sharing the app-*.js global lexical scope. Overlays
//  are kept per region because the North American solver scope contains both
//  US and Canadian datasets. A missing optional overlay is represented by the
//  revision string "none" in solve provenance.
// =========================================================================

const railHistoryOverlays = new Map();

const RAIL_HISTORY_SCHEMA_VERSION = "1";

const RAIL_HISTORY_KINDS = new Set([
  "opening",
  "closure",
  "relocation",
  "station_opening",
  "station_closure",
  "suspension",
  "resumption",
  "operator_transfer",
]);

// Service interval the ride solver reads. service_validity wins when present.
// Otherwise today's valid_from/valid_to. A lone infrastructure_validity pair
// is that service interval. Empty strings are preserved, matching the edge
// copy `properties?.valid_from ?? null`.
function railServiceBounds(source) {
  if (!source || typeof source !== "object")
    return { valid_from: null, valid_to: null };
  const asPair = (value) => ({
    valid_from: value[0] ?? null,
    valid_to: value[1] ?? null,
  });
  if (
    Object.prototype.hasOwnProperty.call(source, "service_validity") &&
    Array.isArray(source.service_validity)
  ) {
    return asPair(source.service_validity);
  }
  const hasLegacy = source.valid_from != null || source.valid_to != null;
  if (
    !hasLegacy &&
    Object.prototype.hasOwnProperty.call(source, "infrastructure_validity") &&
    Array.isArray(source.infrastructure_validity)
  ) {
    return asPair(source.infrastructure_validity);
  }
  return {
    valid_from: source.valid_from ?? null,
    valid_to: source.valid_to ?? null,
  };
}

// Validate and store an overlay. Returns the stored overlay, or throws on a
// schema mismatch / missing revision so a bad file never silently keys the
// route cache.
function railHistoryDate(value, label) {
  if (value == null) return null;
  if (typeof value !== "string")
    throw new Error(`rail history overlay: ${label} must be YYYY-MM-DD`);
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match)
    throw new Error(`rail history overlay: ${label} must be YYYY-MM-DD`);
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > monthDays[month - 1])
    throw new Error(`rail history overlay: ${label} is not a real Gregorian date`);
  return value;
}

function railHistoryEntryId(entry, label, fromProperties = false) {
  const value = fromProperties ? entry?.properties?.history_id : entry?.history_id;
  if (typeof value !== "string" || !value.trim())
    throw new Error(`rail history overlay: ${label} has a blank history_id`);
  return value.trim();
}

function railHistoryPair(value, label) {
  if (!Array.isArray(value) || value.length !== 2)
    throw new Error(`rail history overlay: ${label} must be a [from, to] pair`);
  const from = value[0] == null ? null : railHistoryDate(value[0], `${label}[0]`);
  const to = value[1] == null ? null : railHistoryDate(value[1], `${label}[1]`);
  if (from && to && from >= to)
    throw new Error(`rail history overlay: ${label} from must precede to`);
  return { from, to, stated: from != null || to != null };
}

function validateRailHistoryKind(source, label) {
  if (!source || !Object.prototype.hasOwnProperty.call(source, "kind")) return;
  if (!RAIL_HISTORY_KINDS.has(source.kind))
    throw new Error(`rail history overlay: ${label}.kind is invalid`);
}

function validateRailHistoryInterval(entry, label, fromProperties = false) {
  const source = fromProperties ? entry?.properties : entry;
  validateRailHistoryKind(source, label);
  for (const key of ["valid_from", "valid_to"]) {
    if (Object.prototype.hasOwnProperty.call(source || {}, key) && source[key] == null)
      throw new Error(`rail history overlay: ${label}.${key} cannot be null`);
  }
  const from = railHistoryDate(source?.valid_from, `${label}.valid_from`);
  const to = railHistoryDate(source?.valid_to, `${label}.valid_to`);
  if (from && to && from >= to)
    throw new Error(`rail history overlay: ${label} valid_from must precede valid_to`);
  let service = null;
  let infrastructure = null;
  for (const key of ["service_validity", "infrastructure_validity"]) {
    if (!Object.prototype.hasOwnProperty.call(source || {}, key)) continue;
    if (source[key] == null)
      throw new Error(`rail history overlay: ${label}.${key} cannot be null`);
    const pair = railHistoryPair(source[key], `${label}.${key}`);
    if (key === "service_validity") service = pair;
    else infrastructure = pair;
  }
  const hasLegacy = Boolean(from || to);
  const hasDomain = Boolean(service?.stated || infrastructure?.stated);
  if (!hasLegacy && !hasDomain)
    throw new Error(`rail history overlay: ${label} needs valid_from or valid_to`);
}

function validateRailHistoryOverlay(json) {
  if (!json || typeof json !== "object") {
    throw new Error("rail history overlay: not an object");
  }
  if (json.schema_version !== RAIL_HISTORY_SCHEMA_VERSION) {
    throw new Error(
      `rail history overlay: unsupported schema_version ${json.schema_version}`,
    );
  }
  if (typeof json.revision !== "string" || !json.revision.trim()) {
    throw new Error("rail history overlay: missing revision");
  }
  for (const key of ["sections", "stations", "retirements"]) {
    if (!Array.isArray(json[key]))
      throw new Error(`rail history overlay: ${key} must be an array`);
  }

  const sectionIds = new Set();
  (json.sections || []).forEach((entry, index) => {
    const label = `sections[${index}]`;
    sectionIds.add(railHistoryEntryId(entry, label, true));
    validateRailHistoryInterval(entry, label, true);
  });

  const stationIds = new Set();
  (json.stations || []).forEach((entry, index) => {
    const label = `stations[${index}]`;
    const id = railHistoryEntryId(entry, label, true);
    if (stationIds.has(id))
      throw new Error(`rail history overlay: duplicate station history_id ${id}`);
    stationIds.add(id);
    validateRailHistoryInterval(entry, label, true);
  });

  const retirementIds = new Set();
  (json.retirements || []).forEach((entry, index) => {
    const label = `retirements[${index}]`;
    const id = railHistoryEntryId(entry, label);
    if (retirementIds.has(id))
      throw new Error(`rail history overlay: duplicate retirement history_id ${id}`);
    retirementIds.add(id);
    validateRailHistoryInterval(entry, label);
    const targets = entry?.match?.targets;
    if (targets != null) {
      if (
        !Array.isArray(targets) ||
        targets.length === 0 ||
        targets.some((target) => target !== "sections" && target !== "stations")
      ) {
        throw new Error(`rail history overlay: ${label}.match.targets is invalid`);
      }
    }
    const bbox = entry?.match?.bbox;
    if (
      !Array.isArray(bbox) ||
      bbox.length !== 4 ||
      !bbox.every(Number.isFinite) ||
      bbox[0] > bbox[2] ||
      bbox[1] > bbox[3]
    ) {
      throw new Error(`rail history overlay: ${label}.match.bbox is invalid`);
    }
  });

  for (const id of stationIds) {
    if (sectionIds.has(id) || retirementIds.has(id))
      throw new Error(`rail history overlay: history_id ${id} crosses categories`);
  }
  for (const id of retirementIds) {
    if (sectionIds.has(id))
      throw new Error(`rail history overlay: history_id ${id} crosses categories`);
  }
  return json;
}

function loadRailHistoryOverlay(json, country = activeCountry) {
  validateRailHistoryOverlay(json);
  railHistoryOverlays.set(String(country), json);
  return json;
}

function getRailHistoryRevision(country = activeCountry) {
  return railHistoryOverlays.get(String(country))?.revision || null;
}

function getRailHistoryRevisionsForRegions(regions) {
  return Object.fromEntries(
    regions
      .slice()
      .sort()
      .map((code) => [code, getRailHistoryRevision(code) || "none"]),
  );
}

function getRailHistoryRevisions(country = activeCountry) {
  return getRailHistoryRevisionsForRegions(railScopeCountriesForCountry(country));
}

function canonicalRailHistoryRevisionsForRegions(regions) {
  return Object.entries(getRailHistoryRevisionsForRegions(regions))
    .map(([code, revision]) => `${code}:${revision}`)
    .join("|");
}

function railHistoryRegionForStationCode(value) {
  const code = typeof value === "string" ? value.trim() : "";
  if (/^\d{6}$/.test(code)) return "jp";
  const dash = code.indexOf("-");
  if (dash <= 0) return null;
  const prefix = code.slice(0, dash).toLowerCase();
  return SUPPORTED_COUNTRIES.includes(prefix) ? prefix : null;
}

// Mirrors RailPresentation.RegionScopeRule.regionCodesTouched: declared
// region, stop codes, then section endpoint codes; duplicate regions preserve
// first occurrence and a record naming no region falls back to Japan.
function railHistoryRegionsForTrain(train) {
  const regions = [];
  const add = (value) => {
    if (value && !regions.includes(value)) regions.push(value);
  };
  if (SUPPORTED_COUNTRIES.includes(train?.region)) add(train.region);
  (train?.stops || []).forEach((stop) =>
    add(railHistoryRegionForStationCode(stop?.n02_station_code || stop?.N02_005c)),
  );
  (train?.route_sections || []).forEach((section) => {
    add(railHistoryRegionForStationCode(section?.from_n02_station_code));
    add(railHistoryRegionForStationCode(section?.to_n02_station_code));
  });
  return regions.length ? regions : ["jp"];
}

function railHistoryFeatureList(collection) {
  if (Array.isArray(collection)) return collection;
  if (collection && Array.isArray(collection.features)) return collection.features;
  return null;
}

function railHistoryLineName(properties) {
  return properties?.N02_003 || properties?.line_name || null;
}

function railHistoryOperator(properties) {
  return properties?.N02_004 || properties?.operator || null;
}

// Flatten any GeoJSON coordinate nesting into [lon, lat] pairs.
function railHistoryCoordinates(geometry) {
  const out = [];
  const walk = (value) => {
    if (!Array.isArray(value)) return;
    if (typeof value[0] === "number") {
      out.push(value);
      return;
    }
    value.forEach(walk);
  };
  walk(geometry?.coordinates);
  return out;
}

function railHistoryInsideBbox(coords, bbox) {
  if (!coords.length || !Array.isArray(bbox) || bbox.length !== 4) return false;
  const [minLon, minLat, maxLon, maxLat] = bbox;
  return coords.every(
    ([lon, lat]) =>
      lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat,
  );
}

function railHistoryTargetAllows(match, target) {
  const targets = match?.targets;
  if (!Array.isArray(targets) || targets.length === 0) return true;
  return targets.includes(target);
}

function railHistoryMatches(feature, match) {
  const properties = feature?.properties;
  if (railHistoryLineName(properties) !== match.line_name) return false;
  if (railHistoryOperator(properties) !== match.operator) return false;
  return railHistoryInsideBbox(railHistoryCoordinates(feature.geometry), match.bbox);
}

// Apply an overlay to the current package. `sections` / `stations` are
// feature arrays or FeatureCollections and are mutated in place: matched
// current features get the retirement's valid_from/valid_to, and the
// overlay's own sections/stations are appended.
function applyRailHistoryRetirements(
  overlay,
  sections,
  stations,
  { requireAllRetirementsMatched = true } = {},
) {
  const sectionList = railHistoryFeatureList(sections) || [];
  const stationList = railHistoryFeatureList(stations) || [];
  const retirementsApplied = {};
  const unmatchedRetirements = [];
  const planned = [];

  (overlay?.retirements || []).forEach((retirement) => {
    const id = retirement?.history_id;
    const match = retirement?.match;
    let count = 0;
    if (match) {
      [
        ["sections", sectionList],
        ["stations", stationList],
      ].forEach(([target, list]) => {
        if (!railHistoryTargetAllows(match, target)) return;
        list.forEach((feature) => {
          if (!railHistoryMatches(feature, match)) return;
          planned.push({ feature, retirement });
          count += 1;
        });
      });
    }
    if (count > 0) retirementsApplied[id] = count;
    else unmatchedRetirements.push(id);
  });

  if (requireAllRetirementsMatched && unmatchedRetirements.length) {
    throw new Error(
      `rail history overlay: unmatched retirements ${unmatchedRetirements.join(", ")}`,
    );
  }

  planned.forEach(({ feature, retirement }) => {
    feature.properties = feature.properties || {};
    const bounds = railServiceBounds(retirement);
    if (bounds.valid_from != null) {
      feature.properties.valid_from = bounds.valid_from;
      // A valid_from stamp is the current alignment that replaced a retired
      // one. A later valid_to-only stamp must not collapse that back to current.
      if (
        !feature.properties.temporal_kind ||
        feature.properties.temporal_kind === "current"
      ) {
        feature.properties.temporal_kind = "relocatedNew";
      }
      if (!feature.properties.history_id && retirement.history_id)
        feature.properties.history_id = retirement.history_id;
    }
    if (bounds.valid_to != null)
      feature.properties.valid_to = bounds.valid_to;
    if (retirement.service_validity != null)
      feature.properties.service_validity = retirement.service_validity;
    if (retirement.infrastructure_validity != null)
      feature.properties.infrastructure_validity =
        retirement.infrastructure_validity;
  });

  return { retirementsApplied, unmatchedRetirements };
}

// Overlay sections are historical unless swapping `.old-` for `.new-` in
// history_id names a retirement in the same overlay. That pair is a relocation.
function railHistoryOverlayKind(historyId, retirementIDs) {
  if (!historyId) return "historical";
  const relocated = String(historyId).split(".old-").join(".new-");
  if (relocated !== historyId && retirementIDs.has(relocated)) return "relocatedOld";
  return "historical";
}

function applyRailHistory(overlay, sections, stations) {
  const sectionList = railHistoryFeatureList(sections) || [];
  const stationList = railHistoryFeatureList(stations) || [];
  const retirementReport = applyRailHistoryRetirements(
    overlay,
    sectionList,
    stationList,
  );

  const addedSections = overlay?.sections || [];
  const addedStations = overlay?.stations || [];
  const retirementIDs = new Set(
    (overlay?.retirements || []).map((entry) => entry?.history_id).filter(Boolean),
  );
  addedSections.forEach((feature) => {
    feature.properties = feature.properties || {};
    feature.properties.temporal_kind = railHistoryOverlayKind(
      feature.properties.history_id,
      retirementIDs,
    );
    sectionList.push(feature);
  });
  addedStations.forEach((feature) => stationList.push(feature));

  return {
    sectionsAdded: addedSections.length,
    stationsAdded: addedStations.length,
    ...retirementReport,
  };
}

// Boot installs/indexes stations before the large rail-sections file is parsed.
// Apply station additions and any station-side retirement matches first. The
// later section install rechecks retirements against BOTH collections and is
// the strict unmatched-retirement gate before a route graph can be built.
function applyLoadedRailHistoryToStations(stations, country = activeCountry) {
  const stationList = railHistoryFeatureList(stations) || [];
  for (const code of railScopeCountriesForCountry(country)) {
    const overlay = railHistoryOverlays.get(code);
    if (!overlay) continue;
    applyRailHistoryRetirements(overlay, [], stationList, {
      requireAllRetirementsMatched: false,
    });
    (overlay.stations || []).forEach((feature) => stationList.push(feature));
  }
  return stations;
}

function applyLoadedRailHistoryToSections(
  sections,
  stations,
  country = activeCountry,
) {
  const sectionList = railHistoryFeatureList(sections) || [];
  // Station additions were installed earlier for indexing. Retirement
  // selectors describe current-package features, so do not let one historical
  // addition accidentally satisfy an otherwise-unmatched selector.
  const addedStationIDs = new Set();
  for (const code of railScopeCountriesForCountry(country)) {
    (railHistoryOverlays.get(code)?.stations || []).forEach((feature) => {
      if (feature?.properties?.history_id) addedStationIDs.add(feature.properties.history_id);
    });
  }
  const currentStations = (railHistoryFeatureList(stations) || []).filter(
    (feature) => !addedStationIDs.has(feature?.properties?.history_id),
  );
  for (const code of railScopeCountriesForCountry(country)) {
    const overlay = railHistoryOverlays.get(code);
    if (!overlay) continue;
    applyRailHistoryRetirements(overlay, sectionList, currentStations);
    const retirementIDs = new Set(
      (overlay.retirements || []).map((entry) => entry?.history_id).filter(Boolean),
    );
    (overlay.sections || []).forEach((feature) => {
      feature.properties = feature.properties || {};
      feature.properties.temporal_kind = railHistoryOverlayKind(
        feature.properties.history_id,
        retirementIDs,
      );
      sectionList.push(feature);
    });
  }
  return sections;
}
