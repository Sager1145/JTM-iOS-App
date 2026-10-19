import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { evaluateAppScripts, makeSandbox } from "../scripts/lib/app-family-sandbox.mjs";
const context = makeSandbox({userAgent: "region-store-test"});
context.console = {log() {}, warn() {}, error() {}, info() {}, debug() {}};
evaluateAppScripts(context);
const run = (expression) => vm.runInContext(expression, context);
run("stationCandidatesIndex = new Map();");

for (const country of ["jp", "tw", "hk", "mo", "kr", "cn"]) {
  test(`${country} keeps its country and timetable fields through import/export`, () => {
    context.__train = {id: "region_01", date: "2026-09-30", number: "Service 1", region: country,
      number_en: "Service 1", vehicle_type: "Vehicle", train_type: "Express", company: "Operator",
      origin: "A", destination: "B", notes: "Published notes",
      stops: [{name: "A", departure: "07:00", platform_number: 0},
              {name: "B", arrival: "07:30", platform_number: null}]};
    const output = JSON.parse(run("JSON.stringify(normalizeExportTrain(normalizeImportedTrain(__train)))"));
    assert.equal(output.region, country);
    assert.equal(output.number_en, "Service 1");
    assert.equal(output.vehicle_type, "Vehicle");
    assert.equal(output.notes, "Published notes");
    assert.equal(output.stops[0].platform_number, 0);
    assert.equal(output.stops[1].platform_number, null);
    context.__train = output;
    assert.doesNotThrow(() => run("normalizeImportedTrain(__train)"));
  });
}

test("retired regions and untagged railway identities are rejected", () => {
  for (const country of ["us", "ca"]) {
    context.__train = {region: country};
    assert.throws(() => run("normalizeImportedTrain(__train)"), /Unsupported journey region/);
    context.__train = {stops: [{n02_station_code: `${country.toUpperCase()}-RETIRED`}]};
    assert.throws(() => run("normalizeImportedTrain(__train)"), /Unsupported railway identity/);
    context.__train = {route_sections: [{line_ids: [`${country}-retired`]}]};
    assert.throws(() => run("normalizeImportedTrain(__train)"), /Unsupported railway identity/);
    assert.throws(() => run(`railScopeCountriesForCountry("${country}")`), /Unsupported railway region/);
  }
});


test("inferred interval origin survives import and both export forms", () => {
  context.__section = {from_n02_station_code: "003766", to_n02_station_code: "004095",
    section_codes: ["jp-東日本旅客鉄道-総武線-3@003766:003872"],
    section_codes_origin: "corridorPreference"};
  for (const exporter of ["normalizeExportRouteSection", "leanExportSection"]) {
    const output = JSON.parse(run(`JSON.stringify(${exporter}(normalizeImportedRouteSection(__section)))`));
    assert.equal(output.section_codes_origin, "corridorPreference");
    context.__section = output;
    assert.equal(run("normalizeImportedRouteSection(__section).section_codes_origin"), "corridorPreference");
  }
  delete context.__section.section_codes_origin;
  assert.equal(run("normalizeImportedRouteSection(__section).section_codes_origin"), undefined);
});


test("China loads only its own resources and has no foreign sample fallback", async () => {
  run('activeCountry = "cn"');
  assert.deepEqual(Array.from(run('railScopeCountriesForCountry("cn")')), ["cn"]);
  assert.deepEqual(Array.from(run('railScopeCountriesForCountry("hk")')), ["hk"]);
  assert.deepEqual(Array.from(run('railScopeCountriesForCountry("mo")')), ["mo"]);
  assert.deepEqual(Array.from(run('railPackageUrlsForCountry("cn")')), ["./rail/cn-2025.json"]);
  assert.deepEqual(Array.from(run('railSectionsApisForCountry("cn")')), ["rail-sections-cn"]);
  assert.deepEqual(Array.from(run('stationsApisForCountry("cn")')), ["stations-cn"]);
  assert.equal(await run('loadSampleManifest()'), null);
  const train = JSON.parse(run('JSON.stringify(createBlankTrain())'));
  assert.equal(train.region, "cn");
  assert.equal(train.origin, "深圳北");
  assert.equal(train.destination, "香港西九龙");
  assert.equal(train.stops[0].n02_station_code, "CN-12306-IOQ");
  assert.equal(train.stops[1].n02_station_code, "CN-12306-XJA");
  assert.deepEqual(train.route_sections[0].line_ids, ["cn-guangshengan-hsr"]);
  assert.deepEqual(train.route_sections[0].operator_names, []);
  assert.deepEqual(train.route_policy.preferred_operator_names, []);
  assert.deepEqual(train.route_policy.allowed_institution_type_codes, ["1"]);
  run('activeCountry = "jp"');
});

