// Pure optional dated-service contract. No app state, DOM, clock or compact
// station group lookup: raw membership ownership is proved by the compiler.
(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.RailHistoryService = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const own = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
  const nonblank = (value) => typeof value === 'string' && value.trim().length > 0;
  const fail = (message) => { throw new Error(`rail history overlay: ${message}`); };
  const knownFeatures = new Set(['identity_periods', 'service_status_periods']);

  function validateRailCivilDay(value, label = 'civil day') {
    const match = typeof value === 'string' && /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
    if (!match) fail(`${label} must be YYYY-MM-DD`);
    const year = Number(match[1]), month = Number(match[2]), day = Number(match[3]);
    const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
    const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > days[month - 1])
      fail(`${label} is not a real Gregorian date`);
    return value;
  }

  // Validate the optional contract only. The app's complete history validator
  // also owns legacy geometry/identity records; workers can use this structural
  // contract without importing that app lexical script.
  function validateRailServiceStatusOverlay(overlay) {
    if (!overlay || typeof overlay !== 'object' || Array.isArray(overlay)) fail('not an object');
    if (overlay.schema_version !== '1' && overlay.schema_version !== '2')
      fail(`unsupported schema_version ${overlay.schema_version}`);
    if (!nonblank(overlay.revision)) fail('missing revision');
    const dated = overlay.schema_version === '2';
    if (!dated) {
      if (own(overlay, 'service_status_periods') ||
          (Array.isArray(overlay.features) && overlay.features.includes('service_status_periods')))
        fail('service_status_periods requires schema_version 2');
      return overlay;
    }
    if (own(overlay, 'features')) {
      if (!Array.isArray(overlay.features) || overlay.features.some((feature) => !knownFeatures.has(feature)))
        fail('features contains an unsupported capability');
      if (new Set(overlay.features).size !== overlay.features.length) fail('duplicate feature capability');
    }
    if (!overlay.features?.includes('service_status_periods')) fail('missing service_status_periods capability');
    if (!Array.isArray(overlay.service_status_periods) || !overlay.service_status_periods.length)
      fail('service_status_periods must be a nonempty array');
    const ids = new Set(), byLine = new Map();
    overlay.service_status_periods.forEach((period, index) => {
      const label = `service_status_periods[${index}]`;
      if (!period || typeof period !== 'object' || Array.isArray(period)) fail(`${label} is not an object`);
      if (!nonblank(period.history_id)) fail(`${label} has a blank history_id`);
      const id = period.history_id.trim();
      if (ids.has(id)) fail(`duplicate service period history_id ${id}`);
      ids.add(id);
      if (!nonblank(period.lineID)) fail(`${label}.lineID is blank`);
      if (period.scope !== 'whole_line') fail(`${label}.scope must be whole_line`);
      if (period.serviceStatus !== 'substitute_bus') fail(`${label}.serviceStatus is unsupported`);
      const memberships = period.station_membership_ids;
      if (!Array.isArray(memberships) || !memberships.length || memberships.some((id) => !nonblank(id)))
        fail(`${label}.station_membership_ids must be a nonempty string array`);
      if (new Set(memberships.map((id) => id.trim())).size !== memberships.length)
        fail(`${label} has duplicate station_membership_ids`);
      if (!Array.isArray(period.source) || !period.source.length || period.source.some((source) => !nonblank(source)))
        fail(`${label}.source must be a nonempty source-reference string array`);
      const from = validateRailCivilDay(period.valid_from, `${label}.valid_from`);
      const to = period.valid_to == null ? null : validateRailCivilDay(period.valid_to, `${label}.valid_to`);
      if (to && from >= to) fail(`${label} valid_from must precede valid_to`);
      const prior = byLine.get(period.lineID) || [];
      if (prior.some((other) => (to == null || to > other.valid_from) &&
          (other.valid_to == null || other.valid_to > from)))
        fail(`overlapping service periods for ${period.lineID}`);
      prior.push(period);
      byLine.set(period.lineID, prior);
    });
    // Membership ownership and other history ID namespaces belong to their own validators.
    return overlay;
  }

  // Caller supplies a validated overlay and an explicit regional civil day.
  // Managed normal is an instruction to bypass static status, not legacy fallback.
  function resolveRailServiceStatus(validatedOverlay, lineID, civilDay) {
    validateRailCivilDay(civilDay);
    const periods = validatedOverlay?.service_status_periods || [];
    let managed = false;
    for (const period of periods) {
      if (period.lineID !== lineID) continue;
      managed = true;
      if (civilDay >= period.valid_from && (period.valid_to == null || civilDay < period.valid_to))
        return { managed: true, serviceStatus: period.serviceStatus, historyID: period.history_id };
    }
    return { managed, serviceStatus: null, historyID: null };
  }

  return { validateRailCivilDay, validateRailServiceStatusOverlay, resolveRailServiceStatus };
});
