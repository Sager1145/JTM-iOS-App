// =========================================================================
//  app-persistence.js — §12–15: train-store persistence — debounced server autosave, File System Access handles, user IndexedDB store, route-geometry cache, local JSON open/save
//
//  Part of the app-*.js family split out of the old single-file app.js:
//  plain classic scripts sharing one global lexical scope, loaded in the
//  order defined by index.html (the module map lives in app.js's header).
// =========================================================================

// =========================================================================
//  §12.  Train store: built-in defaults & debounced server autosave
// =========================================================================

function getDefaultTrainStore() {
  return {
    schema_version: SCHEMA_VERSION,
    trains: (defaultTrainStore.trains || []).map(normalizeExportTrain),
  };
}

// Fallback when the active country has no saved store yet: Japan gets the
// built-in defaults; other countries start empty (the defaults, like every
// bundled sample, are a Japan dataset).
function countryFallbackStore() {
  return activeCountry === "jp"
    ? getDefaultTrainStore()
    : { schema_version: SCHEMA_VERSION, trains: [] };
}
function countryFallbackLabel() {
  return I18N.t(activeCountry === "jp" ? "src.builtinDefault" : "src.emptyStore");
}

// Persist every change to the server-side store (debounced). This is the
// single source of truth that replaces the old localStorage backup.
let serverStoreSaveTimer = null;
let serverStoreSaveInFlight = false;
let pendingServerStoreText = null;
let pendingServerStoreJournalTimer = null;
let pendingServerStoreJournalStageInFlight = false;
let pendingServerStoreJournalQueue = Promise.resolve();
// Exact raw server state this tab last loaded/saved. Pending recovery copies
// carry this base so a later boot can replay only when the server has not been
// changed by another tab/agent in the meantime.
let lastKnownServerStoreText = null;
let lastKnownServerStoreExists = false;
// Re-flush after a FAILED autosave. The retry re-marks the store dirty and
// re-serializes the CURRENT in-memory state (never a stale captured body), so
// a transient network/server hiccup no longer leaves the last edit unsaved
// until the user happens to edit again.
let storeSaveRetryTimer = null;
const STORE_SAVE_RETRY_MS = 5000;
function scheduleStoreSaveRetry() {
  clearTimeout(storeSaveRetryTimer);
  storeSaveRetryTimer = setTimeout(() => {
    storeSaveRetryTimer = null;
    if (storeRecoveryMode) return;
    storeSaveDirty = true;
    flushServerStoreSave();
  }, STORE_SAVE_RETRY_MS);
}
// Marks the in-memory store dirty WITHOUT serializing. The expensive full
// JSON.stringify is deferred until the debounced flush actually runs, so a
// rapid burst of small
// mutations (visible toggles, field edits, ride_segment toggles) no longer
// pays one — let alone two — full serializations on the synchronous path.
let storeSaveDirty = false;
let persistenceStateChanged = null;

function setPersistenceStateChangedListener(listener) {
  persistenceStateChanged = typeof listener === "function" ? listener : null;
}

// --- Read-only recovery mode -----------------------------------------------
// Entered when a SAVED store exists but cannot be loaded (fails validation,
// corrupt JSON, or an unreadable backend). The old behavior fell back to the
// built-in defaults with autosave still armed, so the user's next edit
// silently overwrote their unreadable-but-recoverable data with the defaults.
// In recovery mode autosave is disabled and the raw saved JSON is pinned into
// the export textarea for rescue; only an explicit, successful data action
// (import / open local JSON / restore / reset / clear) leaves the mode.
let storeRecoveryMode = false;
let storeRecoveryRawText = "";

function enterStoreRecoveryMode({ message = "", rawText = null } = {}) {
  storeRecoveryMode = true;
  // Cancel anything the autosave debounce queued before the failure was known.
  clearTimeout(serverStoreSaveTimer);
  clearTimeout(storeSaveRetryTimer);
  clearTimeout(pendingServerStoreJournalTimer);
  pendingServerStoreJournalTimer = null;
  pendingServerStoreText = null;
  storeSaveDirty = false;
  storeRecoveryRawText = typeof rawText === "string" ? rawText : "";
  if (els.json) els.json.value = storeRecoveryRawText;
  if (els.importStatus)
    setStatus(
      els.importStatus,
      I18N.t("status.recoveryEntered", { msg: message }),
      "err",
    );
}

function exitStoreRecoveryMode() {
  storeRecoveryMode = false;
  storeRecoveryRawText = "";
}

function saveTrainStore() {
  // Recovery mode: the saved store failed to load, so what is on screen is a
  // fallback view — persisting it would destroy the recoverable original.
  if (storeRecoveryMode) {
    setStatus(els.jsonStatus, I18N.t("status.recoveryNoSave"), "warn");
    return;
  }
  // Sample data has no memory: while a sample is on screen NOTHING persists,
  // so browsing/editing the sample can never overwrite the user's saved data.
  if (!HAS_BACKEND && isSampleMode()) {
    if (!sampleEditHintShown) {
      sampleEditHintShown = true;
      setStatus(els.jsonStatus, I18N.t("status.sampleNoSave"), "warn");
    }
    return;
  }
  storeSaveDirty = true;
  if (HAS_BACKEND) schedulePendingServerStoreJournal();
  clearTimeout(serverStoreSaveTimer);
  serverStoreSaveTimer = setTimeout(
    () => flushServerStoreSave(),
    SERVER_AUTOSAVE_DEBOUNCE_MS,
  );
}

// Serialize the store at most once per dirty window, lazily, right before a
// network write. Kept separate so force-flush paths can reuse it.
function serializePendingStoreIfDirty() {
  if (!storeSaveDirty) return;
  pendingServerStoreText = perfMeasure("serialize store", () =>
    exportTrainStore(),
  );
  storeSaveDirty = false;
}

