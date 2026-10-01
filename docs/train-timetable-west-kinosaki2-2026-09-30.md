# きのさき2号：2026-09-30 限定候補

[JR西日本の福知山駅・山陰本線の当日駅時刻表](https://timetable.jr-odekake.net/station-timetable/3208024001?date=20260930)の06:02発リンクから、[きのさき2号の列車時刻表](https://timetable.jr-odekake.net/train-timetable/90831?date=20260930)を確認した。列車番号は `5002M`、運転日は「毎日運転」と表示される。この候補が記録する運転日は **2026-09-30 の一日だけ**であり、表示された運転日欄を他の日付へ展開しない。

当日の時刻表で着発時刻が印刷された旅客扱い駅は次の7駅。`レ` の通過駅は停車駅として収録しない。

| 順 | 駅 | 着 | 発 | のりば |
|---:|---|---|---|---|
| 1 | 福知山 | — | 06:02 | 1 |
| 2 | 綾部 | 06:11 | 06:12 | 2 |
| 3 | 日吉 | 06:41 | 06:41 | — |
| 4 | 園部 | 06:48 | 06:49 | 2 |
| 5 | 亀岡 | 07:00 | 07:00 | — |
| 6 | 二条 | 07:12 | 07:13 | — |
| 7 | 京都 | 07:18 | — | 30 |

[JR西日本の2026年9月きっぷのルール](https://www.jr-odekake.net/ticket/guide/ebook/pages/pageindices/index15.html)は、きのさき号の京都～城崎温泉を「山陰本線経由」と明示する。福知山～京都はその一部で、現行 `jp-2025.json` の `jp-西日本旅客鉄道-山陰線` に7駅が一意かつ同順で存在する。6区間を `current_n02` の路線同定として登録し、`route_lines` は `partial` とする。[N02-25 の基準日](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html)は2025-12-31であり、2026-09-30の線路存続を個別に保証しないため、調査キューは `open` のままにした。列車運行会社の区間も未確定とした。

独立した[候補](../app/data/train-service-history/candidates/jr-west-kinosaki2-20260930.json)、[資料登録](../app/data/train-service-history/sources/source-registry-west-kinosaki2-20260930.jsonl)、[normalizer](../ios/tools/normalize-reviewed-west-kinosaki2-20260930.py)、専用テストを追加した。正規化ファイルの suffix は `west-kinosaki2-20260930`。列車時刻表に記載された転載・加工禁止を資料登録に明示し、原本HTMLは収録していない。
