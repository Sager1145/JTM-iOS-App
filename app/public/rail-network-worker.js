/* Build compact-v1 display geometry away from the browser's UI event loop. */
"use strict";

importScripts("./rail-network.js?v=20261017-owner1");

self.onmessage = async (event) => {
  try {
    const network = await self.RailNetwork.loadNetwork(event.data);
    self.postMessage({ ok: true, network });
  } catch (error) {
    self.postMessage({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
};
