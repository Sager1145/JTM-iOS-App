// =========================================================================
//  app-state.js — core application state owner and named state transitions
//
//  Classic-script compatibility is intentional: the lexical bindings below
//  remain visible to the ordered app family and the Node VM replay. AppActions
//  owns the shared multi-field transitions used by imports and country changes.
// =========================================================================

let trainStore = { schema_version: SCHEMA_VERSION, trains: [] };
let selectedTrainId = null;
let focusedTrainId = null;
// Live maplibregl.Marker instances for the on-map origin/destination labels.
let endpointLabelMarkers = new Map(); // label key -> { marker, el, anchor, fadeTimer }
// Which date the sidebar list is filtered to. ALL_DATES shows the combined
// "all trains" list; otherwise it is a concrete "YYYY-MM-DD" (or UNDATED).
let selectedDate = ALL_DATES;
// §5.3.1: which day Passport is REPORTING on. Deliberately not `selectedDate`.
//
// The two answer different questions — "which journeys am I editing" and "what
// am I counting" — on two different destinations, and §5.3.1 requires the
// second to be independent of the first ("Passport 的日期 Scope 独立于 Journeys
// 筛选，切换后不扰动旅程列表"). Sharing one value meant opening a journey from
// the Passport log rewrote the statistics above it on the way past, because
// selecting a record jumps the journeys filter to that record's own date.
let passportScopeDate = ALL_DATES;
// Dates the user created manually that may not yet have any train.
let manualDates = [];
// Whether the map mirrors the sidebar date filter.
let mapFollowsSelectedDate = false;
// Whether a date/train selection also fits the map to that selection.
let focusZoomEnabled = false;
// The maplibregl.Map instance created by initMap.
let map;

// Cached route render items and the signatures that define their scope.
let cachedRouteItems = null,
  cachedRouteSignature = "",
  cachedRouteOverlapSignature = "",
  cachedRouteDateActive = false;
let cachedOrderedTrains = [];
let importInProgress = false;

// What the store on screen represents, and therefore whether edits persist.
let dataSourceMode = "user";
let sampleModeDate = null;
let userStoreAvailable = false;
let sampleEditHintShown = false;

/**
 * Named transitions for state groups that have been migrated. Keeping these
 * operations beside the bindings makes their write ownership explicit while
 * the remaining groups are converted in later batches.
 */
const AppActions = Object.freeze({
  replaceTrainStore(nextStore) {
    trainStore = nextStore;
    return trainStore;
  },
  resetTrainStore() {
    trainStore = { schema_version: SCHEMA_VERSION, trains: [] };
    return trainStore;
  },
  resetWorkspaceForCountry() {
    // The outgoing store must disappear before persistence targets move.
    // Incoming dataset preparation can fail before its store is loaded.
    trainStore = { schema_version: SCHEMA_VERSION, trains: [] };
    selectedTrainId = null;
    focusedTrainId = null;
    dataSourceMode = "user";
    sampleModeDate = null;
    sampleEditHintShown = false;
    userStoreAvailable = false;
  },
  invalidateRouteRender() {
    cachedRouteItems = null;
    cachedRouteSignature = "";
  },
});

function isSampleMode() {
  return (
    dataSourceMode === "sample-single" ||
    dataSourceMode === "sample-all" ||
    dataSourceMode === "sample-new-year-grand-loop" ||
    dataSourceMode === "sample-tokyo-limited-express-loop"
  );
}

// Marker level-of-detail thresholds are state-adjacent render configuration:
// map initialization and record rendering must share the same values.
const PASSTHROUGH_MIN_ZOOM = 9;
const STOP_MIN_ZOOM = 7;
