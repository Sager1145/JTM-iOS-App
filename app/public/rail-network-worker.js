/* Build compact-v1 display geometry away from the browser's UI event loop. */
"use strict";

importScripts("./rail-network.js?v=20260901-stroke1");

self.onmessage = async (event) => {
  try {
    const { packageUrls, reviewedUrl, lanesUrl } = event.data || {};
    if (!Array.isArray(packageUrls) || !packageUrls.length)
      throw new Error("A rail package URL is required.");

    const responses = await Promise.all(
      packageUrls.map((url) => fetch(url, { cache: "no-cache" })),
    );
    const failed = responses.find((response) => !response.ok);
    if (failed) throw new Error(`rail package request failed: HTTP ${failed.status}`);
    const packages = await Promise.all(responses.map((response) => response.json()));
    const merged = self.RailNetwork.mergeCompactPackages(packages);
    if (!merged) throw new Error("rail packages are not compact-v1");

    let reviewedSharedCorridors = null;
    if (reviewedUrl) {
      try {
        const response = await fetch(reviewedUrl, { cache: "no-cache" });
        if (response.ok) reviewedSharedCorridors = await response.json();
      } catch {
        // The review ledger is optional in the existing loader too. The
        // canonical package still draws when a static deployment omits it.
      }
    }

    let displayLanes = null;
    if (lanesUrl) {
      try {
        const response = await fetch(lanesUrl, { cache: "no-cache" });
        if (response.ok) displayLanes = await response.json();
        else
          console.warn(
            `[rail-network-worker] display lanes unavailable: ${response.status} ${response.statusText} (${lanesUrl})`,
          );
      } catch (e) {
        // Package-local lane rows remain a valid fallback for older deploys.
        console.warn("[rail-network-worker] display lanes unavailable:", lanesUrl, e);
      }
    }

    const network = self.RailNetwork.buildNetworkFromCompactPackage(
      merged,
      reviewedSharedCorridors,
      displayLanes,
    );
    self.postMessage({ ok: true, network });
  } catch (error) {
    self.postMessage({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
};