test("China statistics classify high-speed and conventional services without a JR union", () => {
  run('activeCountry = "cn"');
  assert.equal(run('classifySectionMask({institution_type_code: "1"})'), 1);
  assert.equal(run('classifySectionMask({institution_type_code: "2"})'), 2);
  assert.equal(run('classifySectionMask({institution_type_code: "3", railway_class_code: "12"})'), 8);
  assert.equal(run('classifySectionMask({institution_type_code: "3", railway_class_code: "21"})'), 32);
  assert.equal(run('filterCategoryForMask(classifySectionMask({institution_type_code: "2"}))'), "jr");
  assert.equal(run('serviceGroupOfTrain({train_type:"高速动车组"})'), "hsr");
  assert.equal(run('serviceGroupOfTrain({train_type:"G123"})'), "hsr");
  assert.equal(run('serviceGroupOfTrain({train_type:"特快"})'), "ltd");
  assert.ok(!Array.from(run('activeStatCategories()')).some(row => row.i18n === "stat.jr"));
  run('activeCountry = "jp"');
});

test("China civil today uses Beijing time at the Japan midnight boundary", () => {
  context.Date = class extends Date {
    constructor(...args) { super(...(args.length ? args : ["2026-10-18T15:30:00Z"])); }
  };
  try {
    assert.equal(run('statsRegionCivilToday("cn")'), "2026-10-18");
    assert.equal(run('statsRegionCivilToday("jp")'), "2026-10-19");
  } finally { delete context.Date; }
});


test("China exact intervals honor line identity and retain source provenance", () => {
  run(`
    activeCountry = "cn";
    railSectionsGeoJson = {type:"FeatureCollection", features:[{
      type:"Feature", properties:{line_id:"cn-guangshengan-hsr", line_name:"广深港高速铁路",
        operator:"Test operator", institution_type_code:"1"},
      geometry:{type:"LineString", coordinates:[[114.029,22.609],[114.05,22.5],[114.165,22.304]]}
    }]};
    stationCandidatesIndex = new Map([
      ["CN-12306-IOQ", [{type:"Feature", properties:{station_name:"深圳北",
        n02_station_code:"CN-12306-IOQ", line_name:"广深港高速铁路", operator:"Test operator"},
        geometry:{type:"Point",coordinates:[114.029,22.609]}}]],
      ["CN-12306-XJA", [{type:"Feature", properties:{station_name:"香港西九龙",
        n02_station_code:"CN-12306-XJA", line_name:"广深港高速铁路", operator:"Test operator"},
        geometry:{type:"Point",coordinates:[114.165,22.304]}}]]
    ]);
    routeSolverApi = {pathLengthForCoordinates:() => 40000};
    var cnBlank = createBlankTrain();
  `);
  try {
    const result = JSON.parse(run('JSON.stringify(solveTaiwanRouteSectionOnOfficialInterval(cnBlank.route_sections[0], 0, cnBlank, ["1"]))'));
    assert.ok(result);
    assert.equal(result.properties.route_choice, "source_interval_exact");
    assert.equal(result.properties.solve_mode, "source_interval_exact");
    assert.equal(result.properties.station_code_system, "CN-12306");
    assert.equal(result.geometry.coordinates.length, 3);
    run('cnBlank.route_sections[0].line_ids = ["cn-other"]');
    assert.equal(run('solveTaiwanRouteSectionOnOfficialInterval(cnBlank.route_sections[0], 0, cnBlank, ["1"])'), null);
    assert.equal(run('stationCodeSystem("CN-12306-XJA")'), "CN-12306");
    assert.equal(run('stationCodeFieldLabel("CN-12306-XJA")'), "12306");
  } finally {
    run('activeCountry = "jp"; railSectionsGeoJson = null; stationCandidatesIndex = new Map(); routeSolverApi = null;');
  }
});
