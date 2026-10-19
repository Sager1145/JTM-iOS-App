// Retained source registry for static publication. Runtime railway resources
// are independent of the retired Express backend and its private train stores.
const COUNTRIES = Object.freeze(['jp', 'tw', 'hk', 'mo', 'kr', 'cn']);
const suffixed = (name, country) => country === 'jp' ? name : `${name}-${country}`;
const DATASET_NAMES = Object.freeze([
  'default-trains', 'matched-routes', 'matched-stops', 'rail-history',
  'physical-rail-junctions',
  ...COUNTRIES.flatMap(country =>
    ['rail-sections', 'stations', 'station-readings', 'station-names']
      .map(name => suffixed(name, country))),
]);
const PART_DATASETS = Object.freeze([
  // Only regions with published samples require a precomputed manifest.
  ...COUNTRIES.filter(country => country !== 'cn')
    .map(country => ({dir: suffixed('sample-data', country)})),
  {dir: 'new-year-grand-loop-data'},
  {dir: 'tokyo-limited-express-loop-data'},
].map(dataset => Object.freeze({
  ...dataset,
  missingDataError: `Missing precomputed manifest: data/${dataset.dir}/manifest.json`,
})));
module.exports = {COUNTRIES, DATASET_NAMES, PART_DATASETS};
