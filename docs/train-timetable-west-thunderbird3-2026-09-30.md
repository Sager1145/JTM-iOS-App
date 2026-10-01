# サンダーバード3号：2026-09-30 限定候補

[京都駅・当日の北陸・東海方面駅時刻表](https://timetable.jr-odekake.net/station-timetable/2784076002?date=20260930)の07:29発リンクから[サンダーバード3号列車時刻表](https://timetable.jr-odekake.net/train-timetable/257661?date=20260930)を確認した。列車番号は `4003M`、運転日表示は「毎日運転」。候補が登録するのは **2026-09-30 の一日だけ**である。

当日列車時刻表の着発時刻が印刷された旅客扱い駅は5駅。`レ` の通過駅は旅客停車駅として収録しない。

| 順 | 駅 | 着 | 発 | のりば |
|---:|---|---|---|---|
| 1 | 大阪 | — | 07:00 | 11 |
| 2 | 新大阪 | 07:03 | 07:04 | 4 |
| 3 | 高槻 | 07:14 | 07:15 | — |
| 4 | 京都 | 07:28 | 07:29 | 0 |
| 5 | 敦賀 | 08:23 | — | 32 |

列車時刻表は山科と近江塩津を `レ` で明記する。現行 `jp-2025.json` の駅順と線路所属を照合し、大阪→山科を `jp-西日本旅客鉄道-東海道線`、山科→近江塩津を `jp-西日本旅客鉄道-湖西線`、近江塩津→敦賀を `jp-西日本旅客鉄道-北陸線` として6個の連続した `current_n02` 路線片を登録した。山科と近江塩津は路線境界専用の駅アンカーで、`stop_times` には加えていない。

[国土交通省 N02-25 の基準日](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html)は2025-12-31。2026-09-30の物理線の個別有効期間が未証明なので `route_lines=partial` と調査キュー `open` を維持する。列車運行会社の区間も未確定。実運行の断定や通年運転日の展開はしない。

独立した[候補](../app/data/train-service-history/candidates/jr-west-thunderbird3-20260930.json)、[資料登録](../app/data/train-service-history/sources/source-registry-west-thunderbird3-20260930.jsonl)、[normalizer](../ios/tools/normalize-reviewed-west-thunderbird3-20260930.py)、専用テストを追加した。正規化ファイルの suffix は `west-thunderbird3-20260930`。原本HTMLは収録せず、列車時刻表に記載された転載・加工禁止を資料登録に明示した。