// Stage a recovery copy at the start of an edit burst, well before the 450 ms
// network debounce. The visibility-change flush still stages synchronously as
// a final backstop, but most close/navigation events now find an already
// committed IndexedDB copy instead of depending on page-lifetime grace time.
function schedulePendingServerStoreJournal() {
  if (
    pendingServerStoreJournalTimer ||
    pendingServerStoreJournalStageInFlight
  ) {
    return;
  }
  pendingServerStoreJournalTimer = setTimeout(async () => {
    pendingServerStoreJournalTimer = null;
    pendingServerStoreJournalStageInFlight = true;
    try {
      serializePendingStoreIfDirty();
      if (pendingServerStoreText !== null) {
        await queuePendingServerStoreJournalWrite(pendingServerStoreText);
      }
    } catch (error) {
      console.warn(
        "Could not pre-stage the pending server-store recovery copy.",
        error,
      );
    } finally {
      pendingServerStoreJournalStageInFlight = false;
      // Coalesce edits made while the IndexedDB transaction was active into
      // the next staged snapshot.
      if (storeSaveDirty) schedulePendingServerStoreJournal();
    }
  }, 0);
}

function queuePendingServerStoreJournalWrite(body) {
  const run = pendingServerStoreJournalQueue.then(() =>
    writePendingServerStoreSave(body),
  );
  // Keep the queue usable after a failed IndexedDB transaction while still
  // returning the real rejection to this caller.
  pendingServerStoreJournalQueue = run.catch(() => undefined);
  return run;
}

// PUT one serialized store body to the server train-store endpoint, throwing
// on any non-OK status. apiResourceUrl() applies the deployment's configured
// file suffix; this write path is gated off entirely on static deployments.
async function putTrainStore(body, clientId) {
  const res = await fetch(apiResourceUrl(TRAIN_STORE_API), {
    method: "PUT",
    headers: { "Content-Type": "application/json", "X-Client-Id": clientId },
    body,
  });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
}

// Resolves when the current PUT settles — lets the clear-storage handler wait
// out an in-flight save so it can't land AFTER the DELETE and resurrect the
// just-cleared file on the server.
let serverStoreSavePromise = null;

async function flushServerStoreSave() {
  // Static deploy: there is no server to PUT to — user data is persisted to
  // the browser's IndexedDB instead, chunked one record per day.
  if (!HAS_BACKEND) {
    pendingServerStoreText = null;
    return flushUserStoreSave();
  }
  serializePendingStoreIfDirty();
  if (serverStoreSaveInFlight) return serverStoreSavePromise;
  if (pendingServerStoreText === null) return;
  serverStoreSaveInFlight = true;
  const jsonText = pendingServerStoreText;
  pendingServerStoreText = null;
  serverStoreSavePromise = (async () => {
    try {
      // Start an IndexedDB transaction before the network request. If the page
      // is destroyed during a visibility-change flush, the next boot can
      // safely replay this snapshot. Failure to access browser storage is
      // non-fatal: ordinary server autosave still proceeds.
      try {
        await queuePendingServerStoreJournalWrite(jsonText);
      } catch (pendingError) {
        console.warn(
          "Could not write the pending server-store recovery copy.",
          pendingError,
        );
      }
      await putTrainStore(jsonText, CLIENT_ID);
      lastKnownServerStoreText = jsonText;
      lastKnownServerStoreExists = true;
      try {
        await deletePendingServerStoreSave(CLIENT_ID, jsonText);
      } catch (pendingError) {
        // Harmless: boot sees that the pending body already equals the server
        // body and removes the stale recovery record.
        console.warn(
          "Could not clear the pending server-store recovery copy.",
          pendingError,
        );
      }
      clearTimeout(storeSaveRetryTimer);
      storeSaveRetryTimer = null;
      setStatus(els.jsonStatus, I18N.t("status.autosaveOk"), "ok");
    } catch (error) {
      console.warn("Autosave to server train-store failed.", error);
      setStatus(els.jsonStatus, I18N.t("status.autosaveFail", { msg: error.message }), "warn");
      scheduleStoreSaveRetry();
    } finally {
      serverStoreSaveInFlight = false;
      // A newer change may have arrived while this request was in flight
      // (either already serialized, or just flagged dirty). Flush it — and
      // AWAIT it, so `await flushServerStoreSave()` only settles once the
      // store is fully drained. A country switch relies on this: its
      // follow-up write must land in the OLD country's store, not fire
      // detached and resolve TRAIN_STORE_API / countryDbName after the
      // switch has re-pointed them at the new country.
      if (pendingServerStoreText !== null || storeSaveDirty)
        await flushServerStoreSave();
    }
  })();
  return serverStoreSavePromise;
}

// Static-deploy counterpart of the server PUT: write the canonical store to
// IndexedDB (per-day chunks, diffed). Shares storeSaveDirty with the debounce
// machinery so force-flush callers behave identically on both deployments.
let userStoreSaveInFlight = false;
let userStoreSavePromise = null;
class UserStoreConflictError extends Error {
  constructor(dateKey) {
    super(`Saved data for ${dateKey || UNDATED} changed in another tab.`);
    this.name = "UserStoreConflictError";
    this.dateKey = dateKey || UNDATED;
  }
}
function userStoreChunkConflicts(baselineText, currentRecord) {
  const currentText =
    currentRecord === undefined ? undefined : JSON.stringify(currentRecord);
  return currentText !== baselineText;
}
async function flushUserStoreSave() {
  if (isSampleMode()) {
    storeSaveDirty = false;
    return;
  }
  if (userStoreSaveInFlight) return userStoreSavePromise;
  if (!storeSaveDirty) return;
  storeSaveDirty = false;
  userStoreSaveInFlight = true;
  userStoreSavePromise = (async () => {
    try {
      const canonical = perfMeasure("serialize store", () =>
        buildCanonicalTrainStore(),
      );
      await writeUserStoreChunks(canonical);
      userStoreAvailable = canonical.trains.length > 0;
      clearTimeout(storeSaveRetryTimer);
      storeSaveRetryTimer = null;
      setStatus(els.jsonStatus, I18N.t("status.autosaveLocalOk"), "ok");
      if (persistenceStateChanged) persistenceStateChanged();
    } catch (error) {
      console.warn("Autosave to browser storage (IndexedDB) failed.", error);
      if (error instanceof UserStoreConflictError) {
        // Do not retry a stale snapshot: it would conflict forever and, before
        // the compare-before-write guard, silently replaced the other tab's
        // newer record. Keep this tab's state in memory for export/rescue.
        setStatus(
          els.jsonStatus,
          I18N.t("status.autosaveConflict", { date: error.dateKey }),
          "err",
        );
        return;
      }
      setStatus(
        els.jsonStatus,
        I18N.t("status.autosaveFail", { msg: error.message }),
        "warn",
      );
      scheduleStoreSaveRetry();
    } finally {
      userStoreSaveInFlight = false;
      // A newer change may have arrived while this write was in flight.
      // Awaited for the same reason as the server flush above: callers that
      // await the flush (country switch, clear-storage) must observe a fully
      // drained store, not a detached follow-up write that resolves the
      // country-scoped DB name after a switch.
      if (storeSaveDirty) await flushUserStoreSave();
    }
  })();
  return userStoreSavePromise;
}

