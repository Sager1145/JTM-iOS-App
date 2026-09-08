/*
 * railmap.js — MapLibre GL map core, styled after yzhouwang/railprint.
 *
 * The map core is a family of classic scripts, each publishing one global;
 * index.html loads them in this order:
 *
 *   railmap-basemap.js       RailMapBasemap   basemap style loading + probing
 *   railmap-popup.js         RailMapPopup     C5 station popup model + HTML
 *   railmap-style.js         RailMapStyle     design tokens, layer/source ids,
 *                                             spotlight constants, buildBaseStyle
 *   railmap-geometry.js      RailMapGeometry  record → GeoJSON + overlap-fan math
 *   railmap.js  (this file)  RailMap          the overlay manager: attach, data
 *                                             feeds, basemap install/crossfade,
 *                                             filters, dim/expand animations
 *   railmap-interactions.js  —                extends RailMap with click/hover
 *                                             wiring, tooltip + station popup
 *
 * Together they are a faithful port of railprint's map styling stack
 * (src/design/tokens.ts + src/lib/map/basemap.ts + src/lib/map/style.ts +
 * src/lib/map/popup.ts) into dependency-free browser scripts:
 *
 *   - BASEMAP: OpenFreeMap `positron` for BOTH themes — dark is positron
 *     recolored to a dark palette (railmap-basemap.js), so label layers,
 *     fonts and zoom behavior match light mode exactly. If the online tile
 *     source is unavailable, the rail renders over a theme-matched plain
 *     background.
 *   - NETWORK: the active country's compact-v1 rail package (Japan or Taiwan).
 *     Drawn exactly like railprint's "unridden" field: each line in its
 *     official color at 0.48 opacity, thin, with
 *     zoom-tiered reveal (rank -> minzoom) — and station dots in neutral
 *     grey revealed by average inter-station spacing.
 *   - TRAINS ("ridden"): full-color thick lines (the glow underlay was
 *     removed by request); the selected train gets a dark ink casing
 *     underlay + white-fill/ink-ring station dots (railprint C3 selection
 *     treatment).
 *   - HOVER: hovering a network station opens railprint's C5 bilingual popup
 *     listing every line through the physical station (logo or color swatch
 *     + line name + short company label).
 *
 * The public API mirrors the old deck.gl overlay manager (attach / setData /
 * setMarkers / setSelected / setVisible / setMarkerVisibility) so the app's
 * record-building pipeline plugs in unchanged.
 */
