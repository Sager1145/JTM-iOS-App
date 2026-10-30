import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import test from 'node:test';
const require = createRequire(import.meta.url);
const helperURL = new URL('../public/rail-history-service.js', import.meta.url);
const period = (extra = {}) => ({ history_id: 'bus', lineID: 'isumi', scope: 'whole_line',
  station_membership_ids: ['005230', '005239'], valid_from: '2024-10-05', valid_to: '2025-04-01',
  serviceStatus: 'substitute_bus', source: ['official:notice'], ...extra });
const overlay = (extra = {}) => ({ schema_version: '2', revision: 'test', features: ['service_status_periods'],
  sections: [], stations: [], retirements: [], service_status_periods: [period()], ...extra });
const api = () => require(helperURL.pathname);

test('dated status distinguishes before/start/end/after, other line and legacy', () => {
  const { validateRailServiceStatusOverlay: validate, resolveRailServiceStatus: resolve } = api();
  const input = overlay();
  const saved = JSON.stringify(input);
  assert.equal(validate(input), input);
  const normal = { managed: true, serviceStatus: null, historyID: null };
  const legacy = { managed: false, serviceStatus: null, historyID: null };
  assert.deepEqual(resolve(input, 'isumi', '2024-10-04'), normal);
  assert.deepEqual(resolve(input, 'isumi', '2024-10-05'), { managed: true, serviceStatus: 'substitute_bus', historyID: 'bus' });
  assert.deepEqual(resolve(input, 'isumi', '2025-03-31'), { managed: true, serviceStatus: 'substitute_bus', historyID: 'bus' });
  assert.deepEqual(resolve(input, 'isumi', '2025-04-01'), normal);
  assert.deepEqual(resolve(input, 'isumi', '2026-01-01'), normal);
  assert.deepEqual(resolve(input, 'other', '2024-10-05'), legacy);
  const old = { schema_version: '1', revision: 'old', sections: [], stations: [], retirements: [] };
  assert.equal(validate(old), old);
  assert.deepEqual(resolve(old, 'isumi', '2024-10-05'), legacy);
  assert.equal(JSON.stringify(input), saved);
});

test('open end and adjacent intervals use strict real civil days with no clock', () => {
  const { validateRailServiceStatusOverlay: validate, resolveRailServiceStatus: resolve } = api();
  const input = validate(overlay({ service_status_periods: [period(), period({ history_id: 'next', valid_from: '2025-04-01', valid_to: null })] }));
  assert.equal(resolve(input, 'isumi', '2025-04-01').historyID, 'next');
  const open = validate(overlay({ service_status_periods: [period({ valid_to: undefined })] }));
  assert.equal(resolve(open, 'isumi', '9999-12-31').historyID, 'bus');
  for (const day of [null, undefined, '', '2024-02-30', '1900-02-29', '0000-01-01', '2024-10-05T00:00:00Z', '2024-1-05', new Date()])
    assert.throws(() => resolve(input, 'isumi', day), /date|YYYY-MM-DD|civil/i);
  assert.equal(resolve(input, 'isumi', '2000-02-29').managed, true);
});

test('new contract rejects malformed schema/capabilities/status/periods without compact ownership guesses', () => {
  const { validateRailServiceStatusOverlay: validate } = api();
  for (const extra of [
    { schema_version: '3' }, { schema_version: 2 }, { features: undefined }, { features: [] },
    { features: ['service_status_periods', 'unknown'] }, { features: ['service_status_periods', 'service_status_periods'] },
    { service_status_periods: [] }, { service_status_periods: null },
  ]) assert.throws(() => validate(overlay(extra)));
  for (const extra of [
    { history_id: '' }, { lineID: '' }, { scope: 'partial' }, { serviceStatus: 'suspended' },
    { station_membership_ids: [] }, { station_membership_ids: ['x', 'x'] }, { station_membership_ids: [''] },
    { valid_from: null }, { valid_from: '2024-02-30' }, { valid_to: '2024-10-05' },
    { valid_to: '2024-10-04' }, { source: [] }, { source: [''] }, { source: 'notice' },
  ]) assert.throws(() => validate(overlay({ service_status_periods: [period(extra)] })));
  assert.throws(() => validate(overlay({ service_status_periods: [period(), period()] })), /duplicate/i);
  assert.throws(() => validate(overlay({ service_status_periods: [period(), period({ history_id: 'overlap', valid_from: '2025-03-31' })] })), /overlap/i);
  assert.throws(() => validate(overlay({ schema_version: '1' })));
  // These are raw memberships, deliberately unlike hypothetical compact endpoint groups.
  assert.doesNotThrow(() => validate(overlay()));
});