// A country switch swaps every persistence target (server endpoint + the
// country-scoped IndexedDB databases). Every diff baseline and pending write
// captured against the OLD country must be dropped, or the first save in the
// new country diffs against the wrong store (skipped per-day chunks = data
// loss). Callers flush pending saves BEFORE calling this.
function resetPersistenceStateForCountrySwitch() {
  clearTimeout(serverStoreSaveTimer);
  clearTimeout(storeSaveRetryTimer);
  storeSaveRetryTimer = null;
  clearTimeout(pendingServerStoreJournalTimer);
  pendingServerStoreJournalTimer = null;
  pendingServerStoreText = null;
  storeSaveDirty = false;
  userStoreWrittenChunks = new Map();
  lastKnownServerStoreText = null;
  lastKnownServerStoreExists = false;
  // The remembered local-JSON file handle belongs to the old country's
  // export; the handle DB is country-scoped, so drop the in-memory copy.
  localJsonFileHandle = null;
  // The rail-content hash memo was computed from the OLD country's datasets.
  // Left stale, the next warm/persist under the new country would run in the
  // old country's namespace: the warm would load the old country's geometry
  // into this session's runtime cache (same-named station pairs — 松山→板橋
  // exist in both countries — would then serve wrong-country routes), and
  // fresh solves would persist under a namespace the old country later
  // evicts. Recompute it from the datasets ensureSolverReady loads next.
  railContentHashCache = null;
}

// Clear every persistence surface as one serialized operation. Event
// controllers must not manipulate timers, journals, in-flight writes, or
// backend existence flags directly; those are private to this service.
async function clearStoredData() {
  clearTimeout(serverStoreSaveTimer);
  clearTimeout(storeSaveRetryTimer);
  clearTimeout(pendingServerStoreJournalTimer);
  pendingServerStoreJournalTimer = null;
  storeSaveRetryTimer = null;
  pendingServerStoreText = null;
  storeSaveDirty = false;

  // A write already in flight could otherwise land after the delete and
  // recreate the store the user just cleared.
  if (serverStoreSaveInFlight) await serverStoreSavePromise;
  if (userStoreSaveInFlight) await userStoreSavePromise;
  await pendingServerStoreJournalQueue;
  pendingServerStoreText = null;
  storeSaveDirty = false;

  if (HAS_BACKEND) {
    const res = await fetch(apiResourceUrl(TRAIN_STORE_API), {
      method: "DELETE",
      headers: { "X-Client-Id": CLIENT_ID },
    });
    if (!res.ok && res.status !== 404) {
      throw new Error(`${res.status} ${res.statusText}`);
    }
    lastKnownServerStoreText = null;
    lastKnownServerStoreExists = false;
    try {
      await clearPendingServerStoreSaves();
    } catch (pendingError) {
      // The canonical server store is already gone. Failure to remove a local
      // recovery copy must not turn that successful clear into a failure.
      console.warn(
        "Could not clear pending server-store recovery copies.",
        pendingError,
      );
    }
  } else {
    await clearUserStore();
  }

  await deleteStoredFileHandle();
  exitStoreRecoveryMode();
}

async function flushPersistence() {
  await flushServerStoreSave();
  // Journal writes are queued separately from the network debounce. A country
  // switch must wait for both before changing the country-scoped DB name.
  await pendingServerStoreJournalQueue;
}

/**
 * @typedef {Object} PersistenceServiceContract
 * @property {Function} load
 * @property {Function} scheduleSave
 * @property {Function} flush
 * @property {Function} clear
 * @property {Function} enterRecoveryMode
 * @property {Function} exitRecoveryMode
 * @property {Function} resetForCountry
 * @property {Function} readUserStore
 * @property {Function} writeUserStore
 * @property {Function} pickLocalJson
 * @property {Function} defaultStore
 * @property {Function} fallbackStore
 * @property {Function} fallbackLabel
 * @property {Function} markClean
 * @property {boolean} recoveryMode
 */

/** @type {Readonly<PersistenceServiceContract>} */
const PersistenceService = Object.freeze({
  load: loadTrainStoreFromServer,
  scheduleSave: saveTrainStore,
  flush: flushPersistence,
  clear: clearStoredData,
  enterRecoveryMode: enterStoreRecoveryMode,
  exitRecoveryMode: exitStoreRecoveryMode,
  resetForCountry: resetPersistenceStateForCountrySwitch,
  readUserStore: readUserStoreAll,
  writeUserStore: writeUserStoreChunks,
  pickLocalJson: pickLocalJsonFile,
  defaultStore: getDefaultTrainStore,
  fallbackStore: countryFallbackStore,
  fallbackLabel: countryFallbackLabel,
  markClean() {
    storeSaveDirty = false;
  },
  get recoveryMode() {
    return storeRecoveryMode;
  },
});

// The read-only preview is materialized only when the user opens, focuses,
// copies or explicitly exports it. Recovery owns the textarea's original raw
// bytes; export actions must never replace those bytes with the fallback view.
function exportJsonText() {
  if (storeRecoveryMode) return storeRecoveryRawText;
  return perfMeasure("export JSON", () => exportTrainStore());
}

function refreshExportTextarea() {
  const text = exportJsonText();
  if (els.json) els.json.value = text;
  return text;
}

