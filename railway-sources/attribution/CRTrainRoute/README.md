# CRTrainRoute source attribution

Snapshot: [Laide140/CRTrainRoute at d75307df](https://github.com/Laide140/CRTrainRoute/tree/d75307df9c812abf1259b86b75202ba7b0048679), retrieved 2026-10-18.

The upstream code/documentation includes the [MIT notice](LICENSE.txt), copyright
2026 Laide. No upstream Python server/builder is executed or incorporated into
the app; the importer reads the upstream JSON as candidate source material.

Track geometry is attributed upstream to OpenStreetMap contributors, distributed
through `next.laide.net.cn`. © OpenStreetMap contributors;
[ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/) and
[OSM attribution](https://www.openstreetmap.org/copyright) apply separately from
the code's MIT notice. The upstream snapshot lacks an OSM extraction timestamp,
original node identities and an extraction manifest. These omissions remain
explicit; a Git revision does not supply the missing source version.

Station names/telecodes and coordinate/address records are attributed upstream
to 12306. The repository supplies no separate redistribution terms for these
records. Their datum is described as GCJ02 by upstream but has not been
independently established. The local candidate store retains the source values
and that uncertainty; it does not publish those values as WGS84 app resources.

The [intake manifest](../../china-crtrainroute.json) records the consumed files,
checksums, source URLs, coverage and unresolved production requirements.
