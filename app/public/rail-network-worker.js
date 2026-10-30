/* Build compact-v1 display geometry away from the browser's UI event loop. */
"use strict";

importScripts("./rail-history-service.js?v=20261026-service1", "./rail-network.js?v=20261017-owner1");

self.onmessage = async (event) => {
  try {
    const inputs = event.data.inputs || await self.RailNetwork.loadNetworkInputs(event.data);
    const network = await self.RailNetwork.loadNetwork({ inputs, dateContext: event.data.dateContext || null });
    self.postMessage({ ok: true, network, inputs });
  } catch (error) {
    self.postMessage({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
};