// Load the saved store from the server. Returns:
//   - the parsed, validated store;
//   - null when nothing has been saved yet (HTTP 404) — defaults are safe;
//   - { recovery: true, rawText, message } when a store EXISTS but cannot be
//     loaded (network/HTTP failure, corrupt JSON, or validation failure).
// Callers must treat the recovery sentinel as read-only: falling back to
// writable defaults here is what used to let the next autosave overwrite the
// user's recoverable data.
async function loadTrainStoreFromServer() {
  let res;
  try {
    res = await fetch(apiResourceUrl(TRAIN_STORE_API), {
      cache: "no-store",
    });
  } catch (error) {
    // Network failure: we cannot know whether a saved store exists, so do NOT
    // hand back writable defaults.
    console.warn("Could not reach the server train-store endpoint.", error);
    return { recovery: true, rawText: null, message: error.message };
  }
  if (res.status === 404) {
    lastKnownServerStoreText = null;
    lastKnownServerStoreExists = false;
    return null;
  }
  if (!res.ok) {
    console.warn(`Server train-store read failed: ${res.status}.`);
    return {
      recovery: true,
      rawText: null,
      message: `${res.status} ${res.statusText}`,
    };
  }
  let text = "";
  try {
    text = await res.text();
    lastKnownServerStoreText = text;
    lastKnownServerStoreExists = true;
    const parsed = JSON.parse(text);
    validateTrainStore(parsed);
    return parsed;
  } catch (error) {
    console.warn(
      "Saved train store failed to parse/validate; entering read-only recovery mode instead of overwritable defaults.",
      error,
    );
    return { recovery: true, rawText: text, message: error.message };
  }
}

// Open (creating on first use) one of this app's version-1 IndexedDB
// databases, ensuring every named object store exists. All four app databases
// share this wrapper; only the transaction patterns beyond open differ.
// `fallbackErrorMessage` keeps each caller's historical open-failure message.
function openIdb(name, storeNames, fallbackErrorMessage) {
  return new Promise((resolve, reject) => {
    if (!window.indexedDB) {
      reject(new Error("IndexedDB is unavailable."));
      return;
    }
    const request = indexedDB.open(name, 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      for (const storeName of storeNames) {
        if (!db.objectStoreNames.contains(storeName))
          db.createObjectStore(storeName);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () =>
      reject(request.error || new Error(fallbackErrorMessage));
  });
}

// -------------------------------------------------------------------------
// Backend autosave recovery journal (IndexedDB)
// -------------------------------------------------------------------------

function openPendingServerStoreDb() {
  return openIdb(
    countryDbName(PENDING_SERVER_STORE_DB_NAME),
    [PENDING_SERVER_STORE_NAME],
    "Could not open the pending server-store database.",
  );
}

async function writePendingServerStoreSave(body) {
  const db = await openPendingServerStoreDb();
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction(PENDING_SERVER_STORE_NAME, "readwrite");
      tx.objectStore(PENDING_SERVER_STORE_NAME).put(
        {
          client_id: CLIENT_ID,
          body,
          base_body: lastKnownServerStoreText,
          base_exists: lastKnownServerStoreExists,
          updated_at: new Date().toISOString(),
        },
        CLIENT_ID,
      );
      tx.oncomplete = () => resolve();
      tx.onerror = () =>
        reject(
          tx.error ||
            new Error("Could not save the pending server-store recovery copy."),
        );
    });
  } finally {
    db.close();
  }
}

async function readPendingServerStoreSaves() {
  if (!window.indexedDB) return [];
  const db = await openPendingServerStoreDb();
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(PENDING_SERVER_STORE_NAME, "readonly");
      const records = [];
      const request = tx.objectStore(PENDING_SERVER_STORE_NAME).openCursor();
      request.onsuccess = () => {
        const cursor = request.result;
        if (!cursor) return;
        if (cursor.value && typeof cursor.value.body === "string")
          records.push({ ...cursor.value, _key: String(cursor.key) });
        cursor.continue();
      };
      tx.oncomplete = () => resolve(records);
      tx.onerror = () =>
        reject(
          tx.error ||
            new Error("Could not read pending server-store recovery copies."),
        );
    });
  } finally {
    db.close();
  }
}

async function deletePendingServerStoreSave(clientId, expectedBody = null) {
  if (!window.indexedDB) return;
  const db = await openPendingServerStoreDb();
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction(PENDING_SERVER_STORE_NAME, "readwrite");
      const store = tx.objectStore(PENDING_SERVER_STORE_NAME);
      const request = store.get(clientId);
      request.onsuccess = () => {
        const record = request.result;
        if (
          record &&
          (expectedBody === null || record.body === expectedBody)
        ) {
          store.delete(clientId);
        }
      };
      tx.oncomplete = () => resolve();
      tx.onerror = () =>
        reject(
          tx.error ||
            new Error("Could not clear a pending server-store recovery copy."),
        );
    });
  } finally {
    db.close();
  }
}

async function clearPendingServerStoreSaves() {
  if (!window.indexedDB) return;
  const db = await openPendingServerStoreDb();
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction(PENDING_SERVER_STORE_NAME, "readwrite");
      tx.objectStore(PENDING_SERVER_STORE_NAME).clear();
      tx.oncomplete = () => resolve();
      tx.onerror = () =>
        reject(
          tx.error ||
            new Error("Could not clear pending server-store recovery copies."),
        );
    });
  } finally {
    db.close();
  }
}