(function (global) {
  "use strict";

  const {
    loadBasemap,
    probeBasemapOrigin,
    namespaceBasemap,
    opacityPropsForLayer,
    MAP_SURFACE_COLORS,
    BASEMAP_CROSSFADE_MS,
  } = global.RailMapBasemap;
  const {
    buildBaseStyle,
    railAttributionForCountry,
    stopMarkerZoomGate,
    networkLineColor,
    networkCasingColor,
    riddenLineWidth,
    riddenHoverLineWidth,
    riddenFocusLineWidth,
    railwayScreenPaintEntries,
    railwayScaleAt,
    laneScaleForZoom,
    markerRadiusExpr,
    selectedStopRadiusExpr,
    EMPTY_FC,
    NO_TRAIN,
    MATCH_NONE,
    HOVER_DIM,
    HOVER_PICK_PAD_PX,
    HOVER_STICKY_PAD_PX,
    HOVER_FAN_HOLD_PX,
    HOVER_GROUP_SWITCH_PX,
    SELECT_DIM,
    SEGMENTS_SOURCE,
    STATIONS_SOURCE,
    STATION_LANES_SOURCE,
    STATION_LABELS_SOURCE,
    SEGMENTS_LAYER,
    SEGMENTS_CASING_LAYER,
    SEGMENTS_SUSPENDED_LAYER,
    SEGMENTS_SUSPENDED_CASING_LAYER,
    SEGMENTS_WITHHELD_SOURCE,
    SEGMENTS_WITHHELD_LAYER,
    SEGMENTS_WITHHELD_CASING_LAYER,
    STATIONS_LAYER,
    STATION_LANES_LAYER,
    STATION_ICON_BASE_PX,
    RAILWAY_STYLE,
    stationIconId,
    stationIconImage,
    STATIONS_LABEL_LAYER,
    SEGMENTS_LABEL_LAYER,
    networkLabelTextColor,
    networkLabelHaloColor,
    networkLineLabelColor,
    FADE_LAYER,
    TRAIN_ROUTES_SOURCE,
    TRAIN_PICK_SOURCE,
    TRAIN_PICK_FAN_SOURCE,
    TRAIN_EXPAND_SOURCE,
    TRAIN_MARKERS_SOURCE,
    FIT_CURVES_SOURCE,
    HOVER_REGIONS_SOURCE,
    TRAIN_ROUTES_LAYER,
    TRAIN_XDAY_LAYER,
    TRAIN_XDAY_STOP_LAYER,
    XDAY_ICON_ID,
    XDAY_ICON_BASE_RADIUS,
    TRAIN_PICK_LAYER,
    TRAIN_PICK_FAN_LAYER,
    TRAIN_EXPAND_LAYER,
    TRAIN_EXPAND_HOVER_LAYER,
    TRAIN_HOVER_LAYER,
    TRAIN_SEL_CASING_LAYER,
    TRAIN_SEL_LAYER,
    TRAIN_PASS_LAYER,
    TRAIN_STOPS_LAYER,
    TRAIN_TERMINAL_LABEL_LAYER,
    TRAIN_STOP_LABEL_LAYER,
    TRAIN_PASS_LABEL_LAYER,
    TRAIN_SEL_PASS_LAYER,
    TRAIN_SEL_STOPS_LAYER,
    PLAYBACK_SOURCE,
    PLAYBACK_DONE_LAYER,
    PLAYBACK_HEAD_LAYER,
    PLAYBACK_CASING_DONE_LAYER,
    PLAYBACK_CASING_HEAD_LAYER,
    PLAYBACK_STATIONS_SOURCE,
    PLAYBACK_STATION_LAYER,
    PLAYBACK_STATION_DONE_LAYER,
    PLAYBACK_STATION_LABEL_LAYER,
    PLAYBACK_HEAD_SOURCE,
    PLAYBACK_HEAD_DOT_LAYER,
    playbackTrailGradient,
    playbackStationDoneRadius,
    playbackStationTextColor,
    FIT_CURVES_CASING_LAYER,
    FIT_CURVES_LAYER,
    HOVER_REGIONS_FILL_LAYER,
    HOVER_REGIONS_LINE_LAYER,
    stationFill,
    stationStroke,
    strokeSourceTolerancePx,
  } = global.RailMapStyle;
  const {
    routeRecordsToFC,
    routePickRecordsToFC,
    routePickFanBaseFC,
    routeExpandBaseFC,
    fanPerpAt,
    fitCurvesToFC,
    diagnoseFitCurves,
    hoverRegionsToFC,
    markerRecordsToFC,
  } = global.RailMapGeometry;

  const fanVisibleLayerId = (slot) =>
    slot ? TRAIN_EXPAND_LAYER + "-" + slot : TRAIN_EXPAND_LAYER;
  const fanHoverLayerId = (slot) =>
    slot ? TRAIN_EXPAND_HOVER_LAYER + "-" + slot : TRAIN_EXPAND_HOVER_LAYER;
  const fanPickLayerId = (slot) =>
    slot ? TRAIN_PICK_FAN_LAYER + "-" + slot : TRAIN_PICK_FAN_LAYER;

  // ───────────────────────────── rail package loader ─────────────────────────────
  // Loads the active country's rail package in compact-v1 format (stations and
  // segments nested per line, derivable fields omitted — see
  // scripts/railway/lib/railpkg.py for the format spec) and builds the two GeoJSON
  // collections + the geo index the hover popup needs (buildSegmentCollection /
  // buildStationCollection / geo-index, ported).
  //   station row: [stationGroupId, name, lon, lat, (nameRoma, romaSourceCode)]
  //   segment row: [km, sharedFirstPoint, coordinates, (arcDirection)]
  //   segment i joins station i to station (i+1) % n (loop lines close the ring)
  async function loadNetworkOnMain(packageUrls, reviewedUrl, lanesUrl) {
    const responses = await Promise.all(
      packageUrls.map((url) => fetch(url, { cache: "no-cache" })),
    );
    if (responses.some((response) => !response.ok)) return null;
    const packages = await Promise.all(responses.map((response) => response.json()));
    const merged = global.RailNetwork.mergeCompactPackages(packages);
    let reviewedSharedCorridors = null;
    try {
      const reviewedResponse = await fetch(reviewedUrl, { cache: "no-cache" });
      if (reviewedResponse.ok) reviewedSharedCorridors = await reviewedResponse.json();
    } catch (e) {
      console.warn("[railmap] shared-corridor review unavailable:", e);
    }
    let displayLanes = null;
    try {
      const laneResponse = await fetch(lanesUrl, { cache: "no-cache" });
      if (laneResponse.ok) displayLanes = await laneResponse.json();
      else
        console.warn(
          `[railmap] display lanes unavailable: ${laneResponse.status} ${laneResponse.statusText} (${lanesUrl})`,
        );
    } catch (e) {
      console.warn("[railmap] display lanes unavailable:", lanesUrl, e);
    }
    return global.RailNetwork.buildNetworkFromCompactPackage(
      merged,
      reviewedSharedCorridors,
      displayLanes,
    );
  }

  function loadNetworkInWorker(packageUrls, reviewedUrl, lanesUrl) {
    return new Promise((resolve, reject) => {
      const workerUrl = new URL(
        "./rail-network-worker.js?v=20260901-stroke1",
        global.location.href,
      );
      const worker = new Worker(workerUrl);
      const finish = (callback, value) => {
        worker.terminate();
        callback(value);
      };
      worker.onmessage = (event) => {
        const message = event.data || {};
        if (message.ok) finish(resolve, message.network);
        else finish(reject, new Error(message.error || "rail network worker failed"));
      };
      worker.onerror = (event) => {
        finish(reject, new Error(event.message || "rail network worker failed"));
      };
      worker.postMessage({ packageUrls, reviewedUrl, lanesUrl });
    });
  }

  async function loadNetwork(packageUrl) {
    try {
      if (!packageUrl) throw new Error("A rail package URL is required.");
      // Resolve URLs before crossing the worker boundary. This keeps the same
      // resource names on a root deploy and on a sub-path static deploy.
      const packageUrls = (Array.isArray(packageUrl) ? packageUrl : [packageUrl]).map(
        (url) => new URL(url, global.location.href).href,
      );
      const reviewedUrl = new URL("shared-corridors.json", packageUrls[0]).href;
      const lanesUrl = new URL("display-lanes.json", packageUrls[0]).href;

      // JSON.parse plus compact-v1 display derivation takes about one second
      // for Japan on the shipped package. Doing both on the window event loop
      // made the whole client unresponsive exactly when 全部鐵路線 was enabled.
      // A classic worker loads the same authoritative decoder and returns the
      // completed immutable network; MapLibre upload remains on its own worker
      // path after this hand-off.
      if (typeof Worker === "function") {
        try {
          return await loadNetworkInWorker(packageUrls, reviewedUrl, lanesUrl);
        } catch (workerError) {
          console.warn("[railmap] background network load unavailable:", workerError);
        }
      }
      return await loadNetworkOnMain(packageUrls, reviewedUrl, lanesUrl);
    } catch (e) {
      console.warn("[railmap] rail package unavailable:", e);
      return null;
    }
  }

  // How far the zoom may move before a continuous stroke's baked pixel lane
  // gap is rebuilt. An eighth of a level, matching iOS's rebuild step
  // (RailMapView.swift): a quarter-level band let the visible lane gap swing
  // 0.77–1.71 px before it was rebuilt, visibly wider than the stroke itself.
  const STROKE_REBUILD_ZOOM_STEP = 0.125;
  // Rebuild cadence while a zoom gesture is in flight; `zoomend` settles it.
  const STROKE_REBUILD_DELAY_MS = 120;
  // A lane change drifts over at least this many pixels per lane whatever the
  // zoom: at a regional zoom the metre ramp is under a pixel.
  const STROKE_MIN_RAMP_PX = 24;
  // How far beyond the viewport, as a fraction of it, a part still counts as
  // near enough to be rebuilt with the camera.
  const STROKE_REBUILD_PAD = 1;
  // Per-part zoom staleness (_applyContinuousStrokes) is bucketed rather than
  // driven off the live, continuously-changing camera zoom: `zoomBucket =
  // round(zoom / STROKE_REBUILD_ZOOM_STEP)` and every part built for that
  // bucket is built at the bucket's own NOMINAL zoom (`zoomBucket *
  // STROKE_REBUILD_ZOOM_STEP`), never the exact live zoom. Two consequences:
  // a slow pinch that keeps re-entering the same eighth-level band does not
  // re-run RailStroke.buildStroke on every frame (STROKE_LRU_SIZE below), and
  // a part's build is a pure function of (zoomBucket, lane-LOD bucket) —
  // required for that cache to be sound, and for two parts of the same line
  // built in different rebuild passes to still be comparable/reproducible.
  const STROKE_LRU_SIZE = 3;

  // Slice a just-built pixel stroke (RailStroke.buildStroke's `{points,
  // measures}`) into one screen-space polyline per metre `range`, dropping
  // any slice RailStroke.sliceStroke collapses to under 2 points (a window
  // that snapped onto the part's own start/end, or a rounding sliver).
  function familySliceRanges(strokePoints, strokeMeasures, ranges) {
    const pieces = [];
    for (const range of ranges) {
      const sliced = RailStroke.sliceStroke(strokePoints, strokeMeasures, range.from, range.to);
      if (sliced.length >= 2) pieces.push(sliced);
    }
    return pieces;
  }

  // ── the per-part stroke LRU (_applyContinuousStrokes) ───────────────────
  // Up to STROKE_LRU_SIZE recent RailStroke.buildStroke results per part,
  // keyed by the (zoomBucket, laneLodBucket) pair the geometry was built
  // for — both integers, so a slow pinch that oscillates across one eighth-
  // level boundary reuses the SAME two cached builds instead of re-running
  // buildStroke's offset/fillet passes every frame. Stored on the part
  // object itself (`part._strokeLRU`) rather than in a shared Map so a
  // part's cache dies with the part (network reload / country switch), not
  // with a rebuild pass.
  function strokeCacheGet(part, zoomBucket, laneLodBucket) {
    const cache = part._strokeLRU;
    if (!cache) return null;
    for (let i = 0; i < cache.length; i++) {
      const entry = cache[i];
      if (entry.zoomBucket === zoomBucket && entry.laneLodBucket === laneLodBucket) {
        if (i !== cache.length - 1) {
          cache.splice(i, 1);
          cache.push(entry);
        }
        return entry;
      }
    }
    return null;
  }

  function strokeCachePut(part, entry) {
    let cache = part._strokeLRU;
    if (!cache) {
      cache = [];
      part._strokeLRU = cache;
    }
    cache.push(entry);
    if (cache.length > STROKE_LRU_SIZE) cache.shift();
  }

  // ───────────────────────────── the overlay manager ─────────────────────────────
  const RailMap = {
    loadBasemap,
    loadNetwork,
    buildBaseStyle,

    _map: null,
    _network: null,
    _networkPromise: null, // dedups concurrent network loads/retries
    _networkGeneration: 0, // invalidates a load started for the prior country
    _networkVisibleWanted: false,
    _networkStationsVisibleWanted: false,
    _handlers: {},
    _records: [],
    _expandRecords: [],
    _groupInfo: null, // groupKey → { sx, sy, mults } (rigid lane shifts)
    _laneSpacingPx: 0,
    // Continuous strokes (rail-stroke.js): the zoom the network's stroke
    // geometry was last built for, and the pending rebuild during a zoom.
    _strokeZoom: null,
    _strokeRebuildTimer: null,
    // Per-rebuild instrumentation (_applyContinuousStrokes): how long the
    // last pass took and how much of the network it actually touched. Read
    // by anything that wants to see the per-part scheduler's cost without
    // profiling — a debug console, a test harness — never written outside
    // that method.
    _strokeStats: null,
    // Bumped every time _applyRideStrokes actually changes a ridden route's
    // drawn path (a fresh setData, or a zoom/pan stroke rebuild). Playback
    // (app-playback.js compilePath) folds this into its cache key so a
    // compiled path sampling the drawn ink re-samples onto the new geometry
    // instead of riding stale ink after a zoom.
    _rideStrokeGeneration: 0,
    // Set by setData() — true when at least one current record can ride the
    // continuous stroke. See _scheduleStrokeRebuild.
    _hasStrokeRefRecords: false,
    _fanLanePool: [],
    _fanPickEnabled: false,
    _markers: [],
    // Intermediate stops and trip terminals share two physical circle layers,
    // but their role filters remain independently toggleable in the map UI.
    _markerVisibility: { stop: true, terminal: true, pass: true },
    _visible: true,
    _fitCurvesVisible: false,
    _hoverRegionsVisible: false,
    _hoverDebugState: null,
    _selectedTrainId: null,
    _hoverTrainId: null,
    _playbackRuns: [],
    _playbackDone: [],
    _playbackRunIndex: -1,
    _playbackProgress: 0,
    _playbackStationIndex: -1,
    _playbackStationPulse: 0,
    _playbackColor: "#1f6feb",
    _expandedGroup: null,
    _expandedTids: [], // the hovered group's train set (expand target)
    _engagedTids: [], // trains whose true-track lines are currently hidden
    _expandFilterTids: [], // trains the expand layers currently show
    _expandT: 0,
    _expandOpacity: 0,
    _expandAnimId: null,
    _groupTransition: null,
    _groupTransitionRaf: null,
    _tooltipEl: null,
    _tooltipRecord: null, // record the tooltip currently shows (dedup)
    _stationPopup: null,
    _stationPopupKey: null, // station|line the popup currently shows (dedup)
    _pendingHoverPoint: null, // latest mousemove point awaiting the rAF pass
    _hoverRafId: null,
    _lastGroupPoint: null, // px of the last real overlapped-run hit (fan hysteresis anchor)
    _groupSwitchCandidate: null,
    _groupSwitchAnchor: null,
    _basemapLayerIds: [],
    _basemapSourceIds: [],
    // The single installed basemap stack ({layerIds, sourceIds}); both themes
    // share it and theme switches recolor it in place (_recolorBasemapStack).
    _basemapStack: null,
    _basemapMode: "none",
    _theme: "light",
    _basemapInstalledTheme: null,
    _basemapRetryInflight: null, // dedups concurrent retryBasemap() calls
    // Cross-day: draw an overnight train's other-day half dashed. The app's
    // "顯示完整跨天行程" toggle flips this to false, which makes that half draw
    // exactly like any other line.
    _crossDayDash: true,
    _basemapGeneration: 0,
    _basemapTransitionDuration: BASEMAP_CROSSFADE_MS,
    _fadeOpacity: 0,

    // Every ridden route is rendered from an exact slice of the same complete
    // line geometry used by the hidden-by-default national-network overlay.
    // Keeping this adapter here makes the active country's network the single
    // display-geometry authority for every route consumer.
    canonicalizeRouteFeature(feature, options) {
      if (
        !this._network ||
        !global.RailNetwork ||
        typeof global.RailNetwork.canonicalizeRouteFeature !== "function"
      )
        return null;
      return global.RailNetwork.canonicalizeRouteFeature(
        this._network,
        feature,
        options,
      );
    },

    attach(
      map,
      network,
      handlers,
      basemapLayerIds,
      basemapSourceIds,
      theme,
      basemapStacks,
    ) {
      this._map = map;
      this._network = network || null;
      this._handlers = handlers || {};
      const stackValues = Object.values(basemapStacks || {});
      this._basemapStack = stackValues.length ? stackValues[0] : null;
      this._basemapLayerIds = this._basemapStack
        ? (this._basemapStack.layerIds || []).slice()
        : basemapLayerIds || [];
      this._basemapSourceIds = this._basemapStack
        ? (this._basemapStack.sourceIds || []).slice()
        : basemapSourceIds || [];
      this._basemapMode = this._basemapLayerIds.length ? "positron" : "none";
      this._theme = theme === "dark" ? "dark" : "light";
      this._basemapInstalledTheme = this._basemapLayerIds.length
        ? this._theme
        : null;
      const initialFade = map.getLayer(FADE_LAYER)
        ? Number(map.getPaintProperty(FADE_LAYER, "background-opacity"))
        : 0;
      this._fadeOpacity = Number.isFinite(initialFade) ? initialFade : 0;
      this._initFanLanePool();
      this._wireInteractions();
      // Anchors the app may already have computed before the overlay existed.
      this._repaintRailwayScreenWeights();
      // ALL opacity fades on these layers are driven manually by the rAF dim
      // engine (_applyDimPaint) and the fan slide — MapLibre skips its own
      // transitions for data-driven paint values anyway, and its implicit
      // default 300 ms transition on CONSTANT values would trail the rAF
      // frames. Pin every animated opacity prop to zero so the rAF loop is
      // the single source of animation truth.
      this._ensureXDayIcon();
      this._ensureStationIcons();
      // A basemap/theme swap installs a fresh style, which drops runtime
      // images; MapLibre asks for the missing one instead of silently drawing
      // nothing, so re-rasterize on demand.
      map.on("styleimagemissing", (e) => {
        if (!e) return;
        if (e.id === XDAY_ICON_ID) this._ensureXDayIcon();
        else if (String(e.id).startsWith("rn-station-"))
          this._ensureStationIcons(String(e.id));
      });
      const ZERO_T = { duration: 0, delay: 0 };
      [
        [TRAIN_ROUTES_LAYER, ["line-opacity"]],
        [TRAIN_XDAY_LAYER, ["line-opacity"]],
        [TRAIN_XDAY_STOP_LAYER, ["icon-opacity"]],
        [TRAIN_HOVER_LAYER, ["line-opacity"]],
        [TRAIN_SEL_CASING_LAYER, ["line-opacity"]],
        [TRAIN_SEL_LAYER, ["line-opacity"]],
        [TRAIN_PICK_FAN_LAYER, ["line-translate"]],
        [TRAIN_EXPAND_LAYER, ["line-opacity", "line-translate"]],
        [TRAIN_EXPAND_HOVER_LAYER, ["line-opacity", "line-translate"]],
        [TRAIN_PASS_LAYER, ["circle-opacity", "circle-stroke-opacity"]],
        [TRAIN_STOPS_LAYER, ["circle-opacity", "circle-stroke-opacity"]],
        [TRAIN_SEL_PASS_LAYER, ["circle-opacity", "circle-stroke-opacity"]],
        [TRAIN_SEL_STOPS_LAYER, ["circle-opacity", "circle-stroke-opacity"]],
      ].forEach(([id, props]) => {
        if (!map.getLayer(id)) return;
        props.forEach((prop) =>
          map.setPaintProperty(id, prop + "-transition", ZERO_T),
        );
      });
      // Pin the solid/dashed cross-day split from the start: a setDateScope
      // that landed before attach() only stored state (no map to filter yet),
      // and setData never re-applies these filters.
      this._applyBaseFilters();
      // Stop-dot LOD: the gate is a plain role filter (filter ["zoom"]
      // expressions never re-gate on zoom in this MapLibre build — see
      // stopMarkerZoomGate), so RailMap owns the crossing itself. The
      // per-frame check is a float compare; setFilter runs only on the flip.
      this._applyMarkerSelectionFilters();
      // §7b is staged at the boot state, so this only has to catch an intent
      // recorded before attach() — and on a slow boot the style may still be
      // layer-less here, in which case the staged state already stands and the
      // one-shot re-assert covers a toggle that landed in between.
      this._applyRiddenLabelVisibility();
      if (!map.getLayer(TRAIN_TERMINAL_LABEL_LAYER))
        map.once("styledata", () => this._applyRiddenLabelVisibility());
      map.on("zoom", () => {
        const gated = stopMarkerZoomGate(map.getZoom()) != null;
        if (gated !== this._stopMarkersGated)
          this._applyMarkerSelectionFilters();
        // An open fan needs nothing here: its lane offsets are pixel constants
        // along a direction that does not depend on zoom either, so a zoom
        // leaves every line-translate exactly where it was.
        // A continuous stroke's lane gap is a pixel constant baked into
        // geometry, so it IS zoom-dependent: rebuild once the zoom has moved
        // far enough for the gap to drift.
        this._scheduleStrokeRebuild();
      });
      map.on("zoomend", () => this._scheduleStrokeRebuild(true));
      map.on("moveend", () => this._scheduleStrokeRebuild(true));
      return this;
    },

    // ── data feeds (same contract as the old deck.gl overlay, plus the
    // full-line expand records + per-group rigid shift vectors) ──
    setData(records, expandRecords, groupInfo, laneSpacingPx) {
      // A data rebuild replaces group objects, so finish any in-flight
      // cross-group interpolation at its current target before uploading.
      if (this._groupTransitionRaf) {
        cancelAnimationFrame(this._groupTransitionRaf);
        this._groupTransitionRaf = null;
      }
      this._groupTransition = null;
      this._records = records || [];
      this._expandRecords = expandRecords || [];
      this._groupInfo = groupInfo || new Map();
      this._laneSpacingPx = Math.max(0, Number(laneSpacingPx) || 0);
      // Whether ANY record in this set can ride the network's continuous
      // stroke. _scheduleStrokeRebuild reads this to keep re-slicing rides
      // on zoom/pan even while the railway overlay layer itself is hidden —
      // a ride is drawn on the TRAINS source, independent of whether the
      // network's own segments/stations layers are toggled on.
      this._hasStrokeRefRecords =
        this._records.some((r) => r.strokeRef) ||
        this._expandRecords.some((r) => r.strokeRef);
      // A freshly built record set carries strokeRef but not yet the
      // network's pixel geometry to slice — substitute it now, once, so the
      // very first paint already shows rides on the network stroke rather
      // than one frame of the route-solver fit.
      this._applyRideStrokes();
      // Pre-grow outside the hover path. Cross-group transitions can still
      // add a rare overflow slot, but ordinary first-open fans do no style
      // mutation at pointer time.
      let maxMembers = 0;
      this._groupInfo.forEach((gi) => {
        maxMembers = Math.max(maxMembers, Object.keys((gi && gi.mults) || {}).length);
      });
      this._ensureFanLanePool(maxMembers);
      this._pushRoutes();
      this._pushFitCurves();
      // The exhaustive pointer-equivalent sweep is intentionally debug-only:
      // normal route/date changes should not pay for it. Turning on the fitted
      // curve overlay runs and publishes the report immediately.
      if (this._fitCurvesVisible) this._refreshFitCurveDiagnostics();
      // A fan is open while the record pipeline is REBUILT (e.g. clicking a
      // lane switches to the single-day scope, which recomputes the overlap
      // groups). If the expanded group no longer exists in the new data, the
      // expand source would go empty while _engagedTids kept the member
      // trains' true-track lines filtered out of the base layer — the
      // clicked route vanished until a mouseleave collapsed the stale fan.
      // Force-collapse the stale fan synchronously instead.
      if (this._expandedGroup && !this._groupInfo.has(this._expandedGroup)) {
        this._forceCollapseExpand();
        return;
      }
      // An in-place rebuild with a fan open: refresh the true geometry once
      // and re-sync the member
      // tid sets — the group can survive a rebuild with DIFFERENT membership
      // (e.g. off-date trains dropped when a day becomes active), and stale
      // engaged tids would hide lines that no longer have expand twins.
      if (this._expandedGroup) {
        const gi = this._groupInfo.get(this._expandedGroup);
        const tids = gi ? Object.keys(gi.mults) : [];
        this._expandedTids = tids;
        this._expandFilterTids = tids;
        this._syncFanLaneAssignments(tids);
        this._uploadFanSources(tids, [this._expandedGroup]);
        this._applyFanLaneTranslations(this._expandedGroup, this._expandT);
        if (this._engagedTids.length) {
          this._engagedTids = tids.slice();
          this._applyBaseFilters();
        } else {
          this._applyHoverFilter();
        }
      }
    },
    // Immediate (no animation) reset of the hover-expand state: clear the
    // group, un-hide every engaged train's true-track lines, empty the expand
    // source and restore the base/hover/selection filters. Used when new data
    // invalidates the currently expanded group.
    _forceCollapseExpand() {
      if (this._expandAnimId) {
        cancelAnimationFrame(this._expandAnimId);
        this._expandAnimId = null;
      }
      if (this._groupTransitionRaf) {
        cancelAnimationFrame(this._groupTransitionRaf);
        this._groupTransitionRaf = null;
      }
      this._groupTransition = null;
      this._groupSwitchCandidate = null;
      this._groupSwitchAnchor = null;
      this._fanSwitchFromDir = null;
      this._fanCurve = null;
      this._fanCurveS = null;
      this._fanCurveSign = 1;
      this._expandedGroup = null;
      this._expandedTids = [];
      this._expandFilterTids = [];
      this._engagedTids = [];
      this._expandT = 0;
      this._animGroup = null;
      this._setExpandOpacity(0);
      this._pushExpandFC(null, 0);
      this._setFanPickEnabled(false);
      this._syncFanLaneAssignments([]);
      this._uploadFanSources([], []);
      this._applyBaseFilters();
    },
    setMarkers(records) {
      this._markers = records || [];
      this._pushMarkers();
    },
    setSelected(id) {
      if ((id || null) === this._selectedTrainId) return;
      this._selectedTrainId = id || null;
      this._applySelectionFilters();
      this._applyMarkerSelectionFilters();
      // Selection spotlight: fade the non-selected trains (lines + dots) to
      // SELECT_DIM — same paint-only mechanism as the hover dim.
      this._applyHoverDim();
    },
    // ── playback trail ──
    // The playing train's covered stretch. `runs` are its CONTIGUOUS ridden
    // paths (one per run, so a route with an unridden middle never gets a
    // chord drawn across the hole). Geometry is uploaded once per run change;
    // advancing the head inside a run is a single gradient repaint, which is
    // what keeps a 60 fps playhead off the GeoJSON worker entirely.
    // `doneRuns` are the stretches EARLIER trains in the queue already
    // covered — [{ coords, color }] — so a day's itinerary stays lit behind
    // the running train instead of resetting at every change of train.
    // `runs` is the current train's own set of contiguous runs.
    setPlaybackTrail(doneRuns, runs, color) {
      this._playbackDone = Array.isArray(doneRuns) ? doneRuns : [];
      this._playbackRuns = Array.isArray(runs) ? runs : [];
      this._playbackColor = color || "#1f6feb";
      this._playbackRunIndex = -1;
      this._playbackProgress = 0;
      this.setPlaybackProgress(0, 0);
      return this;
    },
    // Per FRAME. Re-uploads only when the head crosses into a new run.
    setPlaybackProgress(runIndex, t) {
      const m = this._map;
      if (!m) return this;
      this._playbackProgress = Math.max(0, Math.min(1, Number(t) || 0));
      const idx = Math.max(0, Math.min(this._playbackRuns.length - 1, runIndex | 0));
      if (idx !== this._playbackRunIndex) {
        this._playbackRunIndex = idx;
        const features = [];
        this._playbackDone.forEach((run) => {
          if (!run || !run.coords || run.coords.length < 2) return;
          features.push({
            type: "Feature",
            properties: { state: "done", color: run.color || this._playbackColor },
            geometry: { type: "LineString", coordinates: run.coords },
          });
        });
        for (let i = 0; i <= idx; i += 1) {
          const line = this._playbackRuns[i];
          if (!line || line.length < 2) continue;
          features.push({
            type: "Feature",
            properties: {
              state: i === idx ? "head" : "done",
              color: this._playbackColor,
            },
            geometry: { type: "LineString", coordinates: line },
          });
        }
        const src = this._src(PLAYBACK_SOURCE);
        if (src) src.setData({ type: "FeatureCollection", features });
      }
      if (m.getLayer(PLAYBACK_HEAD_LAYER))
        m.setPaintProperty(
          PLAYBACK_HEAD_LAYER,
          "line-gradient",
          playbackTrailGradient(this._playbackColor, this._playbackProgress),
        );
      // The casing ends where the colour ends, so it takes the same ramp.
      if (m.getLayer(PLAYBACK_CASING_HEAD_LAYER))
        m.setPaintProperty(
          PLAYBACK_CASING_HEAD_LAYER,
          "line-gradient",
          playbackTrailGradient(
            MAP_SURFACE_COLORS[this._theme].casing,
            this._playbackProgress,
          ),
        );
      return this;
    },
    // The running train's stopping stations. `stations` are
    // [{ coord, name, color }] in running order; the index they are uploaded
    // with is what every later "reached up to here" update filters on.
    setPlaybackStations(stations) {
      const list = Array.isArray(stations) ? stations : [];
      // Playback colours are baked at style-build time. Restamping before a
      // new source upload also covers playback that starts after a switch.
      this._restampPlaybackTheme();
      const src = this._src(PLAYBACK_STATIONS_SOURCE);
      if (src)
        src.setData({
          type: "FeatureCollection",
          features: list.map((st, idx) => ({
            type: "Feature",
            properties: {
              idx,
              name: st.name || "",
              color: st.color || this._playbackColor,
            },
            geometry: { type: "Point", coordinates: st.coord },
          })),
        });
      this._playbackStationIndex = -2; // force the next update through
      this.setPlaybackStationIndex(-1, 0);
      return this;
    },
    // Which stations have been reached, and how hot the newest one is. `pulse`
    // decays 1 → 0 over the moment after an arrival; while it is moving this
    // repaints per frame, and once it settles the call is a no-op.
    setPlaybackStationIndex(index, pulse) {
      const m = this._map;
      if (!m) return this;
      const idx = Number.isFinite(index) ? index : -1;
      const p = Math.max(0, Math.min(1, Number(pulse) || 0));
      const settled = p === 0 && this._playbackStationPulse === 0;
      if (idx === this._playbackStationIndex && settled) return this;
      const advanced = idx !== this._playbackStationIndex;
      this._playbackStationIndex = idx;
      this._playbackStationPulse = p;
      if (m.getLayer(PLAYBACK_STATION_DONE_LAYER)) {
        if (advanced)
          m.setFilter(PLAYBACK_STATION_DONE_LAYER, ["<=", ["get", "idx"], idx]);
        m.setPaintProperty(
          PLAYBACK_STATION_DONE_LAYER,
          "circle-radius",
          playbackStationDoneRadius(idx, p),
        );
      }
      if (advanced && m.getLayer(PLAYBACK_STATION_LABEL_LAYER))
        m.setPaintProperty(
          PLAYBACK_STATION_LABEL_LAYER,
          "text-color",
          playbackStationTextColor(idx, this._theme),
        );
      return this;
    },
    _restampPlaybackTheme() {
      const m = this._map;
      if (!m) return;
      const colors = MAP_SURFACE_COLORS[this._theme === "dark" ? "dark" : "light"];
      if (m.getLayer(PLAYBACK_CASING_DONE_LAYER))
        m.setPaintProperty(
          PLAYBACK_CASING_DONE_LAYER,
          "line-color",
          colors.casing,
        );
      if (m.getLayer(PLAYBACK_CASING_HEAD_LAYER))
        m.setPaintProperty(
          PLAYBACK_CASING_HEAD_LAYER,
          "line-gradient",
          playbackTrailGradient(colors.casing, this._playbackProgress),
        );
      if (m.getLayer(PLAYBACK_STATION_LAYER))
        m.setPaintProperty(
          PLAYBACK_STATION_LAYER,
          "circle-color",
          colors.stationRing,
        );
      if (m.getLayer(PLAYBACK_STATION_DONE_LAYER))
        m.setPaintProperty(
          PLAYBACK_STATION_DONE_LAYER,
          "circle-stroke-color",
          colors.stationRing,
        );
      if (m.getLayer(PLAYBACK_HEAD_DOT_LAYER))
        m.setPaintProperty(
          PLAYBACK_HEAD_DOT_LAYER,
          "circle-stroke-color",
          colors.stationRing,
        );
      if (m.getLayer(PLAYBACK_STATION_LABEL_LAYER)) {
        m.setPaintProperty(
          PLAYBACK_STATION_LABEL_LAYER,
          "text-color",
          playbackStationTextColor(this._playbackStationIndex, this._theme),
        );
        m.setPaintProperty(
          PLAYBACK_STATION_LABEL_LAYER,
          "text-halo-color",
          networkLabelHaloColor(this._theme),
        );
      }
    },
    // The train's own position, pushed every frame. One point through the
    // GeoJSON worker is sub-millisecond, and keeping the playhead ON the
    // canvas is what lets canvas.captureStream() record it.
    setPlaybackHead(coord, color) {
      const src = this._src(PLAYBACK_HEAD_SOURCE);
      if (!src) return this;
      if (!coord) {
        src.setData(EMPTY_FC);
        return this;
      }
      src.setData({
        type: "FeatureCollection",
        features: [
          {
            type: "Feature",
            properties: { color: color || this._playbackColor },
            geometry: { type: "Point", coordinates: coord },
          },
        ],
      });
      return this;
    },
    clearPlayback() {
      // Already clear: skip the two setData calls. They are not free — a
      // dirtied source keeps Style.loaded() false until the next render, and
      // the map methods that check it (addLayer above all) throw meanwhile.
      // Playback stops from inside renderTrainLayers, which goes straight on
      // to re-issue the route layers, so clearing twice would put that push
      // in exactly that window.
      if (!this._playbackRuns.length && this._playbackRunIndex < 0)
        return this;
      this._playbackRuns = [];
      this._playbackDone = [];
      this._playbackRunIndex = -1;
      this._playbackProgress = 0;
      this._playbackStationIndex = -1;
      this._playbackStationPulse = 0;
      const src = this._src(PLAYBACK_SOURCE);
      if (src) src.setData(EMPTY_FC);
      const stations = this._src(PLAYBACK_STATIONS_SOURCE);
      if (stations) stations.setData(EMPTY_FC);
      const head = this._src(PLAYBACK_HEAD_SOURCE);
      if (head) head.setData(EMPTY_FC);
      return this;
    },
    // Date-scope dim as PAINT state: records carry their train's date in
    // `tdate`; the active date + dim value live in the opacity expressions.
    // Changing scope therefore FADES (the rAF dim engine ramps the `date`
    // strength) instead of waiting for the record rebuild, whose re-uploaded
    // features carry the same per-train paint inputs mid-fade.
    setDateScope(activeDate, dimOpacity, crossDayDash) {
      const next = activeDate || null;
      const dim = Math.max(0, Math.min(1, Number(dimOpacity ?? 0.18)));
      const dash =
        crossDayDash === undefined ? this._crossDayDash : Boolean(crossDayDash);
      if (
        next === this._activeDate &&
        dim === this._dateDim &&
        dash === this._crossDayDash
      )
        return this;
      this._activeDate = next;
      this._dateDim = dim;
      this._crossDayDash = dash;
      // Every train-line layer filters on the cross-day split, so re-apply the
      // whole base/selection/hover set rather than just the two line layers.
      this._applyBaseFilters();
      this._applyHoverDim();
      return this;
    },
    // Toggle-only entry point ("顯示完整跨天行程"): re-splits the solid/dashed
    // layers without touching the date scope.
    setCrossDayDash(enabled) {
      const dash = Boolean(enabled);
      if (dash === this._crossDayDash) return this;
      this._crossDayDash = dash;
      this._applyBaseFilters();
      return this;
    },
    // Which records belong to the DASHED layer right now: the parts of a
    // cross-day train that run on a different date than the selected one,
    // while that train also runs on the selected date (`dspan` holds every
    // date it touches). With no day selected — the 全部 view — nothing is
    // dashed: there is no "other day" to contrast against.
    _xDaySelector() {
      const date = this._activeDate;
      if (!date || !this._crossDayDash) return MATCH_NONE;
      return [
        "all",
        ["!=", ["get", "edate"], date],
        ["in", "|" + date + "|", ["get", "dspan"]],
      ];
    },
    _applyXDayFilters() {
      const m = this._map;
      if (!m) return;
      if (m.getLayer(TRAIN_ROUTES_LAYER))
        m.setFilter(TRAIN_ROUTES_LAYER, [
          "all",
          this._notExpanded(),
          ["!", this._xDaySelector()],
        ]);
      if (m.getLayer(TRAIN_XDAY_LAYER))
        m.setFilter(TRAIN_XDAY_LAYER, [
          "all",
          this._notExpanded(),
          this._xDaySelector(),
        ]);
    },
    // The cross-day diamond, rasterized once per style: an ink lozenge with a
    // white rim, matching the ride-boundary dot's colour pair but never its
    // shape. Drawn at 2× so it stays crisp on retina.
    _ensureXDayIcon() {
      const m = this._map;
      if (!m || typeof m.addImage !== "function") return;
      if (m.hasImage && m.hasImage(XDAY_ICON_ID)) return;
      const ratio = 2;
      const r = XDAY_ICON_BASE_RADIUS;
      const size = Math.round(r * 2 * ratio);
      const canvas =
        typeof document !== "undefined"
          ? document.createElement("canvas")
          : null;
      if (!canvas) return;
      canvas.width = size;
      canvas.height = size;
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      const c = size / 2;
      const rim = 2 * ratio;
      const half = c - rim / 2 - ratio * 0.5;
      const diamond = (radius) => {
        ctx.beginPath();
        ctx.moveTo(c, c - radius);
        ctx.lineTo(c + radius, c);
        ctx.lineTo(c, c + radius);
        ctx.lineTo(c - radius, c);
        ctx.closePath();
      };
      diamond(half);
      // The station inks from railmap-style.js are mirrored literals here;
      // keep the three in sync.
      ctx.fillStyle = "rgb(26,26,26)";
      ctx.fill();
      ctx.lineJoin = "miter";
      ctx.lineWidth = rim;
      ctx.strokeStyle = "rgb(255,255,255)";
      ctx.stroke();
      try {
        m.addImage(
          XDAY_ICON_ID,
          ctx.getImageData(0, 0, size, size),
          { pixelRatio: ratio },
        );
      } catch {
        // A concurrent styleimagemissing can add it first; that is fine.
      }
    },
    // Laned platforms use symbols because MapLibre cannot data-drive a
    // circle's screen-space translation per feature. These bitmaps are made
    // from the same size, ring and surface colours as the ordinary station
    // circles, so shifting a platform never changes its visual vocabulary.
    _ensureStationIcons(requestedId) {
      const m = this._map;
      if (!m || typeof m.addImage !== "function") return;
      const base = STATION_ICON_BASE_PX;
      const ring =
        (base * RAILWAY_STYLE.stationRingPx) / RAILWAY_STYLE.stationDiameterPx;
      const ratio = 2;
      const span = base + 2 * ring;
      const size = Math.round(span * ratio);
      const requested = String(requestedId || "").match(
        /^rn-station-(light|dark)-([0-9a-f]{6})(-interchange)?$/i,
      );
      const colorKeys = new Set();
      if (requested) colorKeys.add(requested[2].toLowerCase());
      else if (this._network && this._network.stations)
        for (const feature of this._network.stations.features || []) {
          const key = feature.properties && feature.properties.colorKey;
          if (/^[0-9a-f]{6}$/i.test(String(key || "")))
            colorKeys.add(String(key).toLowerCase());
        }
      if (!colorKeys.size) colorKeys.add("7c8a82");
      const themes = requested ? [requested[1].toLowerCase()] : ["light", "dark"];
      const interchangeStates = requested ? [Boolean(requested[3])] : [false, true];
      for (const theme of themes)
        for (const colorKey of colorKeys)
          for (const interchange of interchangeStates) {
            const id = stationIconId(theme, interchange, colorKey);
            if (m.hasImage && m.hasImage(id)) continue;
            const canvas =
              typeof document !== "undefined" ? document.createElement("canvas") : null;
            if (!canvas) return;
            canvas.width = size;
            canvas.height = size;
            const ctx = canvas.getContext("2d");
            if (!ctx) return;
            const colors = MAP_SURFACE_COLORS[theme === "dark" ? "dark" : "light"];
            const lineColor = `#${colorKey}`;
            const fill = interchange ? colors.stationRing : lineColor;
            const stroke = interchange ? lineColor : networkCasingColor(theme);
            const centre = size / 2;
            const ringPx = ring * ratio;
            const radius = (base * ratio) / 2;
            ctx.beginPath();
            ctx.arc(centre, centre, radius + ringPx / 2, 0, Math.PI * 2);
            ctx.lineWidth = ringPx;
            ctx.strokeStyle = stroke;
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(centre, centre, radius, 0, Math.PI * 2);
            ctx.fillStyle = fill;
            ctx.fill();
            try {
              m.addImage(id, ctx.getImageData(0, 0, size, size), { pixelRatio: ratio });
            } catch {
              // A concurrent styleimagemissing can add it first.
            }
          }
    },
    // Re-assert every railway weight and lane offset from the ONE table in
    // railmap-style.js. There is nothing to re-anchor: the scale ramp those
    // values ride is a pure function of zoom (see the screen-space weight
    // contract at the top of railmap-style.js), so the built style already
    // carries it. This exists for the paths that add or replace layers behind
    // the style's back — attach() over a live map, and the pooled fan lanes
    // below, which are not in the table because they come and go.
    _repaintRailwayScreenWeights() {
      const m = this._map;
      if (!m) return;
      for (const entry of railwayScreenPaintEntries()) {
        if (!m.getLayer(entry.layer)) continue;
        if (entry.kind === "layout")
          m.setLayoutProperty(entry.layer, entry.property, entry.value);
        else m.setPaintProperty(entry.layer, entry.property, entry.value);
      }
      // The fan's lanes are pooled layers added on demand, so they are not in
      // the table — they are the same two weights under per-slot ids.
      this._fanLanePool.forEach((slot) => {
        if (m.getLayer(slot.visibleId))
          m.setPaintProperty(slot.visibleId, "line-width", riddenLineWidth());
        if (m.getLayer(slot.hoverId))
          m.setPaintProperty(slot.hoverId, "line-width", riddenHoverLineWidth());
      });
      // The selected route's width carries its focus boost, and the table just
      // overwrote it with the plain one.
      this.setFocusBoost(this._focusBoost);
    },
    // Focus emphasis for the selected train: instead of baking the boost into
    // every record (which would force a full pipeline rebuild on each pick),
    // the SEL line and role-aware marker paint expressions add it at draw time.
    setFocusBoost(px) {
      this._focusBoost = Number(px) || 0;
      const m = this._map;
      if (!m) return;
      if (m.getLayer(TRAIN_SEL_LAYER))
        m.setPaintProperty(
          TRAIN_SEL_LAYER,
          "line-width",
          riddenFocusLineWidth(this._focusBoost),
        );
      if (m.getLayer(TRAIN_SEL_STOPS_LAYER))
        m.setPaintProperty(
          TRAIN_SEL_STOPS_LAYER,
          "circle-radius",
          selectedStopRadiusExpr(this._focusBoost),
        );
      if (m.getLayer(TRAIN_SEL_PASS_LAYER))
        m.setPaintProperty(
          TRAIN_SEL_PASS_LAYER,
          "circle-radius",
          markerRadiusExpr(this._focusBoost / 2),
        );
    },
    // Selection = pure layer filtering on the single marker source: the
    // selected train's dots leave the base layers and enter the SEL layers.
    _applyMarkerSelectionFilters() {
      const m = this._map;
      if (!m) return;
      const id = this._selectedTrainId || NO_TRAIN;
      // Keep the attach() zoom watcher's flip detection in sync with what
      // these filters actually encode.
      const stopZoomGate = stopMarkerZoomGate(m.getZoom());
      this._stopMarkersGated = stopZoomGate != null;
      const shown = this._markerVisibility || {
        stop: true,
        terminal: true,
        pass: true,
      };
      let stopRoleFilter = null;
      if (shown.stop === false && shown.terminal === false) {
        stopRoleFilter = MATCH_NONE;
      } else if (shown.stop === false) {
        stopRoleFilter = ["==", ["get", "role"], "terminal"];
      } else if (shown.terminal === false) {
        stopRoleFilter = ["!=", ["get", "role"], "terminal"];
      }
      const f = (cat, mine) => {
        const filters = [
          "all",
          ["==", ["get", "category"], cat],
          [mine ? "==" : "!=", ["get", "tid"], id],
        ];
        if (cat === "stop" && stopRoleFilter) filters.push(stopRoleFilter);
        // Stop-dot zoom LOD, evaluated against the LIVE zoom: setFilter
        // replaces the boot-time filter wholesale, so every rebuild must
        // re-derive the gate or intermediate stop dots would resurface at low
        // zoom after a selection change or marker toggle. The zoom watcher in
        // attach() calls back in here when the view crosses the threshold.
        if (cat === "stop" && stopZoomGate) filters.push(stopZoomGate);
        return filters;
      };
      if (m.getLayer(TRAIN_PASS_LAYER))
        m.setFilter(TRAIN_PASS_LAYER, f("pass", false));
      if (m.getLayer(TRAIN_STOPS_LAYER))
        m.setFilter(TRAIN_STOPS_LAYER, f("stop", false));
      if (m.getLayer(TRAIN_SEL_PASS_LAYER))
        m.setFilter(TRAIN_SEL_PASS_LAYER, f("pass", true));
      if (m.getLayer(TRAIN_SEL_STOPS_LAYER))
        m.setFilter(TRAIN_SEL_STOPS_LAYER, f("stop", true));
    },
    setVisible(v) {
      this._visible = !!v;
      const vis = this._visible ? "visible" : "none";
      [
        // Route lines only — station dots (the cross-day diamond included)
        // belong to setMarkerVisibility, not to the 路線 layer switch.
        TRAIN_ROUTES_LAYER,
        TRAIN_XDAY_LAYER,
        TRAIN_PICK_LAYER,
        TRAIN_PICK_FAN_LAYER,
        TRAIN_EXPAND_LAYER,
        TRAIN_EXPAND_HOVER_LAYER,
        TRAIN_HOVER_LAYER,
        TRAIN_SEL_CASING_LAYER,
        TRAIN_SEL_LAYER,
      ].forEach((id) => this._setVisibility(id, vis));
      this._fanLanePool.forEach((slot) => {
        [slot.pickId, slot.visibleId, slot.hoverId].forEach((id) =>
          this._setVisibility(id, vis),
        );
      });
    },
    setFitCurvesVisible(v) {
      this._fitCurvesVisible = Boolean(v);
      const vis = this._fitCurvesVisible ? "visible" : "none";
      this._setVisibility(FIT_CURVES_CASING_LAYER, vis);
      this._setVisibility(FIT_CURVES_LAYER, vis);
      if (this._fitCurvesVisible) {
        this._pushFitCurves();
        this._refreshFitCurveDiagnostics();
      }
    },
    // Deferred (worker) fit results attach to the same gi objects this
    // instance already holds, so hover needs nothing — only the debug
    // overlay and its published diagnostics report must refresh.
    notifyFitCurvesUpdated() {
      this._pushFitCurves();
      if (this._fitCurvesVisible) this._refreshFitCurveDiagnostics();
    },
    setHoverRegionsVisible(v) {
      this._hoverRegionsVisible = Boolean(v);
      const vis = this._hoverRegionsVisible ? "visible" : "none";
      this._setVisibility(HOVER_REGIONS_FILL_LAYER, vis);
      this._setVisibility(HOVER_REGIONS_LINE_LAYER, vis);
      if (!this._hoverRegionsVisible) {
        const src = this._src(HOVER_REGIONS_SOURCE);
        if (src) src.setData(EMPTY_FC);
      }
      this._pushHoverRegions(this._hoverDebugState);
    },
    setMarkerVisibility(category, v) {
      if (!this._markerVisibility)
        this._markerVisibility = { stop: true, terminal: true, pass: true };
      if (!(category in this._markerVisibility)) return;
      this._markerVisibility[category] = Boolean(v);
      if (category === "stop" || category === "terminal") {
        const anyStops =
          this._markerVisibility.stop || this._markerVisibility.terminal;
        const vis = anyStops ? "visible" : "none";
        this._setVisibility(TRAIN_STOPS_LAYER, vis);
        this._setVisibility(TRAIN_SEL_STOPS_LAYER, vis);
        // The cross-day diamond stands in for a station dot, so it follows the
        // same "are station markers shown at all" switch.
        this._setVisibility(TRAIN_XDAY_STOP_LAYER, vis);
        this._applyMarkerSelectionFilters();
      } else if (category === "pass") {
        const vis = v ? "visible" : "none";
        this._setVisibility(TRAIN_PASS_LAYER, vis);
        this._setVisibility(TRAIN_SEL_PASS_LAYER, vis);
      }
      // A name without its bead would be a place, not a station — the same
      // rule the network's own labels follow.
      this._applyRiddenLabelVisibility();
    },
    // The ridden markers' own station names (§7b). They stand in for the
    // network's labels rather than joining them, so they draw exactly when
    // rn-stations-label does NOT — otherwise one station would be named twice
    // by two layers that disagree about which platform holds the name, and the
    // two copies sit far enough apart that the collision pass keeps both.
    // With 全部鐵路線 booting off, this is the map's DEFAULT state.
    _applyRiddenLabelVisibility() {
      const shown = this._markerVisibility || {
        stop: true,
        terminal: true,
        pass: true,
      };
      const named = !this._networkStationsVisibleWanted;
      const vis = (on) => (named && on !== false ? "visible" : "none");
      // The cross-day diamond's name rides in the terminal tier, with the
      // boundary it marks.
      this._setVisibility(TRAIN_TERMINAL_LABEL_LAYER, vis(shown.terminal));
      this._setVisibility(TRAIN_STOP_LABEL_LAYER, vis(shown.stop));
      this._setVisibility(TRAIN_PASS_LABEL_LAYER, vis(shown.pass));
    },
    setNetworkVisible(v) {
      this._networkVisibleWanted = Boolean(v);
      const visibility = this._networkVisibleWanted ? "visible" : "none";
      // The line's own name rides with the line: it names the stroke, so it
      // has nothing to say once the stroke is gone. (It only exists when the
      // style has glyphs — _setVisibility no-ops on a layer that was never
      // added, which is exactly the basemap-less case.)
      for (const layer of [
        SEGMENTS_CASING_LAYER,
        SEGMENTS_LAYER,
        SEGMENTS_SUSPENDED_CASING_LAYER,
        SEGMENTS_SUSPENDED_LAYER,
        SEGMENTS_WITHHELD_LAYER,
        SEGMENTS_WITHHELD_CASING_LAYER,
        SEGMENTS_LABEL_LAYER,
      ])
        this._setVisibility(layer, visibility);
      if (this._networkVisibleWanted) this._scheduleStrokeRebuild(true);
    },
    // ── continuous strokes ──────────────────────────────────────────────────
    // North American railways arrive as a stroke MODEL (rail-network.js
    // `strokeModel`) rather than as finished geometry: one canonical polyline
    // per part plus its lane rows in metres. The drawn polyline — lane offset
    // and corner rounding baked into the vertices, in world pixels at the
    // current zoom — is built here, so that a railway is ONE feature the
    // renderer can never break, and rebuilt when the zoom moves far enough
    // that the pixel lane gap has drifted. See rail-stroke.js.
    _applyContinuousStrokes(force) {
      const m = this._map;
      const network = this._network;
      const model = network && network.strokeModel;
      if (!m || !model || typeof RailStroke === "undefined") return false;
      const startedAt =
        typeof performance !== "undefined" && performance.now ? performance.now() : 0;
      const zoom = m.getZoom();
      // Discrete, hysteretic lane-offset LOD (railmap-style.js
      // `laneScaleForZoom`): below z9 lanes draw with no offset at all, z9–z12
      // offsets at half the resolved gap, z12+ at the full gap — collapsing
      // the multi-kilometre lane spread a hub throat's lane-7 line would
      // otherwise carry at a regional zoom. `this._laneLodBucket` is the
      // controller's own memory of which band the stroke was last built at,
      // so the hysteresis has something to hold against across rebuilds —
      // tracked off the live zoom on every call, whether or not anything
      // below actually rebuilds, or a resting camera near a boundary could
      // never accumulate the crossing.
      const laneLod = laneScaleForZoom(zoom, this._laneLodBucket);
      this._laneLodBucket = laneLod.bucket;
      // Per-part zoom staleness (STROKE_LRU_SIZE doc above) is bucketed: every
      // part built THIS pass is built for `zoomBucket`, at that bucket's own
      // NOMINAL zoom — never the exact live `zoom` — so revisiting the same
      // bucket always reproduces the same geometry, which is what makes the
      // LRU below sound and a rebuilt part's output checkable against a
      // full-line rebuild "at the same nominal zoom".
      const zoomBucket = Math.round(zoom / STROKE_REBUILD_ZOOM_STEP);
      const nominalZoom = zoomBucket * STROKE_REBUILD_ZOOM_STEP;
      const scale = railwayScaleAt(nominalZoom);
      const laneGapPx =
        scale * (RAILWAY_STYLE.railWidthPx + RAILWAY_STYLE.parallelGapPx) *
        laneLod.scale;
      const cornerRadiusPx = scale * RAILWAY_STYLE.strokeCornerRadiusPx;
      // The radius the map PROMISES to present (one stroke width). Passing it
      // is what turns that promise into an operation: where a corner's own
      // edges are too short to carry it, rail-stroke.js rounds the run of
      // vertices as one corner rather than leaving a kink at each of them.
      const minCornerRadiusPx = scale * RAILWAY_STYLE.minCornerRadiusPx;
      const lineFeatures = network.segments.features;
      // Only what is near the camera is rebuilt for a zoom change; a part
      // off screen keeps the geometry of the bucket it was last built for,
      // and is caught up the next time it comes into view (`moveend`). The
      // first build, and any forced one, covers everything so no feature is
      // ever without geometry.
      //
      // A part is also pulled into this pass — even off screen — when it
      // TOUCHES a rebuilt neighbour at a joint that actually carries a lane
      // offset (see boundaryIsLaned below): offsetPolyline bakes that offset
      // into the vertex in PIXELS at this pass's own scale, so two touching
      // parts built at two different scales would part company at the
      // shared vertex. A joint at lane 0 needs no such rescue —
      // RailStroke.project/unproject are exact inverses at any single zoom,
      // so an unlaned boundary vertex round-trips to the same lon/lat
      // whichever bucket built it, and a cached (kept) neighbour's own
      // geometry already agrees with a freshly rebuilt one there for free.
      const bounds = m.getBounds();
      const west = bounds.getWest();
      const east = bounds.getEast();
      const south = bounds.getSouth();
      const north = bounds.getNorth();
      const padLon = (east - west) * STROKE_REBUILD_PAD;
      const padLat = (north - south) * STROKE_REBUILD_PAD;
      const near = (bbox) =>
        bbox[2] >= west - padLon &&
        bbox[0] <= east + padLon &&
        bbox[3] >= south - padLat &&
        bbox[1] <= north + padLat;
      // Canonical parts a follow names, resolved once per rebuild and
      // projected on demand at this pass's nominal zoom.
      const partsByLine = new Map(model.lines.map((line) => [line.lineId, line.parts]));
      const projectedCanon = new Map();
      const canonPixels = (lineId, partIndex) => {
        const key = `${lineId}#${partIndex}`;
        let held = projectedCanon.get(key);
        if (held) return held;
        const part = partsByLine.get(lineId)?.[partIndex];
        if (!part) return null;
        held = {
          points: part.coordinates.map((point) => RailStroke.project(point, nominalZoom)),
          measures: part.measures,
        };
        projectedCanon.set(key, held);
        return held;
      };
      let linesTouched = 0;
      let partsTotal = 0;
      let verticesBuilt = 0;
      let anchorsChanged = false;
      // Mirrors `anchorsChanged`'s own gate, for the withheld source: most
      // rebuild passes touch ordinary lines with no `displayBlockedIntervals`
      // at all (18 of jp's 1200+ lines carry one), so re-uploading
      // `network.segmentsWithheld` on every one of those passes was pure
      // waste — the collection had not moved. `network.segments` itself gets
      // no equivalent flag: a triggered line's OWN feature.geometry is always
      // reassigned (the rebuild loop below only ever runs for `trigger[i]`
      // parts, which by construction are never already at this pass's target
      // bucket — see `atTarget`), so segments genuinely changed whenever
      // `linesTouched` is nonzero and the existing `if (!strokeResult)
      // return` in `_scheduleStrokeRebuild` is already that gate.
      let withheldChanged = false;
      const rebuiltParts = new Set();
      for (const line of model.lines) {
        const feature = lineFeatures[line.featureIndex];
        partsTotal += line.parts.length;
        if (!feature) continue;
        const parts = line.parts;
        const n = parts.length;
        // Which parts want a rebuild THIS pass, for their own reason: never
        // built, the shared lane-LOD bucket moved (ungated — see the comment
        // on that clause below, unchanged from the old per-line test), or
        // individually near the camera with its own zoom bucket stale.
        const trigger = new Array(n);
        let anyTrigger = false;
        for (let i = 0; i < n; i++) {
          const part = parts[i];
          const t =
            force ||
            part.builtZoom == null ||
            // Zooming OUT is not gated on `near`. Everything else in this
            // test may wait for a part to come into view, because a stale
            // FINER-zoom geometry is only ever too detailed for the camera —
            // harmless, and caught on the next `moveend`. That stopped being
            // true when the stroke sources dropped to `tolerance: 0`
            // (railmap-style.js `strokeSourceTolerancePx`): geojson-vt no
            // longer generalises what it is handed, so a part built at z13
            // and then tiled at z6 puts its whole z13 vertex count into every
            // z6 tile. The vertex ceiling this file respects is respected by
            // the STROKE BUILDER now, at the zoom it builds for, so a part
            // whose bucket is finer than the camera's has to be rebuilt at
            // once, wherever it sits. Zoom-in is unchanged — a coarser stale
            // part still waits for `near`, exactly as before.
            part.builtZoomBucket > zoomBucket ||
            // The lane-LOD bucket is staleness like `builtZoomBucket` is —
            // its own bucket, checked the same `near` way, so an off-screen
            // part crossing z9/z12 keeps its old lane gap until it actually
            // comes into view instead of every part in the network
            // rebuilding synchronously on that one pan (jp's 669 parts cost
            // ~152ms doing exactly that). It is a SEPARATE bucket from
            // `zoomBucket`, not folded into it, because the two move at
            // different granularities: the laneLod threshold can cross
            // within a single STROKE_REBUILD_ZOOM_STEP, so a part whose
            // `builtZoomBucket` already reads fresh would otherwise keep
            // the wrong lane gap for a step. The dilation walk below still
            // pulls in an off-screen neighbour across a LANED joint
            // regardless of `near`, so a joint that actually carries an
            // offset never straddles two lane-LOD buckets.
            (near(part.bbox) &&
              (part.builtLaneLodBucket !== laneLod.bucket ||
                part.builtZoomBucket !== zoomBucket));
          trigger[i] = t;
          if (t) anyTrigger = true;
        }
        if (!anyTrigger) continue;
        const partSpan = (part) =>
          part.measures[part.measures.length - 1] - part.measures[0];
        const touches = (before, after) => {
          const a = before.coordinates[before.coordinates.length - 1];
          const b = after.coordinates[0];
          return a[0] === b[0] && a[1] === b[1];
        };
        // A touching boundary needs both sides built for the SAME
        // (zoomBucket, laneLodBucket) pair only when it actually carries a
        // lane offset — see the note above `bounds`. Purely static: rows and
        // measures, no projection, so cheap to check on every boundary.
        const boundaryIsLaned = (before, after) =>
          RailStroke.terminalLanes(before.rows, partSpan(before)).end !== 0 ||
          RailStroke.terminalLanes(after.rows, partSpan(after)).start !== 0;
        // Dilate `trigger` across laned touching boundaries: a part pulled
        // in this way is built for the SAME (zoomBucket, laneLodBucket) as
        // the part that pulled it in, so the walk stops the instant it
        // reaches a part already built for that exact pair (bucket-keyed
        // builds are deterministic, so that part's existing geometry already
        // agrees with a fresh one — see atTarget) or an unlaned boundary (no
        // offset to reconcile). In practice this only ever walks the
        // shared-corridor throat around a junction; an ordinary single-track
        // split is unlaned and the walk never leaves the parts already near.
        const atTarget = (part) =>
          part.builtZoom != null &&
          part.builtZoomBucket === zoomBucket &&
          part.builtLaneLodBucket === laneLod.bucket;
        const queue = [];
        for (let i = 0; i < n; i++) if (trigger[i]) queue.push(i);
        while (queue.length) {
          const i = queue.pop();
          if (
            i > 0 && !trigger[i - 1] &&
            touches(parts[i - 1], parts[i]) &&
            boundaryIsLaned(parts[i - 1], parts[i]) &&
            !atTarget(parts[i - 1])
          ) {
            trigger[i - 1] = true;
            queue.push(i - 1);
          }
          if (
            i + 1 < n && !trigger[i + 1] &&
            touches(parts[i], parts[i + 1]) &&
            boundaryIsLaned(parts[i], parts[i + 1]) &&
            !atTarget(parts[i + 1])
          ) {
            trigger[i + 1] = true;
            queue.push(i + 1);
          }
        }
        // Raw part coordinates, projected at this pass's nominal zoom on
        // demand and memoized — needed for a triggered part's own build AND
        // for jointAt's tangent at a KEPT neighbour's shared vertex. Never
        // needed for a kept neighbour's full geometry: jointAt reads only
        // the neighbour's raw coordinates and its static row lanes, never
        // its built/offset stroke — a cached part.strokePx of the neighbour
        // simply is not part of what a joint needs.
        const projectedAt = new Array(n);
        const projectPart = (i) => {
          if (i < 0 || i >= n) return null;
          let px = projectedAt[i];
          if (!px) {
            px = parts[i].coordinates.map((point) => RailStroke.project(point, nominalZoom));
            projectedAt[i] = px;
          }
          return px;
        };
        const unit = (from, to) => {
          const dx = to[0] - from[0];
          const dy = to[1] - from[1];
          const length = Math.hypot(dx, dy);
          return length > 0 ? [dx / length, dy / length] : null;
        };
        // The joint between parts `index - 1` and `index`, or null. Reads
        // only raw projected coordinates and static row lanes, so it is
        // bit-identical whether or not either side is being rebuilt this
        // pass — see the doc on `projectPart` above.
        const jointAt = (index) => {
          const before = parts[index - 1];
          const after = parts[index];
          if (!before || !after || !touches(before, after)) return null;
          const beforePx = projectPart(index - 1);
          const afterPx = projectPart(index);
          if (beforePx.length < 2 || afterPx.length < 2) return null;
          const incoming = unit(beforePx[beforePx.length - 2], beforePx[beforePx.length - 1]);
          const outgoing = unit(afterPx[0], afterPx[1]);
          if (!incoming || !outgoing) return null;
          return {
            incoming,
            outgoing,
            beforeLane: RailStroke.terminalLanes(before.rows, partSpan(before)).end,
            afterLane: RailStroke.terminalLanes(after.rows, partSpan(after)).start,
          };
        };
        for (let i = 0; i < n; i++) {
          if (!trigger[i]) continue;
          const part = parts[i];
          // A slow pinch that keeps re-entering the same eighth-level band
          // (or a pan that revisits a bucket it already built) reuses this
          // exact result instead of re-running buildStroke's offset/fillet
          // passes — see the LRU doc above strokeCacheGet.
          let entry = strokeCacheGet(part, zoomBucket, laneLod.bucket);
          if (!entry) {
            const px = projectPart(i);
            const startJoint = jointAt(i);
            const endJoint = jointAt(i + 1);
            const follows = (part.follows || [])
              .map((follow) => {
                const canon = canonPixels(follow.canonLineId, follow.canonPartIndex);
                return canon
                  ? {
                      from: follow.from,
                      to: follow.to,
                      canonFrom: follow.canonFrom,
                      canonTo: follow.canonTo,
                      points: canon.points,
                      measures: canon.measures,
                    }
                  : null;
              })
              .filter(Boolean);
            const stroke = RailStroke.buildStroke(px, {
              measures: part.measures,
              rows: part.rows,
              totalMetres: part.totalMetres,
              laneGapPx,
              minRampPx: STROKE_MIN_RAMP_PX,
              cornerRadiusPx,
              minCornerRadiusPx,
              anchors: part.anchors,
              follows,
              joinStart: startJoint
                ? {
                    lane: startJoint.beforeLane,
                    incoming: startJoint.incoming,
                    outgoing: startJoint.outgoing,
                  }
                : null,
              joinEnd: endJoint
                ? {
                    lane: endJoint.afterLane,
                    incoming: endJoint.incoming,
                    outgoing: endJoint.outgoing,
                  }
                : null,
            });
            entry = { zoomBucket, laneLodBucket: laneLod.bucket, stroke };
            strokeCachePut(part, entry);
            verticesBuilt += px.length;
          }
          const stroke = entry.stroke;
          part.anchorPoints = stroke.anchors.map((point) =>
            RailStroke.unproject(point, nominalZoom),
          );
          // Kept in pixel space, with the metre measure of every vertex and
          // the NOMINAL zoom it was built for (never the live camera zoom,
          // which may have moved on by the time a kept part's stroke is next
          // read) — so a ridden route's slice (see _applyRideStrokes) and
          // the withheld/family assembly below always unproject a part's
          // stroke at the exact zoom it was projected at, whether that
          // stroke is fresh from this pass or untouched from an earlier one.
          // Always the FULL built stroke, tenant/family windows included: a
          // ride recorded on a tenant window is a real ride on real track,
          // whichever member's stroke draws it, so playback slices from this
          // regardless of what the BASE feature below draws.
          part.strokePx = { points: stroke.points, measures: stroke.measures, zoom: nominalZoom };
          part.builtZoom = nominalZoom;
          part.builtZoomBucket = zoomBucket;
          part.builtLaneLodBucket = laneLod.bucket;
          rebuiltParts.add(part);
        }
        // Base feature: reassembled from EVERY part's CURRENT strokePx —
        // freshly built above for a triggered part, exactly as it already
        // was for a kept one — each unprojected at ITS OWN strokePx.zoom, so
        // a kept part's drawn geometry is untouched down to the coordinate,
        // not merely left alone in intent. The base feature draws only the
        // COMPLEMENT of a part's own tenant windows (this line's stroke
        // withheld here — another family member's landlord window stands
        // for it) and landlord windows (drawn instead by this line's OWN
        // family feature, so the corridor is not drawn twice under two
        // features of the same line) — see familyFeatureIndex below and
        // deriveFamilyWindows in build-display-lanes.mjs. A part with
        // neither is unaffected: one full-length piece, as always.
        // Every part's family/withheld split, computed ONCE per part here
        // via the shared `RailStroke.familyPartition` (rail-stroke.js,
        // answer-identical to RailCore's `ContinuousStroke.familyPartition`
        // to 1e-9 m — see the fixture doc on that function) and reused by
        // the base feature below, the withheld overlay, and the family
        // stroke, so the three can never disagree on where a window's edge
        // actually falls. Clamped to the STROKE's own measure range
        // (`strokePx.measures[0]`/`[last]`), not `[0, part.totalMetres]`: a
        // joint's extension or a follow's own vertices can leave the built
        // stroke short of the part's nominal total, and clamping to the
        // wrong bound would manufacture a sliver of base colour past
        // geometry that does not exist (see the doc on `familyPartition`
        // itself).
        const partitionByPart = new Map();
        const built = parts.map((part) => {
          const strokePx = part.strokePx;
          const z = strokePx.zoom;
          if (!(part.tenantWindows || []).length && !(part.familyWindows || []).length)
            return [strokePx.points.map((point) => RailStroke.unproject(point, z))];
          const measures = strokePx.measures;
          const partition = RailStroke.familyPartition(
            part.totalMetres,
            part.tenantWindows,
            part.familyWindows,
            { measureStart: measures[0], measureEnd: measures[measures.length - 1] },
          );
          partitionByPart.set(part, partition);
          return familySliceRanges(strokePx.points, strokePx.measures, partition.base).map((piece) =>
            piece.map((point) => RailStroke.unproject(point, z)),
          );
        }).flat();
        feature.geometry =
          built.length === 1
            ? { type: "LineString", coordinates: built[0] }
            : { type: "MultiLineString", coordinates: built };
        // Bridged blocked-interval spans (rail-network.js `part.withheld`,
        // metres in this part's own measure space) — sliced from each
        // part's own CURRENT pixel stroke, the same way a ride is sliced
        // from it in _applyRideStrokes, so the dashed overlay can never sit
        // a fraction of a pixel off the field it is meant to trace.
        if (line.withheldFeatureIndex != null) {
          const withheldFeature =
            network.segmentsWithheld.features[line.withheldFeatureIndex];
          if (withheldFeature) {
            const withheldCoords = [];
            for (const part of parts) {
              const strokePx = part.strokePx;
              if (!strokePx || !part.withheld || !part.withheld.length) continue;
              // A withheld span drawn over this line's own tenant window
              // would dash track this line draws NOWHERE (the base feature
              // just excluded that exact stretch, and the landlord's own
              // stroke — not this feature — draws it) — a dash with no
              // solid stroke under it. Clip every span to the complement of
              // this part's OWN tenant windows via the shared
              // `RailStroke.clipRangesToComplement` (mirrors
              // RailMapView.swift's withheld-run build) before slicing. A
              // landlord window stays clipped in: it is still solid track,
              // just drawn by this line's OWN familyFeatureIndex feature
              // rather than the base one below — so each surviving piece is
              // split again at every landlord-window edge strictly inside
              // it, the same way iOS colours each final sub-piece by its
              // own midpoint. On the web both this feature and
              // familyFeatureIndex already share this line's own
              // featureColor/featureColorDark (a render-group colour
              // override applies to the whole line, never to only part of
              // it — see colorOverrideByLine in rail-network.js), so every
              // sub-piece here is already in the family's own colour
              // whenever it falls inside a landlord window; the split
              // still runs so the piece BOUNDARIES match iOS exactly, not
              // merely the colour.
              const visibleRanges = RailStroke.clipRangesToComplement(
                part.withheld.map((span) => ({ from: span[0], to: span[1] })),
                part.tenantWindows || [],
              );
              const familyWindows = part.familyWindows || [];
              for (const range of visibleRanges) {
                const cuts = new Set([range.from, range.to]);
                for (const window of familyWindows) {
                  const lo = Math.min(window.from, window.to);
                  const hi = Math.max(window.from, window.to);
                  if (lo > range.from && lo < range.to) cuts.add(lo);
                  if (hi > range.from && hi < range.to) cuts.add(hi);
                }
                const points = [...cuts].sort((a, b) => a - b);
                for (let index = 0; index < points.length - 1; index += 1) {
                  const from = points[index];
                  const to = points[index + 1];
                  if (to - from <= RailStroke.FAMILY_PARTITION_EPSILON_METRES) continue;
                  const sliced = RailStroke.sliceStroke(
                    strokePx.points,
                    strokePx.measures,
                    from,
                    to,
                  );
                  if (sliced.length >= 2)
                    withheldCoords.push(
                      sliced.map((point) => RailStroke.unproject(point, strokePx.zoom)),
                    );
                }
              }
            }
            withheldFeature.geometry = {
              type: "MultiLineString",
              coordinates: withheldCoords,
            };
            withheldChanged = true;
          }
        }
        // Family stroke (rail-network.js `line.familyFeatureIndex`, set
        // when any part has a landlord window — see deriveFamilyWindows in
        // build-display-lanes.mjs): the shared corridor stroke for a
        // same-family follow, sliced from each part's own CURRENT pixel
        // stroke — the SAME `familyPartition` result the base feature above
        // already computed for this part (`partitionByPart`), so the two
        // can never sit a fraction of a pixel off each other. Its colour is
        // already this line's own featureColor/featureColorDark (a
        // render-group colour override applies to every family member), so
        // this draws the ONE stroke the corridor needs, in the family's
        // colour, once — not once per member.
        if (line.familyFeatureIndex != null) {
          const familyFeature = lineFeatures[line.familyFeatureIndex];
          if (familyFeature) {
            const familyCoords = [];
            for (const part of parts) {
              const strokePx = part.strokePx;
              const partition = partitionByPart.get(part);
              if (!strokePx || !partition || !partition.family.length) continue;
              for (const piece of familySliceRanges(strokePx.points, strokePx.measures, partition.family))
                familyCoords.push(piece.map((point) => RailStroke.unproject(point, strokePx.zoom)));
            }
            familyFeature.geometry = {
              type: "MultiLineString",
              coordinates: familyCoords,
            };
          }
        }
        linesTouched += 1;
      }
      if (!linesTouched) return false;
      // Station anchors: only a part this pass actually rebuilt (fresh
      // build or LRU reuse of a DIFFERENT bucket than it already had) can
      // have moved — a kept part's anchorPoints is the same array it
      // already had — so only those parts' station slots are worth
      // comparing. Exact equality against the feature's current
      // coordinates: a pinch that lands back on an already-drawn bucket
      // (LRU hit, same value as what's already uploaded) costs a compare,
      // not a re-upload.
      if (rebuiltParts.size) {
        const stationFeatures = network.stations.features;
        for (const slot of model.stations) {
          const part = model.lines[slot.lineIndex]?.parts[slot.partIndex];
          if (!part || !rebuiltParts.has(part)) continue;
          const point = part.anchorPoints?.[slot.anchorSlot];
          const feature = stationFeatures[slot.featureIndex];
          if (!point || !feature) continue;
          const prev = feature.geometry && feature.geometry.coordinates;
          if (!prev || prev[0] !== point[0] || prev[1] !== point[1]) {
            feature.geometry = { type: "Point", coordinates: [point[0], point[1]] };
            anchorsChanged = true;
          }
        }
      }
      this._strokeZoom = zoom;
      const elapsed =
        typeof performance !== "undefined" && performance.now
          ? performance.now() - startedAt
          : 0;
      this._strokeStats = {
        lastRebuildMs: elapsed,
        partsRebuilt: rebuiltParts.size,
        partsKept: partsTotal - rebuiltParts.size,
        verticesBuilt,
      };
      if (typeof window !== "undefined" && window.PERF_DEBUG) {
        console.log(
          `[railmap] stroke rebuild: ${elapsed.toFixed(1)}ms, ` +
            `${rebuiltParts.size}/${partsTotal} parts rebuilt, ` +
            `${verticesBuilt} vertices built, anchorsChanged=${anchorsChanged}`,
        );
      }
      return { anchorsChanged, withheldChanged };
    },
    // A ridden route sliced from a continuous-stroke part (rail-network.js
    // `strokeRefFor`/`canonicalizeRouteFeature`, carried onto the record by
    // app-deck-records.js as `record.strokeRef`) is redrawn HERE, straight
    // from that part's own just-built pixel stroke (`part.strokePx`,
    // written by _applyContinuousStrokes above), instead of drifting a
    // fraction of a pixel from an independent fit. Called right after the
    // network rebuild and before the route/pick sources are re-uploaded, so
    // a ride can never lag the network stroke by a frame.
    //
    // A record's very first substitution keeps its prior path as
    // `record.canonicalPath` — the route-solver-fitted geometry
    // canonicalizeRouteFeature produced — so it stays recoverable. A record
    // whose slice comes back empty (the part isn't built yet, or the ref
    // measures collapsed) is left exactly as it was; the next rebuild tries
    // again once the part it names has geometry.
    _applyRideStrokes() {
      const network = this._network;
      const model = network && network.strokeModel;
      if (!model || typeof RailStroke === "undefined") return false;
      const partsByLine = new Map(model.lines.map((line) => [line.lineId, line.parts]));
      let changed = false;
      const applyTo = (records) => {
        if (!records) return;
        for (const record of records) {
          const ref = record.strokeRef;
          if (!ref) continue;
          const part = partsByLine.get(ref.lineId)?.[ref.partIndex];
          const strokePx = part && part.strokePx;
          if (!strokePx) continue;
          const sliced = RailStroke.sliceStroke(
            strokePx.points,
            strokePx.measures,
            ref.from,
            ref.to,
          );
          if (!sliced.length) continue;
          if (!record.canonicalPath) record.canonicalPath = record.path;
          record.path = sliced.map((point) => RailStroke.unproject(point, strokePx.zoom));
          changed = true;
        }
      };
      applyTo(this._records);
      applyTo(this._expandRecords);
      if (changed) {
        this._rideStrokeGeneration += 1;
        // gi.curve / gi._line for an `_allStrokeRef` corridor (app-deck-
        // records.js resolveCorridorComponent / fitCorridorRunsIndependently)
        // were built from the PRE-substitution path — refresh them from the
        // record paths just resliced above, or the hover-fan direction and
        // fit-curve diagnostics keep reading stale, off-network geometry.
        // refreshExactStrokeCorridorCurves is a bare global published by
        // app-overlap-lanes.js (the app-*.js family shares one lexical
        // scope, unlike this RailMap namespace) — guarded the same way
        // RailStroke is above, since a standalone embed of this file has
        // no app layer at all.
        if (typeof refreshExactStrokeCorridorCurves === "function")
          refreshExactStrokeCorridorCurves(this._groupInfo);
      }
      return changed;
    },
    // Undoes _applyRideStrokes' substitution: any record still holding a
    // `canonicalPath` (its pre-substitution, solver-fitted path) gets it
    // back as `record.path`, and the marker is cleared. Called when the
    // strokeModel a record's slice depended on is gone (switchNetworkCountry
    // nulls `this._network`) — the OLD country's pixel stroke must not keep
    // being shown once it no longer corresponds to any live network.
    _restoreCanonicalPaths(records) {
      if (!records) return false;
      let restored = false;
      for (const record of records) {
        if (!record.canonicalPath) continue;
        record.path = record.canonicalPath;
        record.canonicalPath = null;
        restored = true;
      }
      return restored;
    },
    // A ridden route substituted onto the continuous-stroke network above
    // draws exact ink app-playback.js's compilePath cannot see on its own —
    // it samples the solver-fitted CANONICAL route geometry, which on a
    // laned/rounded stretch sits a few pixels off what is actually drawn.
    //
    // Returns, for one train, each ridden route feature's CURRENT drawn path
    // (`record.path`, straight from _applyRideStrokes above), keyed by the
    // feature's own segment_index and given in feature-segment order, so
    // compilePath can zip them against getMatchedRouteFeatures(train). Only
    // strokeRef-backed records are returned: those alone are guaranteed to
    // sit on the drawn network centreline (rail-network.js strokeRefFor /
    // canonicalizeRouteFeature) — a record with no strokeRef draws the
    // corridor/Douglas-Peucker DISPLAY geometry, which is NOT a faithful
    // stand-in for the raw route feature compilePath otherwise samples, and
    // substituting it would change a non-NA train's playback path (which
    // must stay byte-identical to before this accessor existed).
    //
    // One (train, feature) pair can own more than one record — a corridor/
    // lane change cuts a "run" wherever the shared track changes lane, even
    // mid-feature — so every matching record's path is concatenated here in
    // array order, which is along-the-line order (appendDeckRouteLineRecords
    // in app-deck-records.js pushes a line's runs in ascending position).
    // Adjoining runs share an exact boundary vertex, deduped like
    // compilePath's own run-stitcher.
    drawnRidePaths(trainId) {
      const records = this._records;
      if (!records || trainId == null) return null;
      const bySeg = new Map();
      for (let i = 0; i < records.length; i += 1) {
        const record = records[i];
        if (!record.strokeRef) continue;
        const train = record.train;
        if (!train || train.id !== trainId) continue;
        const feature = record.feature;
        const segIndex =
          feature && feature.properties
            ? Number(feature.properties.segment_index ?? -1)
            : -1;
        if (segIndex < 0) continue;
        const path = record.path;
        if (!Array.isArray(path) || path.length < 2) continue;
        let entry = bySeg.get(segIndex);
        if (!entry) {
          entry = { segmentIndex: segIndex, coords: [] };
          bySeg.set(segIndex, entry);
        }
        for (let k = 0; k < path.length; k += 1) {
          const c = path[k];
          const last = entry.coords[entry.coords.length - 1];
          if (last && distanceMeters(last, c) <= 0) continue;
          entry.coords.push(c);
        }
      }
      if (!bySeg.size) return null;
      const out = Array.from(bySeg.values()).filter(
        (entry) => entry.coords.length >= 2,
      );
      if (!out.length) return null;
      out.sort((a, b) => a.segmentIndex - b.segmentIndex);
      return out;
    },
    _scheduleStrokeRebuild(now) {
      const network = this._network;
      if (!network || !network.strokeModel || !this._map) return;
      // Gate on whether there is anything to rebuild FOR — the visible
      // network layers, or a ride that must stay glued to the network's
      // pixel stroke — not on the network layer's own visibility. A ride is
      // drawn on the TRAINS/expand sources, independent of whether "全部鐵路
      // 線"/station dots are toggled on, so hiding the network must not also
      // stop rides from tracking it across a zoom.
      const networkVisible =
        this._networkVisibleWanted || this._networkStationsVisibleWanted;
      if (!networkVisible && !this._hasStrokeRefRecords) return;
      const run = () => {
        this._strokeRebuildTimer = null;
        // _applyContinuousStrokes only rebuilds near-camera/stale-zoom parts
        // (its own perf guard) and, unlike this method, does not look at
        // layer visibility at all — reaching it now even while the network
        // layer is hidden keeps every part a ride might reference at a
        // current part.strokePx. Nothing rebuilt means part.strokePx is
        // unchanged, so a ride's slice would come out byte-identical —
        // skip the re-slice and re-upload rather than pay for a no-op.
        const strokeResult = this._applyContinuousStrokes(false);
        if (!strokeResult) return;
        this._applyRideStrokes();
        const seg = this._src(SEGMENTS_SOURCE);
        if (seg) seg.setData(network.segments);
        // The withheld source is its own upload, skipped independently: most
        // rebuild passes touch only lines with no `displayBlockedIntervals`
        // at all, and re-uploading `network.segmentsWithheld` on every one of
        // those passes moved nothing — see `withheldChanged`'s own doc above.
        if (strokeResult.withheldChanged) {
          const withheld = this._src(SEGMENTS_WITHHELD_SOURCE);
          if (withheld) withheld.setData(network.segmentsWithheld || EMPTY_FC);
        }
        // Stations/labels are a SEPARATE source pair from segments, so their
        // re-upload can be skipped independently: a rebuild that only moved
        // parts with no station anchor on them (or whose anchors landed back
        // on their exact prior coordinates) leaves `network.stations` byte-
        // for-byte the same FeatureCollection object it already was.
        if (strokeResult.anchorsChanged) {
          const sta = this._src(STATIONS_SOURCE);
          const labels = this._src(STATION_LABELS_SOURCE);
          if (sta) sta.setData(network.stations);
          if (labels) labels.setData(network.stationLabels || EMPTY_FC);
        }
        this._pushRoutes();
        this._pushPickFan();
      };
      if (now) {
        if (this._strokeRebuildTimer) clearTimeout(this._strokeRebuildTimer);
        run();
        return;
      }
      if (this._strokeRebuildTimer) return;
      this._strokeRebuildTimer = setTimeout(run, STROKE_REBUILD_DELAY_MS);
    },
    setNetworkStationsVisible(v) {
      this._networkStationsVisibleWanted = Boolean(v);
      const visibility = this._networkStationsVisibleWanted ? "visible" : "none";
      // The station names ride with the station dots. A name without its
      // bead would be a place, not a station.
      for (const layer of [STATIONS_LAYER, STATION_LANES_LAYER, STATIONS_LABEL_LAYER])
        this._setVisibility(layer, visibility);
      // …and when they go, the rides' own names take over naming the map.
      this._applyRiddenLabelVisibility();
      if (this._networkStationsVisibleWanted) this._scheduleStrokeRebuild(true);
    },
    // Fetch + build + upload the active country's network package when it was
    // not supplied at attach time, or retry after a failed boot/country load.
    // Deduped so concurrent recovery/toggle requests parse once.
    ensureNetwork(packageUrl) {
      if (this._network) return Promise.resolve(this._network);
      if (this._networkPromise) return this._networkPromise;
      const m = this._map;
      const generation = this._networkGeneration;
      const request = loadNetwork(packageUrl)
        .then((network) => {
          if (generation !== this._networkGeneration) return null;
          if (!network) {
            if (this._networkPromise === request) this._networkPromise = null;
            return null;
          }
          this._network = network;
          if (m) {
            // Upload into the pre-created (still-hidden) EMPTY_FC sources.
            // Returns false if the style isn't ready yet (getSource undefined) —
            // e.g. the overlay is toggled during the initial map load — in which
            // case we apply once the style finishes ('load'), so the data is
            // never silently dropped.
            const applyNetwork = () => {
              if (generation !== this._networkGeneration) return false;
              const seg = m.getSource(SEGMENTS_SOURCE);
              const withheld = m.getSource(SEGMENTS_WITHHELD_SOURCE);
              const sta = m.getSource(STATIONS_SOURCE);
              const lanes = m.getSource(STATION_LANES_SOURCE);
              const labels = m.getSource(STATION_LABELS_SOURCE);
              // A throw here must not leave the sources empty for good: the
              // canonical geometry is still a drawable fallback.
              try {
                this._applyContinuousStrokes(true);
                // The network's own stroke geometry just landed for the
                // first time (or was rebuilt from scratch here) — any
                // already-ridden record carrying a strokeRef (set before the
                // network finished loading, e.g. a country switch mid-ride)
                // must be resliced onto it now, not wait for the next
                // zoom/pan-triggered rebuild. Without this a ride stays on
                // its solver-fitted canonical path — visibly off the drawn
                // network — until the map is next zoomed or panned.
                this._applyRideStrokes();
              } catch (error) {
                console.warn("[railmap] continuous strokes failed:", error);
              }
              if (seg) seg.setData(network.segments);
              if (withheld) withheld.setData(network.segmentsWithheld || EMPTY_FC);
              if (sta) sta.setData(network.stations);
              if (lanes) lanes.setData(network.stationLanes || EMPTY_FC);
              if (labels) labels.setData(network.stationLabels || EMPTY_FC);
              this._ensureStationIcons();
              this._pushRoutes();
              this._pushPickFan();
              // Re-assert the recorded visibility intent: a toggle made while
              // the style was still loading hit _setVisibility before the
              // layers existed and was silently dropped, leaving a checked
              // 全部鐵路線 box with invisible layers.
              this.setNetworkVisible(this._networkVisibleWanted);
              this.setNetworkStationsVisible(this._networkStationsVisibleWanted);
              return Boolean(seg && sta);
            };
            if (!applyNetwork() && typeof m.once === "function") {
              // Retry on style progress, not on "load": the load event waits
              // for every initial tile and may have already fired — or may
              // stall for a long time in a throttled tab — while the style
              // (and thus the pre-created sources) is ready much earlier.
              const retry = () => {
                if (generation !== this._networkGeneration) return;
                if (!applyNetwork()) m.once("styledata", retry);
              };
              m.once("styledata", retry);
            }
          }
          return network;
        })
        .catch((e) => {
          if (this._networkPromise === request) this._networkPromise = null;
          console.warn("[railmap] network load failed:", e);
          return null;
        });
      this._networkPromise = request;
      return request;
    },
    // Drop the previous country's in-memory network and reload only if the
    // user had already opted into the national-network overlay (or another
    // feature, such as station hover, had already loaded the network).
    // `country` re-credits the segment source: the style is built once at boot
    // with the country that was active then, and switching swaps the geometry
    // underneath it, so the licence declaration has to move with the data.
    // Re-point one geojson source's simplification tolerance for `country`.
    //
    // MapLibre reads `tolerance` once, in the GeoJSONSource constructor, and
    // keeps it in the worker options it re-sends on every setData — there is
    // no public setter, and rebuilding the source would mean tearing down and
    // reinstalling every layer that draws from it. Writing the already-derived
    // tile-unit value is the same in-place mutation `seg.attribution` above
    // is, and it is read by the very next setData. Guarded on every field it
    // touches so a MapLibre that has moved them simply keeps the boot value.
    _setSourceTolerance(source, country) {
      if (!source || typeof source._pixelsToTileUnits !== "function") return;
      const options = source.workerOptions && source.workerOptions.geojsonVtOptions;
      if (!options) return;
      options.tolerance = source._pixelsToTileUnits(strokeSourceTolerancePx(country));
    },
    switchNetworkCountry(country, packageUrl) {
      const shouldReload = Boolean(
        this._networkVisibleWanted ||
          this._networkStationsVisibleWanted ||
          this._network ||
          this._networkPromise,
      );
      this._networkGeneration += 1;
      this._network = null;
      this._networkPromise = null;
      // The old country's strokeModel is gone, so any record still sliced
      // onto it (record.canonicalPath set by _applyRideStrokes) can no
      // longer be kept in sync — undo the substitution and go back to the
      // solver-fitted canonical path until the new country's network (and,
      // if this record's line still exists there, a fresh strokeRef) loads.
      // Without this a ride would keep showing the OLD country's stroke
      // geometry — coordinates that have nothing to do with the network
      // about to replace it — until app.js happens to rebuild this record.
      // Both calls must run — no `||` short-circuit — so an expand-only
      // restoration is never skipped just because _records had none.
      const restoredRecords = this._restoreCanonicalPaths(this._records);
      const restoredExpand = this._restoreCanonicalPaths(this._expandRecords);
      if (restoredRecords || restoredExpand) {
        this._rideStrokeGeneration += 1;
        this._pushRoutes();
        this._pushPickFan();
      }
      this._strokeZoom = null;
      this._stationPopupKey = null;
      if (this._stationPopup) this._stationPopup.remove();
      const seg = this._src(SEGMENTS_SOURCE);
      const withheld = this._src(SEGMENTS_WITHHELD_SOURCE);
      const sta = this._src(STATIONS_SOURCE);
      const staLanes = this._src(STATION_LANES_SOURCE);
      const staLabels = this._src(STATION_LABELS_SOURCE);
      // How much geojson-vt may generalise the stroke sources is a per-COUNTRY
      // answer (railmap-style.js `strokeSourceTolerancePx`: a continuous-stroke
      // region spends its epsilon inside rail-stroke.js, BEFORE its corners are
      // rounded, and a second pass here would strip every fillet back to a
      // chord), and the style is built once, at boot, for the country the map
      // booted into. A switch across that boundary — jp/us/ca ⇄ tw/hk/mo/kr —
      // therefore has to re-point it, exactly as it re-credits the attribution
      // below. The sources are emptied here and refilled by ensureNetwork, so
      // the new tolerance is in place before any geometry is uploaded under
      // it. The list is every source that carries stroke geometry or a slice
      // of it — the network, its withheld dashes, the ridden lines, their two
      // touch targets, the tap fan and the playback trail — which is the same
      // list railmap-style.js gives `strokeTolerance` to at build.
      [
        seg,
        withheld,
        this._src(TRAIN_ROUTES_SOURCE),
        this._src(TRAIN_PICK_SOURCE),
        this._src(TRAIN_PICK_FAN_SOURCE),
        this._src(TRAIN_EXPAND_SOURCE),
        this._src(PLAYBACK_SOURCE),
      ].forEach((source) => this._setSourceTolerance(source, country));
      if (seg) {
        seg.setData(EMPTY_FC);
        if (country) seg.attribution = railAttributionForCountry(country);
      }
      if (withheld) withheld.setData(EMPTY_FC);
      if (sta) sta.setData(EMPTY_FC);
      if (staLanes) staLanes.setData(EMPTY_FC);
      if (staLabels) staLabels.setData(EMPTY_FC);
      if (!shouldReload) return Promise.resolve(null);
      return this.ensureNetwork(packageUrl).then((network) => {
        // Country switching does not recreate the layer control. Re-apply its
        // current intent after the new sources are populated so a checked
        // "All Railway Lines" box can never leave an invisible Taiwan layer.
        this.setNetworkVisible(this._networkVisibleWanted);
        this.setNetworkStationsVisible(this._networkStationsVisibleWanted);
        return network;
      });
    },
    // Basemap mode: 'positron' (online vector) | 'none'.
    setBasemapMode(mode) {
      this._basemapMode = mode === "positron" ? "positron" : "none";
      const posVis = mode === "positron" ? "visible" : "none";
      this._basemapLayerIds.forEach((id) => this._setVisibility(id, posVis));
    },
    // Whether the vector (online) basemap is present in the live style.
    hasBasemap() {
      return this._basemapLayerIds.length > 0;
    },
    // Theme switch = recolor the ONE installed basemap stack in place. Both
    // themes are the same positron layers (railmap-basemap.js), so writing the
    // target theme's color paint values — with the transitions pre-installed
    // at style build — crossfades every surface AND label smoothly. This
    // replaced the old dual staged-stack crossfade: two identical symbol
    // stacks fight in MapLibre's global label collision pass, and the staged
    // invisible copy won placement, blanking the visible theme's labels.
    _recolorBasemapStack(basemap, duration) {
      const m = this._map;
      const stack = this._basemapStack;
      if (!m || !stack || !basemap || !Array.isArray(basemap.layers))
        return false;
      const layerIds = stack.layerIds || [];
      if (layerIds.length !== basemap.layers.length) return false;
      const transition = {
        duration: Math.max(0, Number(duration) || 0),
        delay: 0,
      };
      const updateTransition =
        transition.duration !== this._basemapTransitionDuration;
      basemap.layers.forEach((layer, index) => {
        const id = layerIds[index];
        if (!m.getLayer(id)) return;
        Object.keys(layer.paint || {}).forEach((prop) => {
          if (!/-color$/.test(prop)) return;
          if (updateTransition)
            m.setPaintProperty(id, prop + "-transition", transition);
          m.setPaintProperty(id, prop, layer.paint[prop]);
        });
        // The city-dot sprite swaps between its black/light variants per
        // theme (layout, so it snaps — the dot is tiny and position-stable).
        const icon = layer.layout ? layer.layout["icon-image"] : undefined;
        if (icon !== undefined) {
          const current = m.getLayoutProperty(id, "icon-image");
          if (JSON.stringify(current) !== JSON.stringify(icon))
            m.setLayoutProperty(id, "icon-image", icon);
        }
      });
      this._basemapTransitionDuration = transition.duration;
      return true;
    },
    _applyThemePaint(theme, duration) {
      const m = this._map;
      if (!m) return;
      const colors = MAP_SURFACE_COLORS[theme === "dark" ? "dark" : "light"];
      const transition = {
        duration: Math.max(0, Number(duration) || 0),
        delay: 0,
      };
      if (m.getLayer("rp-bg")) {
        m.setPaintProperty(
          "rp-bg",
          "background-color-transition",
          transition,
        );
        m.setPaintProperty("rp-bg", "background-color", colors.background);
      }
      if (m.getLayer(FADE_LAYER)) {
        m.setPaintProperty(
          FADE_LAYER,
          "background-color-transition",
          transition,
        );
        m.setPaintProperty(FADE_LAYER, "background-color", colors.fade);
      }
      if (m.getLayer(TRAIN_SEL_CASING_LAYER))
        m.setPaintProperty(TRAIN_SEL_CASING_LAYER, "line-color", colors.casing);
      if (m.getLayer(SEGMENTS_CASING_LAYER)) {
        m.setPaintProperty(
          SEGMENTS_CASING_LAYER,
          "line-color-transition",
          transition,
        );
        m.setPaintProperty(
          SEGMENTS_CASING_LAYER,
          "line-color",
          networkCasingColor(theme),
        );
      }
      // The network carries a pre-audited variant for each map surface, so a
      // surface change selects the matching package colour (see
      // networkLineColor).
      if (m.getLayer(SEGMENTS_LAYER)) {
        m.setPaintProperty(SEGMENTS_LAYER, "line-color-transition", transition);
        m.setPaintProperty(SEGMENTS_LAYER, "line-color", networkLineColor(theme));
      }
      // The suspended stretches are the same field in the same two inks, so
      // they follow the same two colour rules. Both layers, or a theme switch
      // would leave every closed railway painted for the surface it left.
      if (m.getLayer(SEGMENTS_SUSPENDED_CASING_LAYER)) {
        m.setPaintProperty(
          SEGMENTS_SUSPENDED_CASING_LAYER,
          "line-color-transition",
          transition,
        );
        m.setPaintProperty(
          SEGMENTS_SUSPENDED_CASING_LAYER,
          "line-color",
          networkCasingColor(theme),
        );
      }
      if (m.getLayer(SEGMENTS_SUSPENDED_LAYER)) {
        m.setPaintProperty(
          SEGMENTS_SUSPENDED_LAYER,
          "line-color-transition",
          transition,
        );
        m.setPaintProperty(
          SEGMENTS_SUSPENDED_LAYER,
          "line-color",
          networkLineColor(theme),
        );
      }
      // A bridged blocked interval (see SEGMENTS_WITHHELD_LAYER in
      // railmap-style.js) is the same field in the line's own colour, and its
      // dashed casing is the surface colour itself — both follow the theme.
      if (m.getLayer(SEGMENTS_WITHHELD_LAYER)) {
        m.setPaintProperty(
          SEGMENTS_WITHHELD_LAYER,
          "line-color-transition",
          transition,
        );
        m.setPaintProperty(
          SEGMENTS_WITHHELD_LAYER,
          "line-color",
          networkLineColor(theme),
        );
      }
      if (m.getLayer(SEGMENTS_WITHHELD_CASING_LAYER)) {
        m.setPaintProperty(
          SEGMENTS_WITHHELD_CASING_LAYER,
          "line-color-transition",
          transition,
        );
        m.setPaintProperty(
          SEGMENTS_WITHHELD_CASING_LAYER,
          "line-color",
          colors.background,
        );
      }
      if (m.getLayer(STATIONS_LAYER)) {
        m.setPaintProperty(
          STATIONS_LAYER,
          "circle-color-transition",
          transition,
        );
        // Expressions, not flat colours: solid where one railway calls, open
        // where two meet, and that has to survive a theme switch.
        m.setPaintProperty(STATIONS_LAYER, "circle-color", stationFill(theme));
        m.setPaintProperty(
          STATIONS_LAYER,
          "circle-stroke-color-transition",
          transition,
        );
        m.setPaintProperty(
          STATIONS_LAYER,
          "circle-stroke-color",
          stationStroke(theme),
        );
      }
      this._ensureStationIcons();
      if (m.getLayer(STATION_LANES_LAYER))
        m.setLayoutProperty(
          STATION_LANES_LAYER,
          "icon-image",
          stationIconImage(theme),
        );
      // Names: ink and halo are both surface-derived, so both flip with the
      // theme. The line name keeps its hue and only re-anchors the contrast
      // half of its blend (networkLineLabelColor).
      if (m.getLayer(SEGMENTS_LABEL_LAYER)) {
        m.setPaintProperty(SEGMENTS_LABEL_LAYER, "text-color-transition", transition);
        m.setPaintProperty(
          SEGMENTS_LABEL_LAYER,
          "text-color",
          networkLineLabelColor(theme),
        );
        m.setPaintProperty(
          SEGMENTS_LABEL_LAYER,
          "text-halo-color-transition",
          transition,
        );
        m.setPaintProperty(
          SEGMENTS_LABEL_LAYER,
          "text-halo-color",
          networkLabelHaloColor(theme),
        );
      }
      if (m.getLayer(STATIONS_LABEL_LAYER)) {
        m.setPaintProperty(STATIONS_LABEL_LAYER, "text-color-transition", transition);
        m.setPaintProperty(
          STATIONS_LABEL_LAYER,
          "text-color",
          networkLabelTextColor(theme),
        );
        m.setPaintProperty(
          STATIONS_LABEL_LAYER,
          "text-halo-color-transition",
          transition,
        );
        m.setPaintProperty(
          STATIONS_LABEL_LAYER,
          "text-halo-color",
          networkLabelHaloColor(theme),
        );
      }
      // The rides' own station names are the same ink on the same surface —
      // they name the map whenever the network's labels are switched off, so
      // they have to flip with it too.
      for (const id of [
        TRAIN_TERMINAL_LABEL_LAYER,
        TRAIN_STOP_LABEL_LAYER,
        TRAIN_PASS_LABEL_LAYER,
      ]) {
        if (!m.getLayer(id)) continue;
        m.setPaintProperty(id, "text-color-transition", transition);
        m.setPaintProperty(id, "text-color", networkLabelTextColor(theme));
        m.setPaintProperty(id, "text-halo-color-transition", transition);
        m.setPaintProperty(id, "text-halo-color", networkLabelHaloColor(theme));
      }
      // Playback layers are long-lived style layers. Repaint them in place so
      // a theme switch during an active run keeps its casing, beads and labels
      // on the same surface palette without rebuilding playback sources.
      this._restampPlaybackTheme();
    },
    _applyEffectiveFade(duration) {
      const m = this._map;
      if (!m || !m.getLayer(FADE_LAYER)) return;
      const transition = {
        duration: Math.max(0, Number(duration) || 0),
        delay: 0,
      };
      m.setPaintProperty(
        FADE_LAYER,
        "background-opacity-transition",
        transition,
      );
      m.setPaintProperty(
        FADE_LAYER,
        "background-opacity",
        this._fadeOpacity,
      );
    },
    _waitForBasemapSources(sourceIds, timeoutMs) {
      const m = this._map;
      if (!m || !sourceIds.length || typeof m.isSourceLoaded !== "function")
        return Promise.resolve();
      return new Promise((resolve) => {
        let done = false;
        let timer = null;
        const finish = () => {
          if (done) return;
          done = true;
          if (timer !== null) clearTimeout(timer);
          if (typeof m.off === "function") m.off("sourcedata", check);
          resolve();
        };
        const check = () => {
          if (sourceIds.every((id) => m.getSource(id) && m.isSourceLoaded(id)))
            finish();
        };
        timer = setTimeout(finish, Math.max(0, Number(timeoutMs) || 1200));
        if (typeof m.on === "function") m.on("sourcedata", check);
        check();
        if (typeof m.triggerRepaint === "function") m.triggerRepaint();
      });
    },
    async _installBasemap(basemap, options = {}) {
      const m = this._map;
      if (!m || !basemap) return false;
      const visible = this._basemapMode === "positron";
      const oldLayerIds = this._basemapLayerIds.slice();
      const oldSourceIds = this._basemapSourceIds.slice();
      const animate =
        options.animate !== false &&
        visible &&
        oldLayerIds.some((id) => m.getLayer(id));
      const namespace =
        "rp-bm-" +
        ++this._basemapGeneration +
        "-" +
        (basemap.theme === "dark" ? "dark-" : "light-");
      const staged = namespaceBasemap(basemap, namespace, animate);
      const addedLayerIds = [];
      const addedSourceIds = [];
      try {
        // Stage the new basemap below the fade/railway stack while the old
        // basemap remains live. Once its tiles settle, cross-fade both stacks
        // directly instead of passing through a solid white/black cover.
        for (const id of Object.keys(staged.sources)) {
          if (!m.getSource(id)) {
            m.addSource(id, staged.sources[id]);
            addedSourceIds.push(id);
          }
        }
        if (basemap.glyphs && typeof m.setGlyphs === "function")
          m.setGlyphs(basemap.glyphs);
        if (basemap.sprite && typeof m.setSprite === "function")
          m.setSprite(basemap.sprite);

        const bmLayers = staged.layers;
        const addLayer = (sourceLayer, beforeId) => {
          const layer = Object.assign({}, sourceLayer);
          if (!visible) {
            layer.layout = Object.assign({}, layer.layout, { visibility: "none" });
          }
          m.addLayer(layer, beforeId);
          addedLayerIds.push(layer.id);
        };
        bmLayers.forEach((layer) => addLayer(layer, FADE_LAYER));

        if (animate) {
          await this._waitForBasemapSources(
            Object.keys(staged.sources),
            2200,
          );
          const transition = {
            duration: BASEMAP_CROSSFADE_MS,
            delay: 0,
          };
          oldLayerIds.forEach((id) => {
            const layer = m.getLayer(id);
            if (!layer) return;
            opacityPropsForLayer(layer).forEach((prop) => {
              m.setPaintProperty(id, prop + "-transition", transition);
              m.setPaintProperty(id, prop, 0);
            });
          });
          staged.opacityTargets.forEach((targets, id) => {
            if (!m.getLayer(id)) return;
            Object.keys(targets).forEach((prop) => {
              m.setPaintProperty(id, prop + "-transition", transition);
              m.setPaintProperty(id, prop, targets[prop]);
            });
          });
          await new Promise((resolve) =>
            setTimeout(resolve, BASEMAP_CROSSFADE_MS + 40),
          );
        }

        oldLayerIds
          .slice()
          .reverse()
          .forEach((id) => {
            if (m.getLayer(id)) m.removeLayer(id);
          });
        oldSourceIds.forEach((id) => {
          if (m.getSource(id)) m.removeSource(id);
        });

        this._basemapLayerIds = bmLayers.map((l) => l.id);
        this._basemapSourceIds = Object.keys(staged.sources);
        this._basemapInstalledTheme = basemap.theme || this._theme;
        this._basemapStack = {
          layerIds: this._basemapLayerIds.slice(),
          sourceIds: this._basemapSourceIds.slice(),
        };
        // The staged install wrote fresh transitions; future theme recolors
        // rely on the build-time BASEMAP_CROSSFADE_MS transitions.
        this._basemapTransitionDuration = BASEMAP_CROSSFADE_MS;
        return true;
      } catch (e) {
        console.warn("[map] failed to install basemap theme", e);
        addedLayerIds
          .slice()
          .reverse()
          .forEach((id) => {
            if (m.getLayer(id)) m.removeLayer(id);
          });
        addedSourceIds.forEach((id) => {
          if (m.getSource(id)) m.removeSource(id);
        });
        return false;
      }
    },
    // Switches only the basemap palette, preserving all railway overlays and
    // the current view. Dark mode uses the recolored positron style
    // (railmap-basemap.js), keeping labels identical to light mode.
    async setBasemapTheme(theme, options = {}) {
      theme = theme === "dark" ? "dark" : "light";
      this._theme = theme;
      const animate = options.animate !== false;
      const duration = animate ? BASEMAP_CROSSFADE_MS : 0;
      this._applyThemePaint(theme, duration);
      if (!this._map) return false;
      if (this._basemapRetryInflight) await this._basemapRetryInflight;
      if (this._theme !== theme) return false; // superseded by a newer switch
      if (this._basemapInstalledTheme === theme && this._basemapStack)
        return true;
      if (this._basemapStack) {
        // The themed style is cache-warm after boot, so this resolves in a
        // microtask and the recolor starts within the same frame as the click.
        const basemap = await loadBasemap(theme);
        if (this._theme !== theme) return false;
        if (basemap && this._recolorBasemapStack(basemap, duration)) {
          this._basemapInstalledTheme = theme;
          return true;
        }
        // Recolor impossible (layer-count mismatch) — reinstall wholesale.
      }
      this._basemapRetryInflight = (async () => {
        try {
          const basemap = await loadBasemap(theme, true);
          if (!basemap) return false;
          if (!(await probeBasemapOrigin(basemap))) return false;
          return await this._installBasemap(basemap, { animate });
        } finally {
          this._basemapRetryInflight = null;
        }
      })();
      return this._basemapRetryInflight;
    },
    // Online retry: boot may have degraded to no-basemap. Load the style for
    // the active page theme and splice it into the live map without touching
    // railway overlays or camera state.
    async retryBasemap() {
      const m = this._map;
      if (!m) return false;
      if (this._basemapStack) {
        // Present but possibly painted for another theme (installed while a
        // switch raced) — converge via the cheap in-place recolor.
        if (this._basemapInstalledTheme !== this._theme)
          return this.setBasemapTheme(this._theme, { animate: false });
        return true;
      }
      if (this._basemapRetryInflight) return this._basemapRetryInflight;
      this._basemapRetryInflight = (async () => {
        try {
          const basemap = await loadBasemap(this._theme, true);
          if (!basemap) return false;
          if (!(await probeBasemapOrigin(basemap))) return false;
          return await this._installBasemap(basemap);
        } catch {
          return false;
        } finally {
          this._basemapRetryInflight = null;
        }
      })();
      return this._basemapRetryInflight;
    },
    setFadeOpacity(v) {
      this._fadeOpacity = Math.max(0, Math.min(1, Number(v) || 0));
      this._applyEffectiveFade(0);
    },

    _setVisibility(layerId, vis) {
      const m = this._map;
      if (m && m.getLayer(layerId)) m.setLayoutProperty(layerId, "visibility", vis);
    },
    _src(id) {
      const m = this._map;
      return m ? m.getSource(id) : null;
    },
    _initFanLanePool() {
      this._fanLanePool = [];
      const m = this._map;
      if (!m || !m.getLayer(TRAIN_EXPAND_LAYER)) return;
      this._fanLanePool.push({
        slot: 0,
        visibleId: TRAIN_EXPAND_LAYER,
        hoverId: TRAIN_EXPAND_HOVER_LAYER,
        pickId: TRAIN_PICK_FAN_LAYER,
        tid: null,
        translate: [0, 0],
      });
    },
    _ensureFanLanePool(size) {
      const m = this._map;
      if (!m) return;
      // addLayer THROWS while the style is mid-load, and this runs from the
      // ordinary data push — so a country switch that lands during boot, or
      // while a basemap install still has setGlyphs/setSprite in flight,
      // aborted the whole switch with "Style is not done loading" and left the
      // map empty. The pool is style scaffolding the first hover would rebuild
      // anyway: remember the size wanted, grow it when the style is ready, and
      // let the caller's data push stand. Same one-shot retry the network
      // upload above uses, re-checking because "styledata" also fires early.
      this._fanLanePoolWanted = Math.max(this._fanLanePoolWanted || 0, size);
      if (typeof m.isStyleLoaded === "function" && !m.isStyleLoaded()) {
        if (!this._fanLanePoolPending) {
          this._fanLanePoolPending = true;
          // "styledata" alone is not enough: the event that finally flips
          // isStyleLoaded() can be the last one, leaving the retry armed for a
          // style event that never comes. "idle" closes that gap; whichever
          // arrives first runs, and the other finds the flag already cleared.
          const retry = () => {
            if (!this._fanLanePoolPending) return;
            this._fanLanePoolPending = false;
            this._ensureFanLanePool(this._fanLanePoolWanted || 0);
          };
          m.once("styledata", retry);
          m.once("idle", retry);
        }
        return;
      }
      size = this._fanLanePoolWanted;
      if (!this._fanLanePool.length) this._initFanLanePool();
      while (this._fanLanePool.length < size) {
        const slot = this._fanLanePool.length;
        const visibleId = fanVisibleLayerId(slot);
        const hoverId = fanHoverLayerId(slot);
        const pickId = fanPickLayerId(slot);
        const translatePaint = {
          "line-translate": [0, 0],
          "line-translate-anchor": "map",
        };
        // Reuse a layer that already exists (a re-attach after hot reload
        // leaves earlier pool layers on the map) — addLayer throws on a
        // duplicate id, which would abort the whole data push.
        const addLayer = (layer, beforeId) => {
          if (!m.getLayer(layer.id)) m.addLayer(layer, beforeId);
        };
        addLayer(
          {
            id: pickId,
            type: "line",
            source: TRAIN_PICK_FAN_SOURCE,
            filter: MATCH_NONE,
            layout: { "line-cap": "round", "line-join": "round" },
            paint: {
              "line-color": "#000",
              "line-opacity": 0,
              "line-width": ["get", "pickWidth"],
              ...translatePaint,
            },
          },
          TRAIN_HOVER_LAYER,
        );
        addLayer(
          {
            id: visibleId,
            type: "line",
            source: TRAIN_EXPAND_SOURCE,
            filter: MATCH_NONE,
            layout: { "line-cap": "round", "line-join": "round" },
            paint: {
              "line-color": ["get", "colorA"],
              "line-opacity": this._expandOpacity || 0,
              "line-width": riddenLineWidth(),
              ...translatePaint,
            },
          },
          TRAIN_EXPAND_HOVER_LAYER,
        );
        addLayer(
          {
            id: hoverId,
            type: "line",
            source: TRAIN_EXPAND_SOURCE,
            filter: MATCH_NONE,
            layout: { "line-cap": "round", "line-join": "round" },
            paint: {
              "line-color": ["get", "colorA"],
              "line-opacity": 0,
              "line-width": riddenHoverLineWidth(),
              ...translatePaint,
            },
          },
          TRAIN_SEL_PASS_LAYER,
        );
        // A reused layer keeps stale filter/translate state from its previous
        // life; reset both so the fresh slot starts collapsed and unassigned.
        [pickId, visibleId, hoverId].forEach((id) => {
          if (m.getLayer(id)) {
            m.setFilter(id, MATCH_NONE);
            m.setPaintProperty(id, "line-translate", [0, 0]);
          }
        });
        const vis = this._visible ? "visible" : "none";
        [pickId, visibleId, hoverId].forEach((id) =>
          m.setLayoutProperty(id, "visibility", vis),
        );
        [pickId, visibleId, hoverId].forEach((id) =>
          m.setPaintProperty(id, "line-translate-transition", {
            duration: 0,
            delay: 0,
          }),
        );
        [visibleId, hoverId].forEach((id) =>
          m.setPaintProperty(id, "line-opacity-transition", {
            duration: 0,
            delay: 0,
          }),
        );
        this._fanLanePool.push({
          slot,
          visibleId,
          hoverId,
          pickId,
          tid: null,
          translate: [0, 0],
        });
      }
    },
    _setFanSlotFilters(slot) {
      const m = this._map;
      if (!m) return;
      const tidFilter = slot.tid
        ? ["==", ["get", "tid"], slot.tid]
        : MATCH_NONE;
      if (m.getLayer(slot.visibleId)) m.setFilter(slot.visibleId, tidFilter);
      if (m.getLayer(slot.hoverId)) m.setFilter(slot.hoverId, tidFilter);
      if (m.getLayer(slot.pickId))
        m.setFilter(
          slot.pickId,
          slot.tid && this._fanPickEnabled
            ? ["all", tidFilter, ["!=", ["get", "nopick"], 1]]
            : MATCH_NONE,
        );
    },
    _syncFanLaneAssignments(tids) {
      const desired = [...new Set((tids || []).filter(Boolean))];
      this._ensureFanLanePool(desired.length);
      const wanted = new Set(desired);
      this._fanLanePool.forEach((slot) => {
        if (slot.tid && !wanted.has(slot.tid)) slot.tid = null;
      });
      const assigned = new Set(
        this._fanLanePool.map((slot) => slot.tid).filter(Boolean),
      );
      desired.forEach((tid) => {
        if (assigned.has(tid)) return;
        let slot = this._fanLanePool.find((candidate) => !candidate.tid);
        if (!slot) {
          this._ensureFanLanePool(this._fanLanePool.length + 1);
          slot = this._fanLanePool[this._fanLanePool.length - 1];
        }
        slot.tid = tid;
        slot.translate = [0, 0];
        assigned.add(tid);
      });
      this._fanLanePool.forEach((slot) => this._setFanSlotFilters(slot));
    },
    _setFanPickEnabled(enabled) {
      this._fanPickEnabled = Boolean(enabled);
      this._fanLanePool.forEach((slot) => this._setFanSlotFilters(slot));
    },
    _fanPickLayerIds() {
      return this._fanLanePool.map((slot) => slot.pickId);
    },
    _directionToScreenPx(dir, gi) {
      if (!dir && !gi) return [0, -1];
      const d = dir || gi;
      const cs =
        (gi && gi.curve && gi.curve.coslat) ||
        Math.cos(((((gi && gi._latRef) || 0) * Math.PI) / 180)) ||
        1e-6;
      const x = (d.sx || 0) * cs;
      const y = d.sy || 0;
      const len = Math.hypot(x, y) || 1;
      return [x / len, -y / len];
    },
    // The fan's lane spacing is a screen-space constant, and one of the two
    // things on the map that deliberately does NOT ride the railway's scale
    // ramp (the hit targets are the other — see the weight contract at the top
    // of railmap-style.js). line-translate is pixel-valued, and the pixel
    // number is the one app-overlap-lanes.js sized for the POINTER rather than
    // for the eye: ~12 px per lane, so sliding between two fanned trains takes
    // a comfortable movement (currentOverlapSpacingPx). A fan that narrowed as
    // the map pulled back would close up exactly where the trains it separates
    // are hardest to tell apart, and would do it to the one gesture the fan
    // exists to serve.
    _fanSpacingPx() {
      return this._laneSpacingPx || 0;
    },
    _targetLaneOffsetPx(gi, tid, dir) {
      if (!gi || !Object.prototype.hasOwnProperty.call(gi.mults, tid))
        return [0, 0];
      const axis = this._directionToScreenPx(dir, gi);
      const distance = gi.mults[tid] * this._fanSpacingPx();
      return [axis[0] * distance, axis[1] * distance];
    },
    _applyFanLaneTranslations(group, factor) {
      const m = this._map;
      if (!m) return;
      const gi = group && this._groupInfo ? this._groupInfo.get(group) : null;
      const dir = this._fanDirGroup === group ? this._fanDirVec() : null;
      const transition = this._groupTransition;
      const f = factor == null ? (this._expandT == null ? 1 : this._expandT) : factor;
      this._fanLanePool.forEach((slot) => {
        if (!slot.tid) return;
        let next;
        if (transition && group === transition.toGroup) {
          const from = transition.fromOffsetsPx[slot.tid] || [0, 0];
          const target = this._targetLaneOffsetPx(transition.toGi, slot.tid, dir);
          const t = Math.max(0, Math.min(1, transition.progress || 0));
          next = [
            from[0] + (target[0] - from[0]) * t,
            from[1] + (target[1] - from[1]) * t,
          ];
        } else {
          const target = this._targetLaneOffsetPx(gi, slot.tid, dir);
          next = [target[0] * f, target[1] * f];
        }
        slot.translate = next;
        [slot.visibleId, slot.hoverId, slot.pickId].forEach((id) => {
          if (m.getLayer(id)) m.setPaintProperty(id, "line-translate", next);
        });
      });
    },
    _uploadFanSources(tids, groups) {
      const exp = this._src(TRAIN_EXPAND_SOURCE);
      if (exp)
        exp.setData(
          tids && tids.length
            ? routeExpandBaseFC(this._expandRecords, tids, this._rideStrokeGeneration)
            : EMPTY_FC,
        );
      const pick = this._src(TRAIN_PICK_FAN_SOURCE);
      if (pick)
        pick.setData(
          groups && groups.length
            ? routePickFanBaseFC(this._records, this._groupInfo, groups)
            : EMPTY_FC,
        );
    },
    _pushRoutes() {
      const shown = this._visible ? this._records : [];
      const src = this._src(TRAIN_ROUTES_SOURCE);
      if (src) src.setData(routeRecordsToFC(shown));
      this._pushPick();
    },
    _pushFitCurves() {
      // The fitted-curve overlay is a debug layer that is HIDDEN by default
      // (setFitCurvesVisible false; layer visibility 'none'). Uploading its
      // source on every route render forces a worker re-tile + repaint for
      // geometry nobody sees. Skip when hidden — setFitCurvesVisible() pushes
      // on enable and every subsequent data change while visible still pushes,
      // so the curves populate the moment the overlay is turned on.
      if (!this._fitCurvesVisible) return;
      const src = this._src(FIT_CURVES_SOURCE);
      if (src) src.setData(fitCurvesToFC(this._groupInfo));
    },
    _pushHoverRegions(state) {
      this._hoverDebugState = state || null;
      const fc = this._hoverRegionsVisible
        ? hoverRegionsToFC(this._map, this._hoverDebugState)
        : EMPTY_FC;
      const src = this._src(HOVER_REGIONS_SOURCE);
      if (src && this._hoverRegionsVisible) src.setData(fc);
      // Diagnostics dataset for the (default-OFF) hover-region debug overlay.
      // Gated on _hoverRegionsVisible: building this ~18-field object +
      // JSON.stringify + DOM dataset write ran on EVERY hover frame otherwise,
      // pure waste when the overlay is off (which it is in production).
      if (this._hoverRegionsVisible && this._map && this._map.getContainer) {
        const container = this._map.getContainer();
        container.dataset.hoverRegionReport = JSON.stringify({
          visible: this._hoverRegionsVisible,
          routePadPx:
            state && state.routePadPx != null
              ? state.routePadPx
              : HOVER_PICK_PAD_PX,
          stickyPadPx: HOVER_STICKY_PAD_PX,
          holdRadiusPx: HOVER_FAN_HOLD_PX,
          switchRadiusPx: HOVER_GROUP_SWITCH_PX,
          zoom: this._map ? +this._map.getZoom().toFixed(2) : null,
          // Debug-only physical-radius approximation from the live pointer
          // latitude and zoom. Fan spacing itself is pixel-valued and does
          // not use this conversion.
          stickyRadiusApproxMeters:
            this._map && state && state.point
              ? +(
                  (156543.03392 *
                    Math.cos(
                      (this._map.unproject(state.point).lat * Math.PI) / 180,
                    ) *
                    HOVER_FAN_HOLD_PX) /
                  Math.pow(2, this._map.getZoom())
                ).toFixed(1)
              : null,
          hasHold: Boolean(state && state.holdPoint),
          hasSwitch: Boolean(state && state.switchPoint),
          hovered: Boolean(this._hoverTrainId),
          expanded: Boolean(this._expandedGroup),
          pointer: state && state.point ? state.point : null,
          holdCenter: state && state.holdPoint ? state.holdPoint : null,
          distanceFromHoldPx:
            state && state.point && state.holdPoint
              ? +Math.hypot(
                  state.point.x - state.holdPoint.x,
                  state.point.y - state.holdPoint.y,
                ).toFixed(2)
              : null,
          featureKinds: fc.features.map((f) => f.properties.kind),
        });
      }
    },
    _refreshFitCurveDiagnostics() {
      this._fitCurveDiagnostics = diagnoseFitCurves(this._groupInfo);
      if (this._map && this._map.getContainer) {
        const container = this._map.getContainer();
        container.dataset.fitCurveReport = JSON.stringify(
          this._fitCurveDiagnostics,
        );
        container.dataset.fitCurveCount = String(
          this._fitCurveDiagnostics.curves,
        );
      }
      return this._fitCurveDiagnostics;
    },
    // Re-upload the STATIC pick source: every record's true-track hit area.
    // Depends only on the record set (never on fan state or lane spacing), so
    // it uploads on data changes alone — fan open/close touches only the
    // small fan-scoped source below.
    _pushPick() {
      const pick = this._src(TRAIN_PICK_SOURCE);
      if (pick)
        pick.setData(
          routePickRecordsToFC(
            this._visible ? this._records : [],
            this._groupInfo,
          ),
        );
    },
    // The fan pick source contains true-track geometry. Pooled tid layers move
    // their visible and hit-test copies together through line-translate.
    _pushPickFan() {
      const group = this._expandedGroup;
      const transition = this._groupTransition;
      if (!this._visible || (!group && !transition)) {
        this._setFanPickEnabled(false);
        const src = this._src(TRAIN_PICK_FAN_SOURCE);
        if (src) src.setData(EMPTY_FC);
        return;
      }
      const groups = transition
        ? [transition.fromGroup, transition.toGroup]
        : [group];
      const tids = this._fanLanePool
        .map((slot) => slot.tid)
        .filter(Boolean);
      this._uploadFanSources(tids, groups);
      this._setFanPickEnabled(true);
    },
    // Coalesce animated paint updates to at most one per frame. GeoJSON is
    // uploaded only when fan membership changes; slide/rotation frames touch
    // constant line-translate values and never wake the worker tiler.
    _scheduleExpandPush(group, factor) {
      this._pendingExpandPush = { group, factor };
      if (this._expandPushRaf != null) return;
      this._expandPushRaf = requestAnimationFrame(() => {
        this._expandPushRaf = null;
        const p = this._pendingExpandPush;
        this._pendingExpandPush = null;
        if (p) this._pushExpandFC(p.group, p.factor);
      });
    },
    _pushExpandFC(group, factor) {
      // A synchronous push is the latest truth — drop any stale queued frame.
      if (this._expandPushRaf != null) {
        cancelAnimationFrame(this._expandPushRaf);
        this._expandPushRaf = null;
        this._pendingExpandPush = null;
      }
      this._applyFanLaneTranslations(group, factor);
    },

    // ── dynamic fan direction ────────────────────────────────────────────
    // The fan's shift axis is NOT a constant per group: it is the local
    // perpendicular of the corridor's smoothed curve (app.js groupInfo
    // `curve`) at the point under the pointer. _setFanDirTarget is fed by
    // every hover pass; the angle then eases toward the target in its own
    // rAF loop so the fan ROTATES smoothly while the pointer travels the
    // corridor instead of snapping at every sample.
    _fanTheta: null, // current animated angle of the perpendicular (scaled space)
    _fanThetaTarget: null,
    _fanCoslat: 1,
    _fanCurve: null, // curve object the angle currently refers to
    _fanCurveS: null, // last projected arc position (same-branch hysteresis)
    _fanCurveSign: 1, // fixed within one fitted curve; avoids axis flip-flop
    _fanDirGroup: null, // group the direction was computed for
    _fanSwitchFromDir: null,
    _fanDirVec() {
      if (this._fanTheta == null) return null;
      const cs = this._fanCoslat || 1;
      return {
        sx: Math.cos(this._fanTheta) / cs, // degree-space, like gi.sx/sy
        sy: Math.sin(this._fanTheta),
      };
    },
    _setFanDirTarget(group, lngLat) {
      const gi = this._groupInfo ? this._groupInfo.get(group) : null;
      if (!gi) return;
      const previousGroup = this._fanDirGroup;
      const previousDir = this._fanDirVec();
      const curve = gi.curve || null;
      let ux;
      let uy;
      let cs;
      if (curve && lngLat) {
        const sameCurve = this._fanCurve === curve;
        const p = fanPerpAt(curve, lngLat, sameCurve ? this._fanCurveS : null);
        ux = p.x;
        uy = p.y;
        cs = curve.coslat;
        this._fanCurveS = p.s;
        if (!sameCurve) {
          // A curve axis is equivalent under a 180° flip. A fresh fan aligns
          // with the canonical group axis; an already-open fan entering a new
          // interval aligns with its CURRENT visible side. This prevents lane
          // offsets from needlessly rotating almost 180° at a group boundary.
          const keepVisibleSide =
            previousDir &&
            previousGroup &&
            previousGroup !== group &&
            (this._expandedGroup || this._animGroup) &&
            (this._expandT || 0) > 0;
          const refX = keepVisibleSide ? previousDir.sx * cs : gi.sx * cs;
          const refY = keepVisibleSide ? previousDir.sy : gi.sy;
          this._fanCurveSign = ux * refX + uy * refY < 0 ? -1 : 1;
        }
        ux *= this._fanCurveSign;
        uy *= this._fanCurveSign;
      } else {
        // No curve: fall back to the group's static vector.
        cs =
          Math.cos((((gi._latRef || 0) * Math.PI) / 180)) || 1e-6;
        ux = gi.sx * cs;
        uy = gi.sy;
        this._fanCurveS = null;
        this._fanCurveSign = 1;
      }
      const target = Math.atan2(uy, ux);
      if (previousGroup && previousGroup !== group)
        this._fanSwitchFromDir = previousDir;
      this._fanCoslat = cs;
      this._fanDirGroup = group;
      // Only a fresh fan snaps to its initial direction. Once a fan is open,
      // crossing into a different corridor also takes the nearest angular path
      // and eases, so the translation axis cannot jump at the boundary.
      const canEase =
        this._fanTheta != null &&
        (this._expandedGroup || this._animGroup) &&
        (this._expandT || 0) > 0;
      this._fanCurve = curve;
      if (!canEase) {
        this._fanTheta = target;
        this._fanThetaTarget = target;
        return;
      }
      // Take the nearest equivalent angle so easing never goes the long way
      // around the circle.
      let d = target - this._fanTheta;
      while (d > Math.PI) d -= 2 * Math.PI;
      while (d < -Math.PI) d += 2 * Math.PI;
      this._fanThetaTarget = this._fanTheta + d;
      this._ensureFanDirAnim();
    },
    _ensureFanDirAnim() {
      if (this._fanDirRaf) return;
      this._fanDirLast = performance.now();
      const step = (now) => {
        this._fanDirRaf = null;
        if (this._fanTheta == null || this._fanThetaTarget == null) return;
        const dt = Math.min(50, now - (this._fanDirLast || now));
        this._fanDirLast = now;
        const d = this._fanThetaTarget - this._fanTheta;
        let settled = false;
        if (Math.abs(d) < 0.002) {
          this._fanTheta = this._fanThetaTarget;
          settled = true;
        } else {
          // Exponential ease: frame-rate independent, always smooth.
          this._fanTheta += d * (1 - Math.exp(-dt / 90));
          this._fanDirRaf = requestAnimationFrame(step);
        }
        const g = this._expandedGroup || this._animGroup;
        if (g && this._fanDirGroup === g) {
          // Mid-ease frames go through the per-frame coalescer (the slide
          // animation may want the same frame's upload); the settled angle
          // commits synchronously so the final geometry is exact.
          if (settled) this._pushExpandFC(g);
          else this._scheduleExpandPush(g);
          // Visible, hover and pick layers share the same translated slot, so
          // hit geometry follows every cheap paint update with no source push.
        }
      };
      this._fanDirRaf = requestAnimationFrame(step);
    },
    // ONE source holds every marker; the base/SEL split is pure layer
    // filtering (see _applyMarkerSelectionFilters) and category visibility is
    // layer visibility — so this pushes only when the record set changes.
    _pushMarkers() {
      const src = this._src(TRAIN_MARKERS_SOURCE);
      if (src) src.setData(markerRecordsToFC(this._markers));
    },
    // Expansion selects by TRAIN SET, not by the single hovered run: every
    // train sharing the hovered stretch shows as its COMPLETE course rigidly
    // translated into its lane — one intact copy of the whole line, corners /
    // radii / lengths unchanged, never broken into pieces mid-route.
    _expandSelector(tids) {
      return ["in", ["get", "tid"], ["literal", tids || []]];
    },
    // While a fan is engaged, the true-track layers (base / hover / sel)
    // EXCLUDE the engaged trains entirely — their translated copies fully
    // replace them, so nothing draws down the middle of the fan and nothing
    // draws twice.
    _notExpanded() {
      return ["!", this._expandSelector(this._engagedTids)];
    },
    _applyBaseFilters() {
      const m = this._map;
      if (!m) return;
      // Owns the base layer's filter: solid lines are "not expanded AND not
      // the cross-day half", the dashed layer takes the remainder.
      this._applyXDayFilters();
      // Engaged trains' TRUE-TRACK hit areas leave the static pick layer while
      // their fan lanes (in the fan pick source) replace them — otherwise the
      // emptied corridor centre would still hit-test as the member trains.
      if (m.getLayer(TRAIN_PICK_LAYER))
        m.setFilter(TRAIN_PICK_LAYER, [
          "all",
          ["!=", ["get", "nopick"], 1],
          this._notExpanded(),
        ]);
      this._applySelectionFilters();
      this._applyHoverFilter();
    },
    _applySelectionFilters() {
      const m = this._map;
      if (!m) return;
      const id = this._selectedTrainId || NO_TRAIN;
      // The dashed cross-day half stays dashed even when its train is picked:
      // the SEL layers would redraw it solid (and wider) on top otherwise.
      const f = [
        "all",
        ["==", ["get", "tid"], id],
        this._notExpanded(),
        ["!", this._xDaySelector()],
      ];
      if (m.getLayer(TRAIN_SEL_CASING_LAYER)) m.setFilter(TRAIN_SEL_CASING_LAYER, f);
      if (m.getLayer(TRAIN_SEL_LAYER)) m.setFilter(TRAIN_SEL_LAYER, f);
    },
    _applyHoverFilter() {
      const m = this._map;
      if (!m) return;
      this._applyHoverDim();
      this._applyHoverLayerFilters();
    },
    // Hover emphasis is a separate, wider line layer.  A tid filter that
    // changes directly from A to B cannot animate, so keep every tid whose
    // focus weight is still non-zero (plus its next target) in the layer and
    // let _applyDimPaint crossfade their line-opacity values.  The same union
    // drives the expanded-fan hover layer.
    _applyHoverLayerFilters() {
      const m = this._map;
      if (!m) return;
      const focusTids = this._opacityWeightIds(
        this._dimFocusWeights,
        this._dimFocusWeightTargets,
      );
      if (m.getLayer(TRAIN_HOVER_LAYER))
        m.setFilter(TRAIN_HOVER_LAYER, [
          "all",
          this._expandSelector(focusTids),
          this._notExpanded(),
          // Same reason as the SEL layers: hovering must not un-dash the
          // cross-day half by drawing it solid on top.
          ["!", this._xDaySelector()],
        ]);
      // Fan hover layers are already one-tid-per-slot; their focus crossfade
      // is entirely paint-driven and must not overwrite the pool assignment.
    },

    // ── hover spotlight: dim every train that is NOT being hovered ──
    // Active set = the expanded parallel group while a fan is showing (also
    // during its fade-out), else the single hovered train. Everything else —
    // route lines AND stop/pass-through dots — fades to HOVER_DIM.
    //
    // P0 path: this changes ONLY layer paint expressions (setPaintProperty),
    // never touches a GeoJSON source; the rAF dim engine below animates the
    // strengths.
    _activeHoverTids() {
      if (this._expandFilterTids.length) return this._expandFilterTids;
      if (this._hoverTrainId) return [this._hoverTrainId];
      return null;
    },
    // ── animated dim engine ────────────────────────────────────────────
    // MapLibre does NOT transition DATA-DRIVEN paint properties — every
    // opacity here is a per-feature expression (keyed on tid / tdate), so
    // declared *-transition values were silently ignored and every dim
    // change snapped. Instead, THREE dim modes each get an animated strength
    // (0..1) driven by ONE rAF loop; each frame rebuilds the opacity
    // expressions with the current strengths lerped in:
    //   date  -> off-date features lerp own-alpha -> flat _dateDim
    //   sel   -> non-selected features lerp own -> flat SELECT_DIM
    //   hover -> non-hovered features multiply toward HOVER_DIM;
    //            hovered features lerp their sel-dim away (spotlight wins)
    // Hover role changes get a second pair of animated weight maps: one for
    // the spotlight set (a whole expanded group can stay bright) and one for
    // the single widened focus line.  This makes A -> B a true crossfade even
    // while the global hover strength is already settled at 1.
    _dimSpeedMs: { hover: 250, sel: 350, date: 400 },
    _syncOpacityWeights(weightsKey, targetsKey, desiredIds, alreadyActive) {
      const desired = new Set((desiredIds || []).filter(Boolean));
      let weights = this[weightsKey];
      if (!(weights instanceof Map)) weights = new Map();
      const targets = new Map();
      if (!desired.size) {
        // The global hover strength already supplies the leave fade.  Holding
        // the last membership weights until that reaches zero avoids dipping
        // the formerly hovered line through the dim state on its way out.
        weights.forEach((weight, id) => targets.set(id, weight));
      } else {
        weights.forEach((_weight, id) => targets.set(id, desired.has(id) ? 1 : 0));
        desired.forEach((id) => {
          if (!weights.has(id)) weights.set(id, alreadyActive ? 0 : 1);
          targets.set(id, 1);
        });
      }
      this[weightsKey] = weights;
      this[targetsKey] = targets;
    },
    _opacityWeightIds(weights, targets) {
      const ids = new Set();
      if (weights instanceof Map)
        weights.forEach((weight, id) => {
          if (weight > 0) ids.add(id);
        });
      if (targets instanceof Map)
        targets.forEach((target, id) => {
          if (target > 0) ids.add(id);
        });
      return [...ids];
    },
    _opacityWeightExpr(weights) {
      if (!(weights instanceof Map)) return 0;
      const entries = [...weights].filter(([, weight]) => weight > 0);
      if (!entries.length) return 0;
      const expr = ["match", ["get", "tid"]];
      entries.forEach(([id, weight]) => expr.push(id, weight));
      expr.push(0);
      return expr;
    },
    _advanceOpacityWeights(weightsKey, targetsKey, dt, duration) {
      const weights = this[weightsKey];
      const targets = this[targetsKey];
      if (!(weights instanceof Map) || !(targets instanceof Map))
        return { moving: false, filtersDirty: false };
      let moving = false;
      let filtersDirty = false;
      targets.forEach((target, id) => {
        const cur = weights.get(id) || 0;
        const rate = dt / duration;
        const next =
          cur < target
            ? Math.min(target, cur + rate)
            : Math.max(target, cur - rate);
        if (next === 0 && target === 0) {
          weights.delete(id);
          targets.delete(id);
          filtersDirty = true;
          return;
        }
        weights.set(id, next);
        if (next !== target) moving = true;
      });
      return { moving, filtersDirty };
    },
    _updateDimTargets() {
      if (!this._dimVals) {
        this._dimVals = { hover: 0, sel: 0, date: 0 };
        this._dimTargets = { hover: 0, sel: 0, date: 0 };
      }
      // Latch the last-known active sets so a fade-OUT still knows which
      // features were dimmed while the strength ramps back to 0.
      const hoverTids = this._activeHoverTids();
      const hoverAlreadyActive =
        this._dimVals.hover > 0 || this._dimTargets.hover > 0;
      this._syncOpacityWeights(
        "_dimHoverWeights",
        "_dimHoverWeightTargets",
        hoverTids,
        hoverAlreadyActive,
      );
      this._syncOpacityWeights(
        "_dimFocusWeights",
        "_dimFocusWeightTargets",
        this._hoverTrainId ? [this._hoverTrainId] : null,
        hoverAlreadyActive,
      );
      if (this._selectedTrainId) this._dimSelId = this._selectedTrainId;
      if (this._activeDate) this._dimDate = this._activeDate;
      this._dimTargets = {
        hover: hoverTids && hoverTids.length ? 1 : 0,
        sel: this._selectedTrainId ? 1 : 0,
        date: this._activeDate ? 1 : 0,
      };
      // Commit the exact current state before the next animation frame.  On a
      // role change this is still the OLD visual state (old weight 1, new
      // weight 0), so no frame can flash the new route fully opaque.
      this._applyDimPaint();
      this._ensureDimAnim();
    },
    _ensureDimAnim() {
      if (this._dimRaf) return;
      const step = (now) => {
        this._dimRaf = null;
        const dt = Math.min(50, now - (this._dimLast || now));
        this._dimLast = now;
        let moving = false;
        let hoverFiltersDirty = false;
        ["hover", "sel", "date"].forEach((k) => {
          const target = this._dimTargets[k];
          const cur = this._dimVals[k];
          if (cur === target) return;
          const rate = dt / this._dimSpeedMs[k];
          const next =
            cur < target
              ? Math.min(target, cur + rate)
              : Math.max(target, cur - rate);
          this._dimVals[k] = next;
          if (next !== target) moving = true;
        });
        [
          ["_dimHoverWeights", "_dimHoverWeightTargets"],
          ["_dimFocusWeights", "_dimFocusWeightTargets"],
        ].forEach(([weightsKey, targetsKey]) => {
          const result = this._advanceOpacityWeights(
            weightsKey,
            targetsKey,
            dt,
            this._dimSpeedMs.hover,
          );
          if (result.moving) moving = true;
          if (result.filtersDirty) hoverFiltersDirty = true;
        });
        // Rebuilding the data-driven opacity expressions forces MapLibre to
        // re-evaluate paint for EVERY feature on up to nine layers — doing
        // that at 60–120 Hz for a 250–400 ms fade is the single biggest
        // main-thread cost while a hover engages. ~30 Hz is visually
        // indistinguishable for an opacity ramp; the final (settled) frame
        // always applies so end states are exact.
        if (!moving || now - (this._dimPaintAt || 0) >= 30)
          this._applyDimPaint();
        if (hoverFiltersDirty) this._applyHoverLayerFilters();
        if (moving) {
          this._dimRaf = requestAnimationFrame(step);
        } else {
          if (this._dimTargets.hover === 0 && this._dimVals.hover === 0) {
            this._dimHoverWeights = new Map();
            this._dimHoverWeightTargets = new Map();
            this._dimFocusWeights = new Map();
            this._dimFocusWeightTargets = new Map();
            this._applyHoverLayerFilters();
          }
          this._dimLast = null;
        }
      };
      this._dimLast = performance.now();
      this._dimRaf = requestAnimationFrame(step);
    },
    _applyDimPaint() {
      const m = this._map;
      if (!m || !this._dimVals) return;
      this._dimPaintAt = performance.now();
      const v = this._dimVals;
      const easeS = (s) => 1 - Math.pow(1 - s, 2); // gentle ease-out
      const sDate = easeS(v.date);
      const sSel = easeS(v.sel);
      const sHover = easeS(v.hover);
      // lerp helpers that collapse to plain values at the endpoints so the
      // steady-state expressions stay as small as before.
      const lerpNum = (expr, num, s) =>
        s >= 1 ? num : s <= 0 ? expr : ["+", ["*", expr, 1 - s], num * s];
      const lerpExpr = (a, b, s) =>
        s >= 1 ? b : s <= 0 ? a : ["+", ["*", a, 1 - s], ["*", b, s]];
      const mixByWeight = (a, b, weight) =>
        typeof weight === "number"
          ? lerpExpr(a, b, weight)
          : ["+", ["*", a, ["-", 1, weight]], ["*", b, weight]];
      const dateDim = this._dateDim ?? 0.18;
      // In scope = the feature's train RUNS on the selected day. `dspan` lists
      // every date the train touches, so an overnight train stays undimmed on
      // both of its days (its off-day half is told apart by the dash, not by
      // fading it into the background).
      const dateWrap = (own) =>
        sDate > 0 && this._dimDate
          ? [
              "case",
              ["in", "|" + this._dimDate + "|", ["get", "dspan"]],
              own,
              lerpNum(own, dateDim, sDate),
            ]
          : own;
      // Non-selected features head toward the flat SELECT_DIM (NOT
      // multiplied into their alpha, or off-date trains would end up dimmer
      // than same-day ones).
      const selWrap = (own) =>
        sSel > 0 && this._dimSelId
          ? [
              "case",
              ["==", ["get", "tid"], this._dimSelId],
              own,
              lerpNum(own, SELECT_DIM, sSel),
            ]
          : own;
      const hoverWeight = this._opacityWeightExpr(this._dimHoverWeights);
      const focusWeight = this._opacityWeightExpr(this._dimFocusWeights);
      const hoverActive = sHover > 0 && hoverWeight !== 0;
      const hoverMul = 1 - (1 - HOVER_DIM) * sHover;
      const chain = (own) => {
        const base = selWrap(dateWrap(own));
        if (!hoverActive) return base;
        // Hovered features climb OUT of the selection dim toward their
        // date-scoped alpha; everyone else multiplies toward HOVER_DIM.  A
        // fractional weight crossfades old/new hover membership.
        return mixByWeight(
          ["*", base, hoverMul],
          lerpExpr(base, dateWrap(own), sHover),
          hoverWeight,
        );
      };
      const set = (id, prop, value) => {
        if (m.getLayer(id)) m.setPaintProperty(id, prop, value);
      };
      const baseOpacity = chain(["get", "alpha"]);
      // SEL layers only ever contain the selected train (always "active"):
      // only the hover spotlight can dim them.
      const selLayerVal = hoverActive
        ? mixByWeight(hoverMul, 1, hoverWeight)
        : 1;
      const focusLayerVal =
        sHover > 0 && focusWeight !== 0
          ? typeof focusWeight === "number"
            ? sHover * focusWeight
            : ["*", sHover, focusWeight]
          : 0;
      set(TRAIN_ROUTES_LAYER, "line-opacity", baseOpacity);
      set(TRAIN_XDAY_LAYER, "line-opacity", baseOpacity);
      set(TRAIN_XDAY_STOP_LAYER, "icon-opacity", baseOpacity);
      set(TRAIN_HOVER_LAYER, "line-opacity", focusLayerVal);
      set(
        TRAIN_SEL_CASING_LAYER,
        "line-opacity",
        hoverActive ? ["*", 0.9, selLayerVal] : 0.9,
      );
      set(TRAIN_SEL_LAYER, "line-opacity", selLayerVal);
      [TRAIN_PASS_LAYER, TRAIN_STOPS_LAYER].forEach((id) => {
        set(id, "circle-opacity", baseOpacity);
        set(id, "circle-stroke-opacity", baseOpacity);
      });
      [TRAIN_SEL_PASS_LAYER, TRAIN_SEL_STOPS_LAYER].forEach((id) => {
        set(id, "circle-opacity", selLayerVal);
        set(id, "circle-stroke-opacity", selLayerVal);
      });
      const fanFocusOpacity =
        typeof focusLayerVal === "number"
          ? (this._expandOpacity || 0) * focusLayerVal
          : ["*", this._expandOpacity || 0, focusLayerVal];
      this._fanLanePool.forEach((slot) =>
        set(slot.hoverId, "line-opacity", fanFocusOpacity),
      );
    },
    // Single entry point every dim-state change funnels through.
    _applyHoverDim() {
      this._updateDimTargets();
    },

    // ── hover-expand: fan an overlapped group out into its parallel lanes ──
    // _expandedGroup / _expandedTids = the hovered run's group and its trains
    // _engagedTids = trains whose true-track overlap-lines are hidden right
    //   now (their continuous expand twins replace them)
    // _expandFilterTids = the trains the expand layers currently SHOW (kept
    //   through the collapse slide so the lanes glide home before vanishing)
    //
    // PURE SLIDE — no opacity crossfade (a fade made the corridor visibly
    // flash on hover). At factor 0 every member's expand twin lies EXACTLY on
    // its true track with identical colour/width/alpha, so the base lines can
    // be swapped for the twins (and back) with zero visible change; the only
    // animated quantity is the lane-offset factor, so expanding slides the
    // lines apart and collapsing slides them home.
    _setExpandedGroup(g) {
      const next = g || null;
      const previous = this._expandedGroup;
      if (next === previous) return;
      this._expandedGroup = next;
      const m = this._map;
      if (!m) return;
      const engage = () => {
        const t = this._expandedTids;
        const same =
          t.length === this._engagedTids.length &&
          t.every((x) => this._engagedTids.includes(x));
        if (same) return;
        this._engagedTids = t.slice();
        this._applyBaseFilters();
      };
      const release = () => {
        if (this._expandedGroup) return; // re-expanded meanwhile
        if (!this._engagedTids.length) return;
        this._engagedTids = [];
        this._applyBaseFilters();
      };
      if (next) {
        const gi = this._groupInfo ? this._groupInfo.get(next) : null;
        const nextTids = gi ? Object.keys(gi.mults) : [];
        const previousGi =
          previous && this._groupInfo ? this._groupInfo.get(previous) : null;
        // OPEN GROUP → DIFFERENT OPEN GROUP: interpolate lane configurations
        // instead of replacing one translated GeoJSON source with the other.
        if (previous && previousGi && gi && (this._expandT || 0) > 0) {
          if (this._expandAnimId) {
            cancelAnimationFrame(this._expandAnimId);
            this._expandAnimId = null;
          }
          const previousTids = this._fanLanePool
            .map((slot) => slot.tid)
            .filter(Boolean);
          const fromOffsetsPx = {};
          this._fanLanePool.forEach((slot) => {
            if (slot.tid)
              fromOffsetsPx[slot.tid] = slot.translate.slice();
          });
          const unionTids = [...new Set(previousTids.concat(nextTids))];
          this._expandT = 1;
          this._animGroup = next;
          this._expandedTids = unionTids;
          this._expandFilterTids = unionTids;
          this._engagedTids = unionTids.slice();
          this._groupTransition = {
            fromGroup: previous,
            toGroup: next,
            fromGi: previousGi,
            toGi: gi,
            fromOffsetsPx,
            progress: 0,
          };
          this._fanSwitchFromDir = null;
          this._syncFanLaneAssignments(unionTids);
          this._uploadFanSources(unionTids, [previous, next]);
          this._setFanPickEnabled(true);
          this._setExpandOpacity(1);
          this._applyBaseFilters();
          this._applyHoverFilter();
          this._pushExpandFC(next, 1);
          this._animateGroupTransition(next, nextTids);
          return;
        }
        // Fill the group-scoped expand source with the member trains'
        // translated complete courses (rigid shift, geometry untouched).
        // Offsets start at the CURRENT slide progress (0 when fresh — i.e.
        // exactly on the true track) and slide outward from there.
        this._animGroup = next;
        this._syncFanLaneAssignments(nextTids);
        this._uploadFanSources(nextTids, [next]);
        this._setFanPickEnabled(true);
        this._pushExpandFC(next, this._expandT || 0);
        this._expandedTids = nextTids;
        this._expandFilterTids = nextTids;
        // The open group's hit areas move from the true track out to the
        // per-lane paths (they only exist there while the fan is open).
        this._applyHoverFilter();
        // Twins are pixel-identical to the base lines at their current
        // factor, so the base->twin swap is invisible — engage at once.
        this._setExpandOpacity(1);
        engage();
        if (this._expandT === 1) {
          // Already fully fanned (pointer slid between groups): nothing to
          // animate — but cancel any queued collapse frame or it would keep
          // sliding the lanes home.
          if (this._expandAnimId) {
            cancelAnimationFrame(this._expandAnimId);
            this._expandAnimId = null;
          }
          return;
        }
        this._animateExpand(1, null);
      } else {
        if (this._groupTransitionRaf) {
          cancelAnimationFrame(this._groupTransitionRaf);
          this._groupTransitionRaf = null;
        }
        this._groupTransition = null;
        this._expandedTids = [];
        // Hit areas snap back to the true track right away (the fan is
        // closing; hovering the line itself may legitimately re-open it).
        this._pushPickFan();
        // Slide the lanes home first; only then swap the twins back for the
        // (identical) true-track lines and empty the expand source.
        this._animateExpand(0, () => {
          release();
          this._expandFilterTids = [];
          this._animGroup = null;
          this._pushExpandFC(null, 0);
          this._syncFanLaneAssignments([]);
          this._uploadFanSources([], []);
          this._applyHoverFilter();
        });
      }
    },
    _animateGroupTransition(targetGroup, targetTids) {
      if (this._groupTransitionRaf)
        cancelAnimationFrame(this._groupTransitionRaf);
      this._groupTransitionRaf = null;
      const transition = this._groupTransition;
      if (!transition) return;
      const duration = 320;
      const t0 = performance.now();
      const step = (now) => {
        if (
          !this._groupTransition ||
          this._groupTransition !== transition ||
          this._expandedGroup !== targetGroup
        ) {
          this._groupTransitionRaf = null;
          return;
        }
        const k = Math.min(1, (now - t0) / duration);
        // smoothstep has zero velocity at both ends, eliminating the small
        // arrival kick that ease-out produced at overlap boundaries.
        transition.progress = k * k * (3 - 2 * k);
        if (k < 1) {
          this._scheduleExpandPush(targetGroup, 1);
          this._groupTransitionRaf = requestAnimationFrame(step);
          return;
        }
        this._groupTransitionRaf = null;
        this._groupTransition = null;
        this._expandedTids = targetTids.slice();
        this._expandFilterTids = targetTids.slice();
        this._engagedTids = targetTids.slice();
        this._syncFanLaneAssignments(targetTids);
        // Re-scope the fan sources to the settled group. Leaving the FROM
        // group's records in the pick source would keep translated hit
        // geometry alive along the old corridor for every staying member
        // (their pooled layers filter by tid alone), stretching the sticky
        // hold far outside the open fan.
        this._uploadFanSources(targetTids, [targetGroup]);
        this._applyBaseFilters();
        this._applyHoverFilter();
        this._pushExpandFC(targetGroup, 1);
      };
      this._groupTransitionRaf = requestAnimationFrame(step);
    },
    _setExpandOpacity(v) {
      const m = this._map;
      if (!m) return;
      this._expandOpacity = Math.max(0, Math.min(1, Number(v) || 0));
      this._fanLanePool.forEach((slot) => {
        if (m.getLayer(slot.visibleId))
          m.setPaintProperty(
            slot.visibleId,
            "line-opacity",
            this._expandOpacity,
          );
      });
      // The widened lane has its own hover A -> B crossfade expression; only
      // its fan visibility multiplier changes here.
      this._applyDimPaint();
    },
    // Animate ONLY the lane-offset factor (the slide); opacity stays put.
    _animateExpand(target, done) {
      if (this._expandAnimId) cancelAnimationFrame(this._expandAnimId);
      this._expandAnimId = null;
      const from = this._expandT || 0;
      if (from === target) {
        if (this._animGroup) this._pushExpandFC(this._animGroup, target);
        if (done) done();
        return;
      }
      const dur = 240;
      const t0 = performance.now();
      const step = (now) => {
        const k = Math.min(1, (now - t0) / dur);
        const e = 1 - Math.pow(1 - k, 3); // ease-out
        const v = from + (target - from) * e;
        this._expandT = v;
        // Slide the fan: re-translate the group's lanes at this frame's
        // progress so the lines physically move out/in. Mid-animation frames
        // coalesce with any same-frame fan-direction push; the final frame
        // commits synchronously so the settled position is exact.
        if (k < 1) {
          if (this._animGroup) this._scheduleExpandPush(this._animGroup, v);
          this._expandAnimId = requestAnimationFrame(step);
        } else {
          if (this._animGroup) this._pushExpandFC(this._animGroup, v);
          this._expandAnimId = null;
          if (done) done();
        }
      };
      this._expandAnimId = requestAnimationFrame(step);
    },
  };

  global.RailMap = RailMap;
})(window);
