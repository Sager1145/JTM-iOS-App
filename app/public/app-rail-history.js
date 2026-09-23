// =========================================================================
//  app-rail-history.js — dated rail history overlay (docs/rail-history.md,
//  ADR 0011)
//
//  Plain classic script sharing the app-*.js global lexical scope. Not yet
//  wired into index.html / the boot fetch path: app-route-graph.js reads
//  getRailHistoryRevision() behind a typeof guard, so an absent module keys
//  the route cache as "history:none" — exactly today's behaviour.
// =========================================================================

let railHistoryOverlay = null;

const RAIL_HISTORY_SCHEMA_VERSION = "1";

// Validate and store an overlay. Returns the stored overlay, or throws on a
// schema mismatch / missing revision so a bad file never silently keys the
// route cache.
function loadRailHistoryOverlay(json) {
  if (!json || typeof json !== "object") {
    throw new Error("rail history overlay: not an object");
  }
  if (String(json.schema_version) !== RAIL_HISTORY_SCHEMA_VERSION) {
    throw new Error(
      `rail history overlay: unsupported schema_version ${json.schema_version}`,
    );
  }
  if (typeof json.revision !== "string" || !json.revision.trim()) {
    throw new Error("rail history overlay: missing revision");
  }
  railHistoryOverlay = json;
  return json;
}

function getRailHistoryRevision() {
  return railHistoryOverlay?.revision || null;
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
function applyRailHistory(overlay, sections, stations) {
  const sectionList = railHistoryFeatureList(sections) || [];
  const stationList = railHistoryFeatureList(stations) || [];
  const retirementsApplied = {};
  const unmatchedRetirements = [];

  (overlay?.retirements || []).forEach((retirement) => {
    const id = retirement?.history_id;
    const match = retirement?.match;
    let count = 0;
    if (match) {
      [sectionList, stationList].forEach((list) => {
        list.forEach((feature) => {
          if (!railHistoryMatches(feature, match)) return;
          feature.properties = feature.properties || {};
          if (retirement.valid_from != null)
            feature.properties.valid_from = retirement.valid_from;
          if (retirement.valid_to != null)
            feature.properties.valid_to = retirement.valid_to;
          count += 1;
        });
      });
    }
    if (count > 0) retirementsApplied[id] = count;
    else unmatchedRetirements.push(id);
  });

  const addedSections = overlay?.sections || [];
  const addedStations = overlay?.stations || [];
  addedSections.forEach((feature) => sectionList.push(feature));
  addedStations.forEach((feature) => stationList.push(feature));

  return {
    sectionsAdded: addedSections.length,
    stationsAdded: addedStations.length,
    retirementsApplied,
    unmatchedRetirements,
  };
}
