# Railway source center and publication boundary

User requested OSM/official cross-checking, central local source storage with annotations, excluding raw railway metadata from future commits, and coordination with other chats. Preserve source contents, runtime databases and concurrent changes; no commit/push or historical rewrite.

- [x] Inventory canonical inputs, ignored comparison references and runtime consumers; distinguish constructed solver databases from raw N02 extracts.
- [x] Move 46 existing input/reference groups (13,799 files) to `railway-sources/local/`, retain ignored compatibility aliases, and index each file locally. No conversion or source-content edits.
- [x] Import existing external reference downloads without changing that checkout: 168 OSM degree-cell cache files, 18 official N02 historical files, 27 N02 baseline files, 4 JP OSM extracts. Central inventory total: 14,016 files.
- [x] Annotate groups, roles, paths, publishers/metadata references and unknown provenance fields in `railway-sources/catalog.json`; retain original sidecars, registries, CRS and licences. Copy OpenCC release attribution separately.
- [x] Ignore central store and all compatibility paths. Remove 4,678 formerly tracked source files from Git index only; preserve physical files. Zero indexed source inputs remain among the selected groups.
- [x] Keep runtime solver identities/geometry, built SQL/JSON databases, packages, histories, reviewed topology, code, corrective rules and production regression fixtures. No required present runtime product is ignored or moved.
- [x] Set historical N02 builder default to imported central history input. Bootstrap command creates missing aliases only, preserving other files; all 46 groups were available in its idempotent execution.
- [x] Bounded independent review: no incorrect alias, ignored runtime product, broken N02 default or relative-manifest-resolution defect found. File listings/counts, ignore queries and source review provide evidence; no whole-tree hashes or retired audit pipeline.
- [x] Coordinate with alignment and through-service chats. Those chats own their production code/products and evidence. The alignment chat reports its targeted Nihongi DisplayParts regression passed and resource repair preserves original station/segment geometry and distance.

Nihongi: operator official station page and publications describe a switchback. Alignment owner cross-checked original route with existing OSM ways and reproduced display-end trimming into a diagonal shortcut; local protection/caches repaired at the display layer, preserving the physical route. Official reference: https://www.echigo-tokimeki.co.jp/guide/haneuma-line/ . Local owning evidence: `app/scripts/railway/nihongi-switchback-evidence.json`. Cached OSM is historical partial reference, not proof of current national completeness.

Retired North America archives and historical build snapshots remain in place, indexed as references without opening or repackaging. External Web source originals were not deleted or untracked by this chat. Existing Git history retains old blobs; only future staged contents are affected. No user source deletion, national data regeneration, commit, push or history rewrite was performed.

The original batch-solver follow-through remains tracked in `2026-10-10-route-workbench-inspection.md`; source consolidation does not turn incomplete physical route evidence into a verified route.
