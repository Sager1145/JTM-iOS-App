# 特急数据库检查清单（2026-09-23）

每一项都由自动化测试逐条执行，不跳过任何条目。勾选含义：

- 列车名数据库：**辨识** = 每个别名（含 1号／ 1 后缀与无车次）都解析到本条目且被归为特急；**Logo** = 非空 logoPath 的文件已打包（无专属 logo 的条目按规则退回公司 logo／默认图标）。
- 停靠站模式：**站名** = 每个站名存在于 stations.json；**站序** = 用坐标检查无倒退；**求解** = 每个相邻站区间都能被真实路线求解器求出（分母为区间数）；**验证** = apply() 产物通过 TrainValidation（由 TrainServicePatternsTests 覆盖）。

## 一、列车名数据库（163 条，通过 163）

| # | id | 名称 | 辨识 | Logo |
|---|---|---|---|---|
| 1 | `haruka` | はるか | ✅ | ✅ |
| 2 | `narita-express` | 成田エクスプレス | ✅ | ✅ (narita-express.png) |
| 3 | `sunrise-izumo` | サンライズ出雲 | ✅ | ✅ |
| 4 | `sunrise-seto` | サンライズ瀬戸 | ✅ | ✅ |
| 5 | `thunderbird` | サンダーバード | ✅ | ✅ |
| 6 | `azusa` | あずさ | ✅ | ✅ |
| 7 | `kaiji` | かいじ | ✅ | ✅ |
| 8 | `hitachi` | ひたち | ✅ | ✅ |
| 9 | `tokiwa` | ときわ | ✅ | ✅ |
| 10 | `odoriko` | 踊り子 | ✅ | ✅ |
| 11 | `saphir-odoriko` | サフィール踊り子 | ✅ | ✅ |
| 12 | `spacia-x` | スペーシア X | ✅ | ✅ (spacia-x.png) |
| 13 | `revaty` | リバティ | ✅ | ✅ |
| 14 | `hinotori` | ひのとり | ✅ | ✅ (hinotori.png) |
| 15 | `shimakaze` | しまかぜ | ✅ | ✅ (shimakaze.png) |
| 16 | `hokuto` | 北斗 | ✅ | ✅ |
| 17 | `ozora` | おおぞら | ✅ | ✅ |
| 18 | `kamui` | カムイ | ✅ | ✅ |
| 19 | `lilac` | ライラック | ✅ | ✅ |
| 20 | `sonic` | ソニック | ✅ | ✅ |
| 21 | `shirasagi` | しらさぎ | ✅ | ✅ |
| 22 | `kuroshio` | くろしお | ✅ | ✅ |
| 23 | `yakumo` | やくも | ✅ | ✅ |
| 24 | `shinano` | しなの | ✅ | ✅ |
| 25 | `hida` | ひだ | ✅ | ✅ |
| 26 | `nanki` | 南紀 | ✅ | ✅ |
| 27 | `kinosaki` | きのさき | ✅ | ✅ |
| 28 | `kounotori` | こうのとり | ✅ | ✅ |
| 29 | `kusatsu-shima` | 草津・四万 | ✅ | ✅ |
| 30 | `fuji` | 富士 | ✅ | ✅ |
| 31 | `nanpu` | 南風 | ✅ | ✅ |
| 32 | `ishizuchi` | いしづち | ✅ | ✅ |
| 33 | `midori` | みどり | ✅ | ✅ |
| 34 | `kirishima` | きりしま | ✅ | ✅ |
| 35 | `kirameki` | きらめき | ✅ | ✅ |
| 36 | `relay-kamome` | リレーかもめ | ✅ | ✅ |
| 37 | `inaho` | いなほ | ✅ | ✅ |
| 38 | `super-tsugaru` | スーパーつがる | ✅ | ✅ |
| 39 | `asoboy` | あそぼーい！ | ✅ | ✅ |
| 40 | `uzushio` | うずしお | ✅ | ✅ |
| 41 | `shiokaze` | しおかぜ | ✅ | ✅ |
| 42 | `soya` | 宗谷 | ✅ | ✅ |
| 43 | `super-oki` | スーパーおき | ✅ | ✅ |
| 44 | `rapit` | ラピートα | ✅ | ✅ |
| 45 | `new-red-arrow` | ニューレッドアロー | ✅ | ✅ (new-red-arrow.png) |
| 46 | `suzuran` | すずらん | ✅ | ✅ |
| 47 | `tokachi` | とかち | ✅ | ✅ |
| 48 | `sarobetsu` | サロベツ | ✅ | ✅ |
| 49 | `okhotsk` | オホーツク | ✅ | ✅ |
| 50 | `niseko` | ニセコ | ✅ | ✅ |
| 51 | `fuji-excursion` | 富士回遊 | ✅ | ✅ |
| 52 | `hachioji` | はちおうじ | ✅ | ✅ |
| 53 | `ome` | おうめ | ✅ | ✅ |
| 54 | `shonan` | 湘南 | ✅ | ✅ |
| 55 | `wakashio` | わかしお | ✅ | ✅ |
| 56 | `sazanami` | さざなみ | ✅ | ✅ |
| 57 | `shiosai` | しおさい | ✅ | ✅ |
| 58 | `akagi` | あかぎ | ✅ | ✅ |
| 59 | `nikko` | 日光 | ✅ | ✅ |
| 60 | `kinugawa` | きぬがわ | ✅ | ✅ |
| 61 | `spacia-nikko` | スペーシア日光 | ✅ | ✅ |
| 62 | `spacia-kinugawa` | スペーシアきぬがわ | ✅ | ✅ |
| 63 | `shirayuki` | しらゆき | ✅ | ✅ |
| 64 | `tsugaru` | つがる | ✅ | ✅ |
| 65 | `kamakura` | 鎌倉 | ✅ | ✅ |
| 66 | `inaji` | 伊那路 | ✅ | ✅ |
| 67 | `fujikawa` | ふじかわ | ✅ | ✅ |
| 68 | `hashidate` | はしだて | ✅ | ✅ |
| 69 | `maizuru` | まいづる | ✅ | ✅ |
| 70 | `hamakaze` | はまかぜ | ✅ | ✅ |
| 71 | `super-hakuto` | スーパーはくと | ✅ | ✅ |
| 72 | `super-inaba` | スーパーいなば | ✅ | ✅ |
| 73 | `super-matsukaze` | スーパーまつかぜ | ✅ | ✅ |
| 74 | `rakuraku-harima` | らくラクはりま | ✅ | ✅ |
| 75 | `rakuraku-biwako` | らくラクびわこ | ✅ | ✅ |
| 76 | `rakuraku-yamato` | らくラクやまと | ✅ | ✅ |
| 77 | `noto-kagaribi` | 能登かがり火 | ✅ | ✅ |
| 78 | `west-express-ginga` | WEST EXPRESS 銀河 | ✅ | ✅ |
| 79 | `hanaakari` | はなあかり | ✅ | ✅ |
| 80 | `mahoroba` | まほろば | ✅ | ✅ |
| 81 | `shimanto` | しまんと | ✅ | ✅ |
| 82 | `ashizuri` | あしずり | ✅ | ✅ |
| 83 | `uwakai` | 宇和海 | ✅ | ✅ |
| 84 | `tsurugisan` | 剣山 | ✅ | ✅ |
| 85 | `morning-exp` | モーニングEXP | ✅ | ✅ |
| 86 | `shikoku-mannaka-sennen-monogatari` | 四国まんなか千年ものがたり | ✅ | ✅ |
| 87 | `shikoku-tosa-jidai-no-yoake` | 志国土佐 時代の夜明けのものがたり | ✅ | ✅ |
| 88 | `iyonada-monogatari` | 伊予灘ものがたり | ✅ | ✅ |
| 89 | `nichirin` | にちりん | ✅ | ✅ |
| 90 | `nichirin-seagaia` | にちりんシーガイア | ✅ | ✅ |
| 91 | `hyuga` | ひゅうが | ✅ | ✅ |
| 92 | `huis-ten-bosch` | ハウステンボス | ✅ | ✅ |
| 93 | `kasasagi` | かささぎ | ✅ | ✅ |
| 94 | `yufu` | ゆふ | ✅ | ✅ |
| 95 | `yufuin-no-mori` | ゆふいんの森 | ✅ | ✅ |
| 96 | `kyushu-odan-tokkyu` | 九州横断特急 | ✅ | ✅ |
| 97 | `kawasemi-yamasemi` | かわせみ やませみ | ✅ | ✅ |
| 98 | `umisachi-yamasachi` | 海幸山幸 | ✅ | ✅ |
| 99 | `36-plus-3` | 36ぷらす3 | ✅ | ✅ |
| 100 | `a-ressha-de-iko` | A列車で行こう | ✅ | ✅ |
| 101 | `futatsuboshi-4047` | ふたつ星4047 | ✅ | ✅ |
| 102 | `aru-ressha` | 或る列車 | ✅ | ✅ |
| 103 | `fujisan` | ふじさん | ✅ | ✅ |
| 104 | `twilight-express-mizukaze` | TWILIGHT EXPRESS 瑞風 | ✅ | ✅ |
| 105 | `ibusuki-no-tamatebako` | 指宿のたまて箱 | ✅ | ✅ |
| 106 | `kaio` | かいおう | ✅ | ✅ |
| 107 | `kanpachi-ichiroku` | かんぱち・いちろく | ✅ | ✅ |
| 108 | `muroto` | むろと | ✅ | ✅ |
| 109 | `midnight-exp` | ミッドナイトEXP | ✅ | ✅ |
| 110 | `dinostar` | ダイナスター | ✅ | ✅ |
| 111 | `aso` | あそ | ✅ | ✅ |
| 112 | `ariake` | 有明 | ✅ | ✅ |
| 113 | `isaburo-shinpei` | いさぶろう・しんぺい | ✅ | ✅ |
| 114 | `taisetsu` | 大雪 | ✅ | ✅ |
| 115 | `shinjuku-sazanami` | 新宿さざなみ | ✅ | ✅ |
| 116 | `shinjuku-wakashio` | 新宿わかしお | ✅ | ✅ |
| 117 | `romancecar` | ロマンスカー | ✅ | ✅ |
| 118 | `hakone` | はこね | ✅ | ✅ |
| 119 | `super-hakone` | スーパーはこね | ✅ | ✅ |
| 120 | `sagami` | さがみ | ✅ | ✅ |
| 121 | `enoshima` | えのしま | ✅ | ✅ |
| 122 | `metro-hakone` | メトロはこね | ✅ | ✅ |
| 123 | `metro-enoshima` | メトロえのしま | ✅ | ✅ |
| 124 | `metro-sagami` | メトロさがみ | ✅ | ✅ |
| 125 | `morningway` | モーニングウェイ | ✅ | ✅ |
| 126 | `homeway` | ホームウェイ | ✅ | ✅ |
| 127 | `metro-morningway` | メトロモーニングウェイ | ✅ | ✅ |
| 128 | `metro-homeway` | メトロホームウェイ | ✅ | ✅ |
| 129 | `skyliner` | スカイライナー | ✅ | ✅ |
| 130 | `morning-liner` | モーニングライナー | ✅ | ✅ |
| 131 | `evening-liner` | イブニングライナー | ✅ | ✅ |
| 132 | `city-liner` | シティライナー | ✅ | ✅ |
| 133 | `kegon` | けごん | ✅ | ✅ |
| 134 | `kinu` | きぬ | ✅ | ✅ |
| 135 | `ryomo` | りょうもう | ✅ | ✅ |
| 136 | `spacia` | スペーシア | ✅ | ✅ |
| 137 | `shimotsuke` | しもつけ | ✅ | ✅ |
| 138 | `kirifuri` | きりふり | ✅ | ✅ |
| 139 | `yunosato` | ゆのさと | ✅ | ✅ |
| 140 | `urban-park-liner` | アーバンパークライナー | ✅ | ✅ |
| 141 | `skytree-liner` | スカイツリーライナー | ✅ | ✅ |
| 142 | `chichibu` | ちちぶ | ✅ | ✅ |
| 143 | `musashi` | むさし | ✅ | ✅ |
| 144 | `koedo` | 小江戸 | ✅ | ✅ |
| 145 | `laview` | ラビュー | ✅ | ✅ |
| 146 | `red-arrow` | レッドアロー | ✅ | ✅ |
| 147 | `urban-liner` | アーバンライナー | ✅ | ✅ |
| 148 | `ise-shima-liner` | 伊勢志摩ライナー | ✅ | ✅ |
| 149 | `sakura-liner` | さくらライナー | ✅ | ✅ |
| 150 | `vista-car` | ビスタカー | ✅ | ✅ |
| 151 | `ao-no-symphony` | 青の交響曲 | ✅ | ✅ |
| 152 | `southern` | サザン | ✅ | ✅ |
| 153 | `koya` | こうや | ✅ | ✅ |
| 154 | `rinkan` | りんかん | ✅ | ✅ |
| 155 | `semboku-liner` | 泉北ライナー | ✅ | ✅ |
| 156 | `mu-sky` | ミュースカイ | ✅ | ✅ |
| 157 | `kyo-train` | 京とれいん 雅洛 | ✅ | ✅ |
| 158 | `fujisan-tokkyu` | フジサン特急 | ✅ | ✅ |
| 159 | `fujisan-view-express` | 富士山ビュー特急 | ✅ | ✅ |
| 160 | `yukemuri` | ゆけむり | ✅ | ✅ |
| 161 | `snow-monkey` | スノーモンキー | ✅ | ✅ |
| 162 | `tango-relay` | たんごリレー | ✅ | ✅ |
| 163 | `tango-discovery` | タンゴディスカバリー | ✅ | ✅ |

