import json, os, sys
repo = sys.argv[1]
out = os.path.join(repo, 'ios/auxiliary/RailDiagnostics/Modules/AreaRepair/Tests/AreaKitTests/Fixtures/repo')
OP = 'テスト鉄道'
def p(path): 
    full = os.path.join(out, path); os.makedirs(os.path.dirname(full), exist_ok=True); return full
def st(code, name, lon, lat): return [code, name, lon, lat, '', 1]
lines = [
  {"id": "jp-テスト鉄道-本線", "name": "本線", "operator": OP, "rank": 1, "stationOrderDirection": "down",
   "alignmentPairs": [{"with": "jp-テスト鉄道-本線-p1", "from": "駅一", "to": "駅二", "direction": "down", "source": "https://example.org/pair"}],
   "stations": [st("100001", "駅一", 140.0, 35.0), st("100002", "駅二", 140.01, 35.0), st("100003", "駅三", 140.02, 35.0)],
   "segments": [[0.9, 0, [[140.0, 35.0], [140.005, 35.0], [140.01, 35.0]]], [0.9, 0, [[140.01, 35.0], [140.015, 35.0], [140.02, 35.0]]]]},
  {"id": "jp-テスト鉄道-本線-p1", "name": "本線", "operator": OP, "rank": 1, "alignmentOf": "jp-テスト鉄道-本線",
   "alignmentRole": "paired_alignment", "alignmentDirection": "up", "stationOrderDirection": "down", "permittedTraversal": "forward",
   "stations": [st("100001", "駅一", 140.0, 35.0), st("100002", "駅二", 140.01, 35.0)],
   "segments": [[0.9, 0, [[140.0, 35.0], [140.005, 35.0003], [140.01, 35.0]]]]},
  {"id": "jp-テスト鉄道-支線", "name": "支線", "operator": OP, "rank": 2,
   "stations": [st("100002", "駅二", 140.01, 35.0), st("100004", "駅四", 140.01, 35.01)],
   "segments": [[1.1, 0, [[140.01, 35.0001], [140.01, 35.005], [140.01, 35.01]]]]},
  {"id": "jp-テスト鉄道-東線", "name": "東線", "operator": OP, "rank": 2,
   "stations": [st("100005", "駅五", 140.03, 35.0), st("100006", "駅六", 140.04, 35.00054)],
   "segments": [[0.9, 0, [[140.03, 35.0], [140.035, 35.0], [140.04, 35.0]]]]},
  {"id": "jp-テスト鉄道-角線", "name": "角線", "operator": OP, "rank": 2,
   "stations": [st("100007", "駅七", 140.0, 35.02), st("100008", "駅八", 140.02, 35.04)],
   "segments": [[4.0, 0, [[140.0, 35.02], [140.01, 35.02], [140.02, 35.02], [140.02, 35.03], [140.02, 35.04]]]]},
  {"id": "jp-テスト鉄道-緩線", "name": "緩線", "operator": OP, "rank": 2,
   "stations": [st("100009", "駅九", 139.92, 35.03), st("100010", "駅十", 140.1291, 35.068)],
   "segments": [[20.0, 0, [[139.92, 35.03], [139.975, 35.03], [140.03, 35.03], [140.07955, 35.049], [140.1291, 35.068]]]]},
]
package = {"format": "compact-v1", "version": "fixture", "country": "JP", "lines": lines}
open(p('app/public/rail/jp-2025.json'), 'w', encoding='utf-8').write(json.dumps(package, separators=(',', ':'), ensure_ascii=False))
def section(name, coords): return {"type": "Feature", "properties": {"N02_001": "12", "N02_002": "5", "N02_003": name, "N02_004": OP}, "geometry": {"type": "LineString", "coordinates": coords}}
sections = [
  section("本線", [[140.0, 35.0], [140.005, 35.0], [140.01, 35.0], [140.015, 35.0], [140.02, 35.0]]),
  section("本線", [[140.0, 35.0], [140.005, 35.0003], [140.01, 35.0]]),
  section("支線", [[140.01, 35.0001], [140.01, 35.005], [140.01, 35.01]]),
  section("東線", [[140.03, 35.0], [140.035, 35.0], [140.04, 35.0]]),
  section("角線", [[140.0, 35.02], [140.01, 35.02], [140.02, 35.02], [140.02, 35.03], [140.02, 35.04]]),
  section("緩線", [[139.92, 35.03], [139.975, 35.03], [140.03, 35.03], [140.07955, 35.049], [140.1291, 35.068]]),
  section("旧線", [[140.0, 35.01], [140.005, 35.01]]),
  section("旧線", [[140.005, 35.01], [140.012, 35.01]]),
]
open(p('app/data/rail-sections.json'), 'w', encoding='utf-8').write(json.dumps({"type": "FeatureCollection", "features": sections}, separators=(',', ':'), ensure_ascii=False))
def station(line, name, code, lon, lat): return {"type": "Feature", "properties": {"railway_class_code": "12", "institution_type_code": "5", "line_name": line, "operator": OP, "station_name": name, "n02_station_code": code, "n02_group_code": code}, "geometry": {"type": "LineString", "coordinates": [[lon - 0.0003, lat], [lon + 0.0003, lat]]}}
stations = [station("本線", "駅一", "100001", 140.0, 35.0), station("本線", "駅二", "100002", 140.01, 35.0), station("本線", "駅三", "100003", 140.02, 35.0),
            station("支線", "駅四", "100004", 140.01, 35.01), station("東線", "駅五", "100005", 140.03, 35.0), station("東線", "駅六", "100006", 140.04, 35.0),
            station("角線", "駅七", "100007", 140.0, 35.02), station("角線", "駅八", "100008", 140.02, 35.04),
            station("緩線", "駅九", "100009", 139.92, 35.03), station("緩線", "駅十", "100010", 140.1291, 35.068)]