// Replay journal entries only when their exact base still matches the server.
// A mismatch means another source changed the store after this tab's edit; keep
// both copies and enter recovery instead of silently overwriting either one.
async function recoverPendingServerStoreSaves(savedStore) {
  let records;
  try {
    records = await readPendingServerStoreSaves();
  } catch (error) {
    console.warn("Could not inspect pending server-store recovery copies.", error);
    return savedStore;
  }
  records.sort((a, b) =>
    String(a.updated_at || "").localeCompare(String(b.updated_at || "")),
  );
  let currentStore = savedStore;
  for (const record of records) {
    let pendingStore;
    try {
      pendingStore = JSON.parse(record.body);
      validateTrainStore(pendingStore);
    } catch (error) {
      return {
        recovery: true,
        rawText: record.body,
        message: I18N.t("err.pendingServerInvalid", { msg: error.message }),
      };
    }

    if (
      lastKnownServerStoreExists &&
      record.body === lastKnownServerStoreText
    ) {
      await deletePendingServerStoreSave(
        record.client_id || record._key || CLIENT_ID,
        record.body,
      );
      currentStore = pendingStore;
      continue;
    }

    const baseMatches =
      Boolean(record.base_exists) === lastKnownServerStoreExists &&
      (!lastKnownServerStoreExists ||
        record.base_body === lastKnownServerStoreText);
    if (!baseMatches) {
      return {
        recovery: true,
        rawText: record.body,
        pendingStore,
        message: I18N.t("err.pendingServerConflict"),
      };
    }

    try {
      await putTrainStore(record.body, record.client_id || CLIENT_ID);
    } catch (error) {
      return {
        recovery: true,
        rawText: record.body,
        pendingStore,
        message: I18N.t("err.pendingServerReplayFailed", {
          msg: error.message,
        }),
      };
    }
    lastKnownServerStoreText = record.body;
    lastKnownServerStoreExists = true;
    currentStore = pendingStore;
    await deletePendingServerStoreSave(
      record.client_id || record._key || CLIENT_ID,
      record.body,
    );
  }
  return currentStore;
}

let localJsonFileHandle = null;

// =========================================================================
//  §13.  File System Access API & IndexedDB key/value (file-handle) store
// =========================================================================

function supportsFileSystemAccess() {
  return (
    typeof window.showOpenFilePicker === "function" &&
    typeof window.showSaveFilePicker === "function"
  );
}

function openFileHandleDb() {
  return openIdb(
    countryDbName(FILE_HANDLE_DB_NAME),
    [FILE_HANDLE_STORE_NAME],
    "Could not open IndexedDB.",
  );
}

async function idbDeleteValue(key) {
  const db = await openFileHandleDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(FILE_HANDLE_STORE_NAME, "readwrite");
    tx.objectStore(FILE_HANDLE_STORE_NAME).delete(key);
    tx.oncomplete = () => {
      db.close();
      resolve();
    };
    tx.onerror = () => {
      db.close();
      reject(tx.error || new Error("Could not delete IndexedDB value."));
    };
  });
}

// =========================================================================
//  §13b. User train store (IndexedDB, chunked one record per calendar day)
// =========================================================================
// The static (GitHub Pages) deploy has no backend, so the user's own data is
// persisted right here in the browser. Layout:
//   object store "dates": key = date string ("" for undated trains), value =
//     { date, trains: [<canonical train>...] }
//   object store "meta": key "meta", value =
//     { schema_version, updated_at, dates: [<date keys in store order>] }
// Derived geometry belongs only to the rail-hash/solver-version route cache.
// Legacy chunks may still contain routes; train recovery and the write-diff
// baseline remain readable, and the next changed/forced write drops that copy.

function openUserStoreDb() {
  return openIdb(
    countryDbName(USER_STORE_DB_NAME),
    [USER_STORE_DATES_STORE, USER_STORE_META_STORE],
    "Could not open the user store DB.",
  );
}

// Serialized per-day chunk texts from the last successful write, so the next
// write only touches days whose content actually changed.
let userStoreWrittenChunks = new Map();

// Group canonical records by day, preserving store order. Route geometry never
// changes a user-record chunk or participates in its cross-tab conflict check.
function buildUserStoreChunks(canonicalStore) {
  const chunks = new Map();
  for (const train of canonicalStore.trains) {
    const dateKey = typeof train.date === "string" ? train.date : "";
    if (!chunks.has(dateKey)) chunks.set(dateKey, { date: dateKey, trains: [] });
    chunks.get(dateKey).trains.push(train);
  }
  return chunks;
}

// Write the canonical store to IndexedDB, one record per day, diffed against
// the previous write. `force` bypasses the diff (used by "save as my data").
async function writeUserStoreChunks(canonicalStore, { force = false } = {}) {
  // Belt-and-braces: in recovery mode the on-screen store is a fallback view,
  // and the per-day diff would DELETE days missing from it. Only an explicit,
  // confirmed force-save (保存為我的資料) may write.
  if (storeRecoveryMode && !force) return;
  // Sample parts seed runtime geometry without writing it. Preserve that warm
  // restore when the user explicitly saves the sample as their own records.
  const routesSaved = force ? persistUserStoreRoutes(canonicalStore).catch((error) => {
    console.warn("Saved records will restore without cached geometry.", error);
  }) : null;
  const chunks = buildUserStoreChunks(canonicalStore);
  const serialized = new Map();
  for (const [dateKey, record] of chunks)
    serialized.set(dateKey, JSON.stringify(record));

  const toPut = [];
  for (const [dateKey, text] of serialized) {
    if (force || userStoreWrittenChunks.get(dateKey) !== text)
      toPut.push([dateKey, chunks.get(dateKey)]);
  }
  const toDelete = [];
  for (const dateKey of userStoreWrittenChunks.keys()) {
    if (!serialized.has(dateKey)) toDelete.push(dateKey);
  }
  // When the diff baseline is empty (fresh boot in sample mode, or a forced
  // save), stale days from an older session may still exist in the DB. A
  // forced write clears the store first so the result is exactly `chunks`.
  const meta = {
    schema_version: canonicalStore.schema_version || SCHEMA_VERSION,
    updated_at: new Date().toISOString(),
    dates: [...serialized.keys()],
  };

  const db = await openUserStoreDb();
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction(
        [USER_STORE_DATES_STORE, USER_STORE_META_STORE],
        "readwrite",
      );
      const dateStore = tx.objectStore(USER_STORE_DATES_STORE);
      let conflictError = null;
      let settled = false;
      const finishReject = (error) => {
        if (settled) return;
        settled = true;
        reject(error);
      };
      const run = () => {
        for (const dateKey of toDelete) dateStore.delete(dateKey);
        for (const [dateKey, record] of toPut) dateStore.put(record, dateKey);
        // Rebuild meta.dates from the transaction's resulting keys. Another
        // tab may have added a different day since this tab loaded; retaining
        // those keys prevents the later meta write from hiding its ordering.
        const keysReq = dateStore.getAllKeys();
        keysReq.onsuccess = () => {
          const actualKeys = keysReq.result.map(String);
          const actualSet = new Set(actualKeys);
          const orderedKeys = [...serialized.keys()].filter((key) =>
            actualSet.has(key),
          );
          for (const key of actualKeys.sort()) {
            if (!orderedKeys.includes(key)) orderedKeys.push(key);
          }
          if (orderedKeys.length) {
            tx.objectStore(USER_STORE_META_STORE).put(
              { ...meta, dates: orderedKeys },
              USER_STORE_META_KEY,
            );
          } else {
            tx.objectStore(USER_STORE_META_STORE).delete(USER_STORE_META_KEY);
          }
        };
      };
      if (force) {
        const clearReq = dateStore.clear();
        clearReq.onsuccess = run;
      } else {
        // IndexedDB serializes readwrite transactions with overlapping object
        // stores. Compare every day this tab is about to touch against the
        // snapshot it originally loaded INSIDE that same transaction; a later
        // tab therefore sees the earlier commit and aborts instead of silently
        // replacing it with stale whole-day state.
        const touchedKeys = [
          ...new Set([
            ...toDelete,
            ...toPut.map(([dateKey]) => dateKey),
          ]),
        ];
        if (!touchedKeys.length) {
          run();
        } else {
          let remaining = touchedKeys.length;
          for (const dateKey of touchedKeys) {
            const getReq = dateStore.get(dateKey);
            getReq.onsuccess = () => {
              if (conflictError) return;
              const baselineText = userStoreWrittenChunks.get(dateKey);
              if (userStoreChunkConflicts(baselineText, getReq.result)) {
                conflictError = new UserStoreConflictError(dateKey);
                tx.abort();
                return;
              }
              remaining -= 1;
              if (remaining === 0) run();
            };
          }
        }
      }
      tx.oncomplete = () => {
        if (settled) return;
        settled = true;
        resolve();
      };
      tx.onerror = () =>
        finishReject(
          conflictError ||
            tx.error ||
            new Error("Could not write the user store."),
        );
      tx.onabort = () =>
        finishReject(
          conflictError ||
            tx.error ||
            new Error("User store write was aborted."),
        );
    });
  } finally {
    db.close();
  }
  userStoreWrittenChunks = serialized;
  if (routesSaved) await routesSaved;
}