test('same pure API loads as classic browser and worker with no app globals', () => {
  const source = fs.readFileSync(helperURL, 'utf8');
  for (const surface of [{}, { self: {} }]) {
    const context = vm.createContext(surface);
    vm.runInContext(source, context);
    const result = context.RailHistoryService.resolveRailServiceStatus(
      context.RailHistoryService.validateRailServiceStatusOverlay(overlay()), 'isumi', '2024-10-05');
    assert.equal(result.historyID, 'bus');
    assert.equal(result.managed, true);
  }
});

test('classic app full history validator integrates the pure contract and old rules', () => {
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(helperURL, 'utf8'), context);
  vm.runInContext(fs.readFileSync(new URL('../public/app-rail-history.js', import.meta.url), 'utf8'), context);
  const validate = vm.runInContext('validateRailHistoryOverlay', context);
  assert.equal(validate(overlay()).schema_version, '2');
  assert.throws(() => validate(overlay({ service_status_periods: [period({ scope: 'partial' })] })));
  assert.throws(() => validate(overlay({ stations: [{ properties: { history_id: 's', valid_from: '2024-02-30' } }] })));
  // A source event may underpin both a station stamp and a service period.
  assert.doesNotThrow(() => validate(overlay({ stations: [{ properties: { history_id: 'bus', valid_from: '2024-01-01' } }] })));
});

test('browser/worker loading declarations and Node app sandbox expose the shared helper first', async () => {
  const html = fs.readFileSync(new URL('../public/index.html', import.meta.url), 'utf8');
  assert.ok(html.indexOf('src="rail-history-service.js?') < html.indexOf('src="rail-network.js?'));
  const imports = [];
  const worker = vm.createContext({ self: {}, importScripts: (...urls) => imports.push(...urls) });
  vm.runInContext(fs.readFileSync(new URL('../public/rail-network-worker.js', import.meta.url), 'utf8'), worker);
  assert.match(imports[0], /^\.\/rail-history-service\.js\?/);
  assert.match(imports[1], /^\.\/rail-network\.js\?/);
  const { evaluateAppScripts, makeSandbox } = await import('../scripts/lib/app-family-sandbox.mjs');
  const sandbox = makeSandbox();
  evaluateAppScripts(sandbox);
  assert.equal(vm.runInContext('typeof RailHistoryService.resolveRailServiceStatus', sandbox), 'function');
});

test('standalone legacy app harness stays compatible but cannot accept schema2 without helper', () => {
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(new URL('../public/app-rail-history.js', import.meta.url), 'utf8'), context);
  const validate = vm.runInContext('validateRailHistoryOverlay', context);
  const old = { schema_version: '1', revision: 'legacy', sections: [], stations: [], retirements: [] };
  assert.equal(validate(old), old);
  assert.throws(() => validate(overlay()), /RailHistoryService must be loaded/);
});


test('schema1 preserves ignored optional feature metadata while reserving dated status for schema2', () => {
  const { validateRailServiceStatusOverlay: validateService } = api();
  const contexts = [vm.createContext({}), vm.createContext({})];
  vm.runInContext(fs.readFileSync(helperURL, 'utf8'), contexts[0]);
  for (const context of contexts)
    vm.runInContext(fs.readFileSync(new URL('../public/app-rail-history.js', import.meta.url), 'utf8'), context);
  const validators = [validateService, ...contexts.map((context) => vm.runInContext('validateRailHistoryOverlay', context))];
  const legacy = (features) => ({ schema_version: '1', revision: 'legacy', sections: [], stations: [], retirements: [], features });
  for (const validate of validators) {
    for (const features of [['identity_periods', 'future_optional_feature'], ['identity_periods', 'identity_periods'],
      { optional: true }, 'legacy metadata', null, 7]) {
      const input = legacy(features);
      assert.equal(validate(input), input);
    }
    assert.throws(() => validate(legacy(['service_status_periods'])));
    assert.throws(() => validate({ ...legacy({ optional: true }), service_status_periods: [] }));
  }
});
