# Final seven-interval preparation

Final candidate-only input is finalcandidate-input.json, SHA87fd1c46f5dafb9546fc6bd6f80d5453f425722042563b1f18f45d985ed488bc. Ordered owners Yodo,Nakamura,Yosan; intervals[0,18]/[0,1,2]/[87,88]. Every owned interval endpoint/outerguard alias is included. New station aliases Wakai/Kita/Kaina are literal at both adjacent owner endpoints; no old-source return connectors.

Current exact inputs: assigned Naka0/Yodo18/Yosan87/88, v3Yodo0, v4Naka1/2. Original JSON byte digests and normalized coordinate-array digests are separately recorded; they are distinct serialization measures. Counts219/137/85/360/157/33/26. BaselineCAS package5b6f1bf4821f8e1a7fbc74660e7170935ce3aa627e24c478674e2902f8eb2e55 and lanes734b9587c3ea9aa26334500680ff0684d4c5fb63be25b8ed599ec36bcc21525b.

Actual scoped owner helpers passed validateCandidate/sharedstationpassage, repairPackage, deriveNativeRows, deriveCandidateMeasuredReferences and repairParts. Physical line/decode equality assertions passed. Strict literal native equality outside all7 owned intervals passed; the earlier six-scope Nakamura#2 failure is resolved by explicit reviewed seven-scope ownership/candidate geometry, not a weaker invariant.

Final native ruler changes: Yodo76166.29350598699→76262.01634230342m (+95.72283631643222m); Nakamura43113.35413928109→43125.84763451615m (+12.493495235059527m); Yosan297876.6723673162→297876.6711416187m (−0.0012256975169293582m). Lane fullends follow final native rulers; exact Yosan unchanged-prefix775/209100/249700.32822160423 references remain unchanged. Native row digests and full mapped references are recorded separately.

Focused existing test passed1/1,136ms after the precise unchanged-boundary fix. Its code is unchanged and evidence reused here; helper assembly introduced no new implementation change. It tests shared alias disagreement/backwards passage rejection, moved native station-boundary remap, full ruler end, invalid measures and unrounded unchanged prefix-boundary preservation. After formal apply it checks shipped station/interval arrays directly, without archived candidate dependence.

Own prepared evidence/derived rows/reference files are under station-precise only. Root’s native-candidate-v1 and freeze job remain untouched. No production apply, resource build, app/UI work or native acceptance performed. All station/group/label/tunnel precision warnings remain; fresh actual three-Inspector plus Main candidate review is required before formal apply. No ordered-list closure.