// Read the whole user store back. Returns null when nothing is saved (or the
// saved data is unreadable), so callers can fall back to the sample.
// Older records with a `routes` field still restore their canonical trains.
async function readUserStoreAll() {
  let db;
  try {
    db = await openUserStoreDb();
  } catch (err) {
    console.warn("User store unavailable (IndexedDB).", err);
    return null;
  }
  try {
    const { meta, records } = await new Promise((resolve, reject) => {
      const tx = db.transaction(
        [USER_STORE_DATES_STORE, USER_STORE_META_STORE],
        "readonly",
      );
      const metaReq = tx
        .objectStore(USER_STORE_META_STORE)
        .get(USER_STORE_META_KEY);
      const recordsByKey = new Map();
      const cursorReq = tx.objectStore(USER_STORE_DATES_STORE).openCursor();
      cursorReq.onsuccess = () => {
        const cursor = cursorReq.result;
        if (cursor) {
          recordsByKey.set(String(cursor.key), cursor.value);
          cursor.continue();
        }
      };
      tx.oncomplete = () =>
        resolve({ meta: metaReq.result || null, records: recordsByKey });
      tx.onerror = () =>
        reject(tx.error || new Error("Could not read the user store."));
    });
    if (!records.size) return null;
    // Reassemble in the order the days were written (meta), falling back to
    // ascending date order for any record the meta list doesn't know about.
    const orderedKeys = [];
    const seen = new Set();
    for (const key of (meta && meta.dates) || []) {
      if (records.has(key) && !seen.has(key)) {
        orderedKeys.push(key);
        seen.add(key);
      }
    }
    for (const key of [...records.keys()].sort()) {
      if (!seen.has(key)) orderedKeys.push(key);
    }
    const trains = [];
    const chunkTexts = new Map();
    for (const key of orderedKeys) {
      const record = records.get(key);
      if (!record || !Array.isArray(record.trains)) continue;
      trains.push(...record.trains);
      chunkTexts.set(key, JSON.stringify(record));
    }
    if (!trains.length) return null;
    // Seed the write-diff baseline so the first autosave after a restore only
    // rewrites days that actually changed.
    userStoreWrittenChunks = chunkTexts;
    return {
      store: {
        schema_version:
          (meta && meta.schema_version) || SCHEMA_VERSION,
        trains,
      },
    };
  } catch (err) {
    console.warn("Could not read the user store from IndexedDB.", err);
    return null;
  } finally {
    db.close();
  }
}

async function clearUserStore() {
  const db = await openUserStoreDb();
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction(
        [USER_STORE_DATES_STORE, USER_STORE_META_STORE],
        "readwrite",
      );
      tx.objectStore(USER_STORE_DATES_STORE).clear();
      tx.objectStore(USER_STORE_META_STORE).clear();
      tx.oncomplete = () => resolve();
      tx.onerror = () =>
        reject(tx.error || new Error("Could not clear the user store."));
    });
  } finally {
    db.close();
  }
  userStoreWrittenChunks = new Map();
  userStoreAvailable = false;
}

// =========================================================================
//  §14.  Persistent route-geometry cache (IndexedDB, namespaced by rail-content hash)
// =========================================================================

