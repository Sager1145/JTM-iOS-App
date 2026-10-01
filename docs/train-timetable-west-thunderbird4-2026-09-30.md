# サンダーバード4号：2026-09-30 限定候補

[敦賀駅・当日の湖西線駅時刻表](https://timetable.jr-odekake.net/station-timetable/2635014001?date=20260930)の07:35発リンクから、[サンダーバード4号の当日列車時刻表](https://timetable.jr-odekake.net/train-timetable/257961?date=20260930)を確認した。列車番号は `4004M`、運転日表示は「土曜・休日運休」。候補が登録するのは **2026-09-30 の一日だけ**。検索で見つかる[土曜・休日運転の別時刻ページ](https://timetable.jr-odekake.net/train-timetable/257971?date=20260926)の時刻は採用していない。

当日列車時刻表の着発時刻が印刷された旅客扱い駅は6駅。`レ` の通過駅は旅客停車駅として収録しない。

| 順 | 駅 | 着 | 発 | のりば |
|---:|---|---|---|---|
| 1 | 敦賀 | — | 07:35 | 33 |
| 2 | 近江今津 | 07:59 | 07:59 | — |
| 3 | 堅田 | 08:20 | 08:21 | — |
| 4 | 京都 | 08:37 | 08:38 | 7 |
| 5 | 新大阪 | 09:01 | 09:02 | 9 |
| 6 | 大阪 | 09:06 | — | 3 |

列車時刻表は近江塩津と山科を `レ` で明記し、敦賀駅の出発方面は湖西線と表示される。現行 `jp-2025.json` の駅順と線路所属を照合し、敦賀→近江塩津を `jp-西日本旅客鉄道-北陸線`、近江塩津→山科を `jp-西日本旅客鉄道-湖西線`、山科→大阪を `jp-西日本旅客鉄道-東海道線` として7個の連続した `current_n02` 路線片を登録した。近江塩津と山科は路線境界専用の駅アンカーで、`stop_times` には加えていない。

[国土交通省 N02-25 の基準日](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html)は2025-12-31。2026-09-30の物理線の個別有効期間が未証明なので `route_lines=partial` と調査キュー `open` を維持する。列車運行会社の区間も未確定。実運行の断定や通年運転日の展開はしない。

独立した[候補](../app/data/train-service-history/candidates/jr-west-thunderbird4-20260930.json)、[資料登録](../app/data/train-service-history/sources/source-registry-west-thunderbird4-20260930.jsonl)、[normalizer](../ios/tools/normalize-reviewed-west-thunderbird4-20260930.py)、専用テストを追加した。正規化ファイルの suffix は `west-thunderbird4-20260930`。原本HTMLは収録せず、列車時刻表に記載された転載・加工禁止を資料登録に明示した。