## 二、停靠站模式数据库（135 条，通过 135）

| # | patternId | 列车 | 区分 | 停车站数 | 站名 | 站序 | 求解 | 验证 | 数据可信度 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `hida-nagoya-takayama` | ひだ | 名古屋〜高山・飛驒古川 | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | medium |
| 2 | `hida-nagoya-toyama` | ひだ | 名古屋〜富山 | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | medium |
| 3 | `hida-osaka-takayama` | ひだ | 大阪〜高山 | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | medium |
| 4 | `shinano-nagoya-nagano` | しなの | 名古屋〜長野 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | medium |
| 5 | `nanki-nagoya-kiikatsuura` | 南紀 | 名古屋〜紀伊勝浦 | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | high |
| 6 | `fujikawa-shizuoka-kofu` | ふじかわ | 静岡〜甲府 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | high |
| 7 | `nanpu-okayama-kochi` | 南風 | 岡山〜高知 | 12 | ✅ | ✅ | ✅ 11/11 | ✅ | high |
| 8 | `shimanto-takamatsu-kochi` | しまんと | 高松〜高知 | 12 | ✅ | ✅ | ✅ 11/11 | ✅ | high |
| 9 | `tsurugisan-tokushima-awaikeda` | 剣山 | 徳島〜阿波池田 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | high |
| 10 | `uzushio-takamatsu-tokushima` | うずしお | 高松〜徳島 | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | high |
| 11 | `uzushio-okayama-tokushima` | うずしお | 岡山〜徳島（2025年3月まで） | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | medium |
| 12 | `muroto-tokushima-mugi` | むろと | 徳島〜牟岐 | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | medium |
| 13 | `azusa-shinjuku-matsumoto` | あずさ | 新宿〜松本 | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | medium |
| 14 | `azusa-chiba-matsumoto` | あずさ | 千葉発着 | 15 | ✅ | ✅ | ✅ 14/14 | ✅ | low |
| 15 | `azusa-minamiotari` | あずさ | 南小谷延長 | 16 | ✅ | ✅ | ✅ 15/15 | ✅ | low |
| 16 | `kaiji-shinjuku-kofu` | かいじ | 新宿〜甲府/竜王 | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | high |
| 17 | `fuji-excursion-shinjuku-kawaguchiko` | 富士回遊 | 新宿〜河口湖 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | medium |
| 18 | `hachioji-tokyo-hachioji` | はちおうじ | 東京〜八王子 | 4 | ✅ | ✅ | ✅ 3/3 | ✅ | high |
| 19 | `ome-tokyo-ome` | おうめ | 東京〜青梅 | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | high |
| 20 | `hitachi-shinagawa-iwaki` | ひたち | 品川〜いわき | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | low |
| 21 | `hitachi-shinagawa-sendai` | ひたち | 品川〜仙台 | 16 | ✅ | ✅ | ✅ 15/15 | ✅ | medium |
| 22 | `tokiwa-shinagawa-katsuta` | ときわ | 品川〜勝田 | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | low |
| 23 | `tokiwa-shinagawa-takahagi` | ときわ | 品川〜高萩 | 15 | ✅ | ✅ | ✅ 14/14 | ✅ | low |
| 24 | `odoriko-tokyo-izukyushimoda` | 踊り子 | 東京〜伊豆急下田 | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | medium |
| 25 | `odoriko-tokyo-shuzenji` | 踊り子 | 修善寺 | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | medium |
| 26 | `saphir-odoriko-tokyo-izukyushimoda` | サフィール踊り子 | 東京〜伊豆急下田 | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | high |
| 27 | `shonan-tokyo-odawara` | 湘南 | 東京〜小田原 | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | medium |
| 28 | `shonan-shinjuku-odawara` | 湘南 | 新宿〜小田原(湘南新宿ライン) | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | medium |
| 29 | `narita-express-tokyo` | 成田エクスプレス | 東京発着 | 3 | ✅ | ✅ | ✅ 2/2 | ✅ | medium |
| 30 | `narita-express-shinjuku` | 成田エクスプレス | 新宿発着 | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | low |
| 31 | `narita-express-ikebukuro` | 成田エクスプレス | 池袋発着 | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | low |
| 32 | `narita-express-omiya` | 成田エクスプレス | 大宮発着 | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | low |
| 33 | `narita-express-yokohama` | 成田エクスプレス | 横浜発着 | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | medium |
| 34 | `narita-express-ofuna` | 成田エクスプレス | 大船発着 | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | medium |
| 35 | `kamakura-yoshikawaminami-kamakura` | 鎌倉 | 吉川美南〜鎌倉 | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | medium |
| 36 | `wakashio-tokyo-awakamogawa` | わかしお | 東京〜安房鴨川 | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | medium |
| 37 | `shinjuku-wakashio-shinjuku-awakamogawa` | 新宿わかしお | 新宿〜安房鴨川 | 14 | ✅ | ✅ | ✅ 13/13 | ✅ | medium |
| 38 | `sazanami-tokyo-kimitsu` | さざなみ | 東京〜君津 | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | medium |
| 39 | `shinjuku-sazanami-shinjuku-tateyama` | 新宿さざなみ | 新宿〜館山 | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | medium |
| 40 | `shiosai-tokyo-choshi` | しおさい | 東京〜銚子 | 12 | ✅ | ✅ | ✅ 11/11 | ✅ | medium |
| 41 | `akagi-ueno-takasaki` | あかぎ | 上野/新宿〜高崎/本庄 | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | medium |
| 42 | `kusatsu-shima-ueno-naganoharakusatsuguchi` | 草津・四万 | 上野〜長野原草津口 | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | high |
| 43 | `nikko-shinjuku-tobunikko` | 日光 | 新宿〜東武日光 | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | low |
| 44 | `kinugawa-shinjuku-kinugawaonsen` | きぬがわ | 新宿〜鬼怒川温泉 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | medium |
| 45 | `spacia-nikko-shinjuku-tobunikko` | スペーシア日光 | 新宿〜東武日光 | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | low |
| 46 | `spacia-kinugawa-shinjuku-kinugawaonsen` | スペーシアきぬがわ | 新宿〜鬼怒川温泉 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | low |
| 47 | `inaho-niigata-akita` | いなほ | 新潟〜秋田 | 16 | ✅ | ✅ | ✅ 15/15 | ✅ | medium |
| 48 | `shirayuki-niigata-joetsumyoko` | しらゆき | 新潟〜上越妙高/新井 | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | medium |
| 49 | `tsugaru-akita-aomori` | つがる | 秋田〜青森 | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | high |
| 50 | `super-tsugaru-akita-aomori` | スーパーつがる | 秋田〜青森（快速停車） | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | high |
| 51 | `hokuto-hakodate-sapporo` | 北斗 | 函館〜札幌 | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | medium |
| 52 | `suzuran-muroran-sapporo` | すずらん | 室蘭/東室蘭〜札幌 | 12 | ✅ | ✅ | ✅ 11/11 | ✅ | medium |
| 53 | `ozora-sapporo-kushiro` | おおぞら | 札幌〜釧路 | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | medium |
| 54 | `tokachi-sapporo-obihiro` | とかち | 札幌〜帯広 | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | medium |
| 55 | `kamui-sapporo-asahikawa` | カムイ | 札幌〜旭川 | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | high |
| 56 | `lilac-sapporo-asahikawa` | ライラック | 札幌〜旭川 | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | high |
| 57 | `soya-sapporo-wakkanai` | 宗谷 | 札幌〜稚内 | 15 | ✅ | ✅ | ✅ 14/14 | ✅ | medium |
| 58 | `sarobetsu-asahikawa-wakkanai` | サロベツ | 旭川〜稚内 | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | high |
| 59 | `okhotsk-sapporo-abashiri` | オホーツク | 札幌〜網走 | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | medium |
| 60 | `taisetsu-asahikawa-abashiri` | 大雪 | 旭川〜網走(2025年3月廃止前最終パターン) | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | high |
| 61 | `niseko-sapporo-hakodate` | ニセコ | 札幌〜函館(小樽・倶知安経由・季節列車) | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | medium |
| 62 | `sonic-hakata-oita` | ソニック | 博多〜大分 | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | low |
| 63 | `sonic-hakata-saiki` | ソニック | 博多〜佐伯 | 12 | ✅ | ✅ | ✅ 11/11 | ✅ | low |
| 64 | `nichirin-oita-miyazakikuko` | にちりん | 大分〜宮崎/宮崎空港 | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | medium |
| 65 | `nichirin-seagaia-hakata-miyazakikuko` | にちりんシーガイア | 博多〜宮崎空港 | 21 | ✅ | ✅ | ✅ 20/20 | ✅ | low |
| 66 | `hyuga-nobeoka-miyazakikuko` | ひゅうが | 延岡〜宮崎空港 | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | low |
| 67 | `kirishima-miyazaki-kagoshimachuo` | きりしま | 宮崎〜鹿児島中央 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | low |
| 68 | `relay-kamome-hakata-takeoonsen` | リレーかもめ | 博多〜武雄温泉 | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | low |
| 69 | `midori-hakata-sasebo` | みどり | 博多〜佐世保 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | low |
| 70 | `huis-ten-bosch-hakata-huistenbosch` | ハウステンボス | 博多〜ハウステンボス | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | low |
| 71 | `kasasagi-mojiko-hizenkashima` | かささぎ | 門司港〜肥前鹿島 | 14 | ✅ | ✅ | ✅ 13/13 | ✅ | low |
| 72 | `kirameki-mojiko-hakata` | きらめき | 門司港/小倉〜博多 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | low |
| 73 | `ariake-omuta-hakata` | 有明 | 大牟田〜博多（廃止時最終パターン） | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | medium |
| 74 | `kaio-nogata-hakata` | かいおう | 直方〜博多 | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | medium |
| 75 | `yufu-hakata-beppu` | ゆふ | 博多〜別府 | 14 | ✅ | ✅ | ✅ 13/13 | ✅ | high |
| 76 | `yufuin-no-mori-hakata-yufuin` | ゆふいんの森 | 博多〜由布院 | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | medium |
| 77 | `yufuin-no-mori-hakata-beppu` | ゆふいんの森 | 博多〜別府 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | medium |
| 78 | `kyushu-odan-tokkyu-beppu-kumamoto` | 九州横断特急 | 別府〜熊本 (2025年3月短縮ダイヤ) | 12 | ✅ | ✅ | ✅ 11/11 | ✅ | high |
| 79 | `aso-kumamoto-miyaji` | あそ | 熊本〜宮地 (2020-2025年最終パターン) | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | high |
| 80 | `asoboy-kumamoto-beppu` | あそぼーい！ | 熊本〜別府 (現行) | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | medium |
| 81 | `kawasemi-yamasemi-kumamoto-miyaji` | かわせみ やませみ | 熊本〜宮地 (現行) | 5 | ✅ | ✅ | ✅ 4/4 | ✅ | high |
| 82 | `umisachi-yamasachi-miyazaki-nango` | 海幸山幸 | 宮崎〜南郷 | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | medium |
| 83 | `36-plus-3-red-hakata-kagoshima-chuo` | 36ぷらす3 | 赤の路: 博多〜鹿児島中央 (木曜) | 5 | ✅ | ✅ | ✅ 4/4 | ✅ | low |
| 84 | `36-plus-3-black-kagoshima-chuo-miyazaki` | 36ぷらす3 | 黒の路: 鹿児島中央〜宮崎 (金曜) | 4 | ✅ | ✅ | ✅ 3/3 | ✅ | low |
| 85 | `36-plus-3-green-miyazaki-airport-beppu` | 36ぷらす3 | 緑の路: 宮崎空港〜別府 (土曜) | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | low |
| 86 | `36-plus-3-blue-oita-hakata` | 36ぷらす3 | 青の路: 大分〜博多 (日曜) | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | low |
| 87 | `36-plus-3-gold-hakata-sasebo` | 36ぷらす3 | 金の路: 博多〜佐世保 (月曜) | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | low |
| 88 | `a-ressha-de-iko-kumamoto-misumi` | A列車で行こう | 熊本〜三角 | 4 | ✅ | ✅ | ✅ 3/3 | ✅ | high |
| 89 | `futatsuboshi-4047-takeo-onsen-nagasaki-am` | ふたつ星4047 | 午前便: 武雄温泉〜長崎 (肥前浜経由) | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | medium |
| 90 | `futatsuboshi-4047-nagasaki-takeo-onsen-pm` | ふたつ星4047 | 午後便: 長崎〜武雄温泉 (新大村経由) | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | medium |
| 91 | `aru-ressha-hakata-yufuin` | 或る列車 | 由布院コース: 博多〜由布院 | 2 | ✅ | ✅ | ✅ 1/1 | ✅ | low |
| 92 | `ibusuki-no-tamatebako-kagoshima-chuo-ibusuki` | 指宿のたまて箱 | 鹿児島中央〜指宿 (2024年3月ノンストップ化後) | 2 | ✅ | ✅ | ✅ 1/1 | ✅ | high |
| 93 | `kanpachi-ichiroku-hakata-beppu` | かんぱち・いちろく | 博多〜別府 (久大本線経由、両方向) | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | medium |
| 94 | `isaburo-shinpei-kumamoto-yoshimatsu` | いさぶろう・しんぺい | 熊本/人吉〜吉松 (最終パターン) | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | high |
| 95 | `thunderbird-osaka-tsuruga` | サンダーバード | 大阪〜敦賀 | 4 | ✅ | ✅ | ✅ 3/3 | ✅ | high |
| 96 | `shirasagi-nagoya-tsuruga` | しらさぎ | 名古屋〜敦賀 | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | high |
| 97 | `shirasagi-maibara-tsuruga` | しらさぎ | 米原〜敦賀 | 2 | ✅ | ✅ | ✅ 1/1 | ✅ | high |
| 98 | `kuroshio-shinosaka-shirahama` | くろしお | 京都・新大阪〜白浜 | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | high |
| 99 | `kuroshio-shinosaka-shingu` | くろしお | 京都・新大阪〜新宮 | 17 | ✅ | ✅ | ✅ 16/16 | ✅ | high |
| 100 | `kounotori-shinosaka-kinosaki` | こうのとり | 新大阪〜城崎温泉 | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | high |
| 101 | `kinosaki-kyoto-kinosaki` | きのさき | 京都〜城崎温泉 | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | high |
| 102 | `hashidate-kyoto-amanohashidate` | はしだて | 京都〜天橋立 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | high |
| 103 | `hashidate-kyoto-toyooka` | はしだて | 京都〜豊岡（天橋立経由） | 16 | ✅ | ✅ | ✅ 15/15 | ✅ | medium |
| 104 | `maizuru-kyoto-higashimaizuru` | まいづる | 京都〜東舞鶴 | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | high |
| 105 | `hamakaze-osaka-hamasaka` | はまかぜ | 大阪〜浜坂 | 16 | ✅ | ✅ | ✅ 15/15 | ✅ | high |
| 106 | `hamakaze-osaka-tottori` | はまかぜ | 大阪〜鳥取 | 18 | ✅ | ✅ | ✅ 17/17 | ✅ | high |
| 107 | `super-hakuto-kyoto-kurayoshi` | スーパーはくと | 京都〜鳥取・倉吉 | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | high |
| 108 | `super-inaba-okayama-tottori` | スーパーいなば | 岡山〜鳥取 | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | high |
| 109 | `yakumo-okayama-izumoshi` | やくも | 岡山〜出雲市 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | medium |
| 110 | `haruka-kyoto-kansai-airport` | はるか | 京都〜関西空港 | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | high |
| 111 | `haruka-yasu-kansai-airport` | はるか | 野洲〜関西空港 | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | medium |
| 112 | `super-oki-tottori-shinyamaguchi` | スーパーおき | 鳥取/米子〜新山口 | 14 | ✅ | ✅ | ✅ 13/13 | ✅ | medium |
| 113 | `super-matsukaze-tottori-masuda` | スーパーまつかぜ | 鳥取〜益田 | 10 | ✅ | ✅ | ✅ 9/9 | ✅ | medium |
| 114 | `rakuraku-harima-kyoto-aboshi` | らくラクはりま | 京都/大阪〜網干 | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | high |
| 115 | `rakuraku-biwako-osaka-maibara` | らくラクびわこ | 大阪〜草津/米原 | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | high |
| 116 | `rakuraku-yamato-shinosaka-nara` | らくラクやまと | 新大阪〜奈良 | 7 | ✅ | ✅ | ✅ 6/6 | ✅ | medium |
| 117 | `dinostar-fukui-kanazawa` | ダイナスター | 福井〜金沢 | 5 | ✅ | ✅ | ✅ 4/4 | ✅ | high |
| 118 | `noto-kagaribi-kanazawa-wakuraonsen` | 能登かがり火 | 金沢〜和倉温泉 | 4 | ✅ | ✅ | ✅ 3/3 | ✅ | medium |
| 119 | `west-express-ginga-sanin` | WEST EXPRESS 銀河 | 京都〜出雲市（山陰ルート） | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | medium |
| 120 | `west-express-ginga-sanyo` | WEST EXPRESS 銀河 | 京都〜下関（山陽ルート） | 14 | ✅ | ✅ | ✅ 13/13 | ✅ | medium |
| 121 | `west-express-ginga-kinan` | WEST EXPRESS 銀河 | 紀南 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | medium |
| 122 | `hanaakari-current` | はなあかり | 大阪〜敦賀（2025年春コース） | 4 | ✅ | ✅ | ✅ 3/3 | ✅ | low |
| 123 | `mahoroba-osaka-nara` | まほろば | 大阪〜奈良 | 4 | ✅ | ✅ | ✅ 3/3 | ✅ | medium |
| 124 | `sunrise-izumo-tokyo-izumoshi` | サンライズ出雲 | 東京〜出雲市 | 17 | ✅ | ✅ | ✅ 16/16 | ✅ | medium |
| 125 | `sunrise-seto-tokyo-takamatsu` | サンライズ瀬戸 | 東京〜高松 | 12 | ✅ | ✅ | ✅ 11/11 | ✅ | medium |
| 126 | `mizukaze-sanin-course` | TWILIGHT EXPRESS 瑞風 | 山陰コース（京都/大阪〜下関） | 6 | ✅ | ✅ | ✅ 5/5 | ✅ | low |
| 127 | `mizukaze-sanyo-course` | TWILIGHT EXPRESS 瑞風 | 山陽コース（京都/大阪〜下関） | 5 | ✅ | ✅ | ✅ 4/4 | ✅ | low |
| 128 | `inaji-toyohashi-iida` | 伊那路 | 豊橋〜飯田 | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | medium |
| 129 | `shiokaze-okayama-matsuyama` | しおかぜ | 岡山〜松山 | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | high |
| 130 | `ishizuchi-takamatsu-matsuyama` | いしづち | 高松〜松山 | 13 | ✅ | ✅ | ✅ 12/12 | ✅ | medium |
| 131 | `ashizuri-kochi-nakamura` | あしずり | 高知〜中村 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | medium |
| 132 | `ashizuri-kochi-sukumo` | あしずり | 高知〜宿毛 | 11 | ✅ | ✅ | ✅ 10/10 | ✅ | medium |
| 133 | `uwakai-matsuyama-uwajima` | 宇和海 | 松山〜宇和島 | 8 | ✅ | ✅ | ✅ 7/7 | ✅ | high |
| 134 | `morning-exp-iyosaijo-takamatsu` | モーニングEXP高松 | 伊予西条〜高松 | 9 | ✅ | ✅ | ✅ 8/8 | ✅ | low |
| 135 | `morning-exp-niihama-matsuyama` | モーニングEXP松山 | 新居浜〜松山 | 5 | ✅ | ✅ | ✅ 4/4 | ✅ | low |