// --- Persistent route-geometry cache (IndexedDB) -------------------------
// Solved route geometry is expensive (route-graph build + Dijkstra). Persisting
// it keyed by railHash::cacheKey means that across sessions — and for ANY
// dataset — a train whose sections/policy already solved once is restored
// instantly, and the heavy route graph is never even built when every train hits
// the warmed cache (getRuntimeRouteGraph runs only on a miss). railHash
// namespaces entries to the current rail network, so changing the underlying N02
// data transparently invalidates stale geometry.
//
// Positive and negative entries share one object store, so a persisted "this
// route cannot be solved" verdict is stored under this extra key prefix. It is
// purely a detail of that layout — only the writer below and the warm pass
// that has to tell the two apart ever touch it.
const ROUTE_NEG_CACHE_MARKER = "__neg__::";
let railContentHashCache = null;
function getRailContentHash() {
  if (railContentHashCache) return railContentHashCache;
  // Guard against namespacing the persistent route cache by a hash of ZERO
  // features: every caller runs after ensureSolverReady(), but if one ever
  // slips in early, failing loud beats silently caching under a bogus key.
  if (!railSectionsGeoJson)
    throw new Error(
      "rail-sections not loaded yet; await ensureSolverReady() before touching the route cache.",
    );
  const feats = (railSectionsGeoJson && railSectionsGeoJson.features) || [];
  // Hash the graph's effective inputs rather than the full JSON text.
  let h = 0x811c9dc5;
  const mix = (n) => {
    h ^= n | 0;
    h = Math.imul(h, 0x01000193) >>> 0;
  };
  mix(feats.length);
  // Reviewed junction identities, geometry and validity affect solvability
  // even when the original surveyed section vertices have not changed.
  const junctionIdentity = JSON.stringify(physicalRailJunctions);
  for (let i = 0; i < junctionIdentity.length; i++) mix(junctionIdentity.charCodeAt(i));
  // Full content hash (~tens of ms over ~405k points, one-time at boot): every
  // coordinate is mixed in — not a sample — so ANY change to the rail geometry
  // changes the namespace and invalidates stale cached routes. Avoids the blind
  // spots a sparse sample would leave between sampled features.
  for (let i = 0; i < feats.length; i += 1) {
    const properties = feats[i]?.properties || {};
    const graphInputs = JSON.stringify([
      physicalRailIdentityKey(properties),
      String(properties.N02_002 || properties.institution_type_code || ""),
      railServiceBounds(properties),
    ]);
    for (let j = 0; j < graphInputs.length; j++) mix(graphInputs.charCodeAt(j));
    const geom = feats[i] && feats[i].geometry;
    const coords = geom && geom.coordinates;
    if (!Array.isArray(coords)) {
      mix(0);
      continue;
    }
    const lines = geom.type === "MultiLineString" ? coords : [coords];
    for (let li = 0; li < lines.length; li += 1) {
      const line = lines[li];
      if (!Array.isArray(line)) continue;
      mix(line.length);
      for (let pi = 0; pi < line.length; pi += 1) {
        const pt = line[pi];
        if (Array.isArray(pt)) {
          mix(pt[0] * 1e5);
          mix(pt[1] * 1e5);
        }
      }
    }
  }
  // Station data participates in every solve (snap candidates, endpoint
  // resolution, negative verdicts), so a corrected stations.json must
  // invalidate cached geometry exactly like changed rail geometry does —
  // without this, a persisted "unsolvable" marker outlived station fixes.
  const stationFeats = (stationsGeoJson && stationsGeoJson.features) || [];
  mix(stationFeats.length);
  for (let i = 0; i < stationFeats.length; i += 1) {
    const station = stationFeats[i];
    // Use the resolver's dual-schema accessors: changing membership, candidate
    // names, institution or service windows can change a solve without moving
    // the station or changing its code. Display-only metadata is irrelevant.
    const stationInputs = JSON.stringify([
      stationCode(station) || "",
      stationName(station) || "",
      stationGroupCode(station) || "",
      stationLineName(station),
      stationOperator(station),
      stationInstitutionTypeCode(station),
      railServiceBounds(station.properties),
    ]);
    for (let j = 0; j < stationInputs.length; j++) mix(stationInputs.charCodeAt(j));
    const coord = getFeatureDisplayCoordinate(station);
    if (Array.isArray(coord)) {
      mix(coord[0] * 1e5);
      mix(coord[1] * 1e5);
    }
  }
  railContentHashCache = `r${(h >>> 0).toString(36)}-${feats.length}`;
  return railContentHashCache;
}

function openRouteCacheDb() {
  // Country-scoped like every other persistent store (countryDbName): each
  // country's solver cache lives in its own DB, so the warm pass below can
  // only ever evict ITS OWN country's superseded namespaces. A JP↔TW switch
  // therefore leaves the other country's persisted geometry intact for the
  // bulk re-warm that CountrySession's contract promises. (Japan keeps
  // the historical unsuffixed DB name, so existing users lose nothing.)
  return openIdb(
    countryDbName(ROUTE_CACHE_DB_NAME),
    [ROUTE_CACHE_STORE_NAME],
    "Could not open route cache DB.",
  );
}

// Bulk-load all persisted route geometry for the current rail network into the
// in-memory runtimeRouteCache, so the synchronous solve path hits memory and
// never triggers the route-graph build. Best-effort: any failure just falls
// back to solving on demand.
async function warmRouteCacheFromIndexedDb({ isCurrent = () => true } = {}) {
  if (!window.indexedDB) return;
  const prefix = `${getRailContentHash()}::`;
  const solverPrefix = `solver:${ROUTE_SOLVER_CACHE_VERSION}|`;
  try {
    const db = await openRouteCacheDb();
    // openRouteCacheDb captures the country in its DB name before awaiting
    // IndexedDB. If that country was replaced while the open was pending,
    // close its handle without exposing any of its entries to runtime memory.
    if (!isCurrent()) {
      db.close();
      return;
    }
    await new Promise((resolve) => {
      // readwrite: the same cursor pass evicts entries from superseded
      // namespaces (old rail hash or old solver version). Nothing can ever
      // read them again, so without this every data/solver update stranded
      // the previous namespace in IndexedDB forever — unbounded growth on
      // the storage-tight iPhone target.
      const tx = db.transaction(ROUTE_CACHE_STORE_NAME, "readwrite");
      const req = tx.objectStore(ROUTE_CACHE_STORE_NAME).openCursor();
      let warmed = 0;
      let evicted = 0;
      req.onsuccess = () => {
        const cursor = req.result;
        if (!cursor) return;
        // Cursor callbacks are separate tasks. A country reset can clear the
        // in-memory cache between two callbacks, so every row must re-check
        // ownership before it seeds or evicts anything in the captured DB.
        if (!isCurrent()) {
          cursor.continue();
          return;
        }
        const key = String(cursor.key);
        if (key.startsWith(prefix)) {
          const rest = key.slice(prefix.length);
          const isNegative = rest.startsWith(ROUTE_NEG_CACHE_MARKER);
          const cacheKey = isNegative
            ? rest.slice(ROUTE_NEG_CACHE_MARKER.length)
            : rest;
          if (!cacheKey.startsWith(solverPrefix)) {
            // Same rail data, older solver semantics: unreachable, evict.
            cursor.delete();
            evicted += 1;
          } else if (isNegative) {
            // Persisted "this route can't be solved" marker for this rail net.
            RouteService.seedNegative(cacheKey);
          } else if (Array.isArray(cursor.value) && cursor.value.length) {
            RouteService.seed(rest, cursor.value);
            warmed += 1;
          }
        } else {
          // Entry from a superseded rail-data namespace of THIS country (the
          // DB is country-scoped, so no other country's entries are ever
          // visible here): unreachable, evict.
          cursor.delete();
          evicted += 1;
        }
        cursor.continue();
      };
      tx.oncomplete = () => {
        db.close();
        if (warmed) console.info(`Warmed ${warmed} route(s) from IndexedDB.`);
        if (evicted)
          console.info(`Evicted ${evicted} stale cached route entr(ies).`);
        resolve();
      };
      tx.onerror = () => {
        db.close();
        resolve();
      };
    });
  } catch (err) {
    console.warn("Route cache warm-up skipped.", err);
  }
}