open(p('app/data/stations.json'), 'w', encoding='utf-8').write(json.dumps({"type": "FeatureCollection", "features": stations}, separators=(',', ':'), ensure_ascii=False))
history = {"schema_version": "1", "revision": "fixture.1", "features": ["identity_periods"], "source": "fixture", "sections": [], "stations": [],
  "retirements": [
    {"history_id": "jp.test.old.closure", "match": {"line_name": "旧線", "operator": OP, "bbox": [139.9999, 35.0099, 140.008, 35.0101], "targets": ["sections"]}, "source": "https://example.org/closure", "valid_to": "2020-04-01"},
    {"history_id": "jp.test.ghost.closure", "match": {"line_name": "幽霊線", "operator": OP, "bbox": [139.9999, 35.0099, 140.006, 35.0101], "targets": ["sections"]}, "source": "https://example.org/ghost", "valid_to": "2019-04-01"},
  ], "identity_periods": []}
open(p('app/data/rail-history.json'), 'w', encoding='utf-8').write(json.dumps(history, separators=(',', ':'), ensure_ascii=False))
real = json.load(open(os.path.join(repo, 'app/data/physical-rail-junctions.json'), encoding='utf-8'))
junctions = {"format": real["format"], "policy": real["policy"], "junctions": real["junctions"][:3]}
open(p('app/data/physical-rail-junctions.json'), 'w', encoding='utf-8').write(json.dumps(junctions, indent=2, ensure_ascii=False) + "\n")
open(p('app/data/physical-rail-topology.json'), 'w', encoding='utf-8').write('{"fixture": true}\n')
open(p('app/data/default-trains.json'), 'w', encoding='utf-8').write('{"schema_version":"1.3","trains":[]}\n')
os.makedirs(os.path.join(out, 'port-fixtures'), exist_ok=True)
open(os.path.join(out, 'port-fixtures', 'README.txt'), 'w').write('Marks this directory as a synthetic JTM repository root for AreaKit tests.\n')
print('ok')
