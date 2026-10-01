// =========================================================================
//  app-precompute-adapter.js — explicit offline precompute contract
//
//  The Node VM calls this single global adapter instead of reaching into the
//  app family's arbitrary lexical state. Browser behavior is unchanged.
// =========================================================================

async function preparePrecomputeTrainStore(host) {
  activeCountry = host.country;
  for (const [country, overlay] of Object.entries(host.historyOverlays || {}))
    loadRailHistoryOverlay(overlay, country);
  applyLoadedRailHistoryToStations(host.stations, host.country);
  applyLoadedRailHistoryToSections(host.railSections, host.stations, host.country);
  AppDatasets.installRailSections(host.railSections);
  AppDatasets.installStations(host.stations);
  AppDatasets.installMatchedData({
    matchedRoutes: { type: "FeatureCollection", features: [] },
    matchedStops: host.matchedStops,
  });
  await buildStationIndexesSliced(stationsGeoJson);

  return parseImportedCanonicalStore(host.trainStoreText);
}

function serializedPrecomputeSolveContext(train, solveContext, host) {
  const serialized = getTrainRouteSolveContext(train);
  if (!solveContext || !serialized) return serialized;
  const historyHashes = Object.fromEntries(
    Object.keys(solveContext.historyRevisions)
      .sort()
      .filter((country) => host.historyHashes?.[country])
      .map((country) => [country, host.historyHashes[country]]),
  );
  const hashEntries = Object.entries(historyHashes);
  if (!hashEntries.length) return serialized;

  const revisionIdentity = canonicalRailHistoryRevisionsForRegions(
    Object.keys(solveContext.historyRevisions));
  const historyToken = `|history:${revisionIdentity}`;
  const historyOffset = solveContext.cacheKey.indexOf(historyToken);
  if (historyOffset < 0) {
    throw new Error("Route solve cache key has no canonical history identity.");
  }
  const insertionOffset = historyOffset + historyToken.length;
  const hashIdentity = hashEntries
    .map(([country, hash]) => `${country}:${hash}`)
    .join("|");
  // RouteService keeps using `solveContext.cacheKey`; this identity exists
  // only to let native reconstruct and authenticate the exported geometry.
  const attestedCacheKey =
    solveContext.cacheKey.slice(0, insertionOffset) +
    `|hashes:${hashIdentity}` +
    solveContext.cacheKey.slice(insertionOffset);
  serialized.route_cache_digest = routeKeyDigest(attestedCacheKey);
  serialized.history_hashes = historyHashes;
  return serialized;
}

function precomputeManifestSolverContext(host) {
  return {
    solver_version: String(ROUTE_SOLVER_CACHE_VERSION),
    history_revisions: getRailHistoryRevisions(host.country),
    ...(Object.keys(host.historyHashes || {}).length
      ? { history_hashes: { ...host.historyHashes } }
      : {}),
  };
}

async function precomputeTrainStoreParts(host) {
  const store = await preparePrecomputeTrainStore(host);

  const results = [];
  for (let index = 0; index < store.trains.length; index += 1) {
    const raw = store.trains[index];
    const id = appendImportedTrain(raw, null);
    const train = getTrain(id);
    const solveContext = buildTrainRouteSolveContext(train);
    const serializedSolveContext = serializedPrecomputeSolveContext(
      train, solveContext, host);
    const cacheKey = solveContext ? solveContext.cacheKey : null;

    const startedAt = performance.now();
    const features = await RouteService.warmTrain(train);
    const ms = Math.round(performance.now() - startedAt);

    let route = null;
    if (cacheKey) {
      if (RouteService.has(cacheKey)) {
        route = {
          cache_key: cacheKey,
          solver_context: serializedSolveContext,
          features: RouteService.get(cacheKey),
        };
      } else if (RouteService.isNegative(cacheKey)) {
        const matched = (host.matchedRoutes.features || [])
          .filter((feature) => {
            const props = feature.properties || {};
            return props.train_id === id && props.is_primary !== false;
          })
          .sort(
            (a, b) =>
              Number(a.properties?.segment_index ?? 0) -
              Number(b.properties?.segment_index ?? 0),
          );
        if (matched.length) {
          RouteService.seed(cacheKey, matched);
          route = {
            cache_key: cacheKey,
            solver_context: serializedSolveContext,
            features: matched,
          };
        } else {
          route = {
            cache_key: cacheKey,
            solver_context: serializedSolveContext,
            unsolvable: true,
          };
        }
      } else {
        throw new Error(
          `Route solve for train ${id} produced neither a positive nor negative cache entry.`,
        );
      }
      const prepared = prepareTrainRouteSolve(train);
      if (!prepared.done) {
        throw new Error(
          `Seeded cache miss for train ${id} — export would not skip the on-device solve.`,
        );
      }
    }

    host.onTrainSolved({
      index,
      id,
      raw,
      route,
      featureCount:
        route && Array.isArray(route.features)
          ? route.features.length
          : features.length,
      ms,
    });
    results.push({
      id,
      solved: Boolean(route && !route.unsolvable),
      featureCount: features.length,
    });
  }
  return {
    total: store.trains.length,
    schemaVersion: store.schema_version,
    solverContext: precomputeManifestSolverContext(host),
    results,
  };
}

// Rebuild only the solve provenance for a set already solved from the same
// overlay bytes. The generator checks the existing attestation before using
// this; geometry never enters this path.
async function precomputeTrainStoreSolverContexts(host) {
  const store = await preparePrecomputeTrainStore(host);
  const results = store.trains.map((raw) => {
    const id = appendImportedTrain(raw, null);
    const train = getTrain(id);
    const solveContext = buildTrainRouteSolveContext(train);
    return {
      id,
      raw,
      solverContext: serializedPrecomputeSolveContext(train, solveContext, host),
    };
  });
  return {
    total: store.trains.length,
    schemaVersion: store.schema_version,
    solverContext: precomputeManifestSolverContext(host),
    results,
  };
}

window.PrecomputeAdapter = Object.freeze({
  solveStore: precomputeTrainStoreParts,
  solverContexts: precomputeTrainStoreSolverContexts,
});