// One writer for derived geometry, including sample geometry kept as user
// data. All entries use the current rail-content namespace; the warm owner
// above still evicts obsolete rail hashes and solver versions.
async function persistRouteCacheEntries(entries) {
  if (!window.indexedDB || !entries.length) return;
  try {
    const prefix = `${getRailContentHash()}::`;
    const db = await openRouteCacheDb();
    try {
      await new Promise((resolve, reject) => {
        const tx = db.transaction(ROUTE_CACHE_STORE_NAME, "readwrite");
        const store = tx.objectStore(ROUTE_CACHE_STORE_NAME);
        for (const entry of entries) {
          if (entry.unsolvable === true) {
            store.delete(`${prefix}${entry.cache_key}`);
            store.put(1, `${prefix}${ROUTE_NEG_CACHE_MARKER}${entry.cache_key}`);
          } else {
            store.delete(`${prefix}${ROUTE_NEG_CACHE_MARKER}${entry.cache_key}`);
            store.put(entry.features, `${prefix}${entry.cache_key}`);
          }
        }
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error || new Error("Could not persist route cache."));
        tx.onabort = () => reject(tx.error || new Error("Route cache write was aborted."));
      });
    } finally {
      db.close();
    }
  } catch (error) {
    // Cache storage is optional; canonical journey persistence proceeds.
    console.warn("Route cache persist skipped.", error);
  }
}

function persistRouteCacheEntry(cacheKey, features) {
  if (!Array.isArray(features) || !features.length) return;
  return persistRouteCacheEntries([{ cache_key: cacheKey, features }]);
}

function persistRouteNegativeEntry(cacheKey) {
  return persistRouteCacheEntries([{ cache_key: cacheKey, unsolvable: true }]);
}

async function persistUserStoreRoutes(canonicalStore) {
  const liveById = new Map(trainStore.trains.map((train) => [train.id, train]));
  const entries = new Map();
  for (const train of canonicalStore.trains) {
    const context = buildTrainRouteSolveContext(liveById.get(train.id) || train);
    if (!context?.cacheKey) continue;
    if (RouteService.has(context.cacheKey)) {
      const features = RouteService.get(context.cacheKey);
      if (Array.isArray(features) && features.length)
        entries.set(context.cacheKey, { cache_key: context.cacheKey, features });
    } else if (RouteService.isNegative(context.cacheKey)) {
      entries.set(context.cacheKey, { cache_key: context.cacheKey, unsolvable: true });
    }
  }
  await persistRouteCacheEntries([...entries.values()]);
}

// =========================================================================
//  §15.  Local JSON file open / save (File System Access, with download fallback)
// =========================================================================

// (storeFileHandle was removed: the handle was persisted to IndexedDB but
// never read back — a write-only path. The user re-picks the file each
// session either way; deleteStoredFileHandle stays to clean up old entries.)

async function deleteStoredFileHandle() {
  try {
    await idbDeleteValue(FILE_HANDLE_KEY);
  } catch (error) {
    console.warn("Could not clear stored file handle.", error);
  }
  localJsonFileHandle = null;
}

async function verifyFileHandlePermission(handle, writable) {
  if (!handle || typeof handle.queryPermission !== "function") return false;
  const options = writable ? { mode: "readwrite" } : { mode: "read" };
  if ((await handle.queryPermission(options)) === "granted") return true;
  if (typeof handle.requestPermission === "function") {
    return (await handle.requestPermission(options)) === "granted";
  }
  return false;
}

async function writeLocalJsonFile(
  jsonText = exportJsonText(),
  promptIfMissing = true,
) {
  if (!supportsFileSystemAccess()) {
    downloadText(countryLocalJsonFilename(), jsonText, "application/json");
    setStatus(
      els.jsonStatus,
      I18N.t("status.noFsApi"),
      "warn",
    );
    return false;
  }

  if (!localJsonFileHandle && promptIfMissing) {
    localJsonFileHandle = await window.showSaveFilePicker({
      suggestedName: countryLocalJsonFilename(),
      types: [
        {
          description: "Train store JSON",
          accept: { "application/json": [".json"] },
        },
      ],
    });
  }

  if (!localJsonFileHandle) return false;
  if (!(await verifyFileHandlePermission(localJsonFileHandle, true))) {
    throw new Error(I18N.t("err.noWritePerm"));
  }

  const writable = await localJsonFileHandle.createWritable();
  await writable.write(jsonText);
  await writable.close();
  return true;
}

async function pickLocalJsonFile() {
  if (supportsFileSystemAccess()) {
    const [handle] = await window.showOpenFilePicker({
      multiple: false,
      types: [
        {
          description: "Train store JSON",
          accept: { "application/json": [".json"] },
        },
      ],
    });
    if (!handle) return;
    localJsonFileHandle = handle;
    const file = await handle.getFile();
    return { text: await file.text(), name: file.name };
  }

  els.localJsonFileInput.value = "";
  els.localJsonFileInput.click();
  return null;
}
