# Japan operational corridors: evidence and coverage

Catalog check date 2026-10-02; targeted historical repairs 2026-10-10. Resource: `ios/RailKit/Sources/RailCore/Resources/japan-through-services.json`.

This catalog contains 182 operational corridor records (176 before the 2026-11-05 feasibility audit below). It is partial. “Checked” describes the listed records in a region; it does not certify all operators, branches, endpoints or historical periods. Unlisted services and dates without sufficient evidence remain unknown. It has no timetable guarantee that a passenger can ride a particular departure without changing trains.

Each record names physical line IDs from `app/public/rail/jp-2025.json` and station anchors. Operational records are display corridors, not physical search edges. In the trip editor a dated record does let one train continue between its consecutive legs at their anchor station (see the feasibility rule below). Shared row membership, identical station codes or an ordinary interchange do not establish track connectivity. Current physical identities and geometry do not prove their historical operator identity.

The oldest locally documented N02 observation is [1996-12-31](https://nlftp.mlit.go.jp/ksj/old/meta/N02/N02-07L/KS-META-N02-07L-2K.htm), despite the archive's H7 label. `historicalTargetFrom` records that review target; `coverageFrom: 2005-01-01` remains the separate inventory coverage floor. Neither field is a service opening date.

## Targeted historical repairs — 2026-10-10

- [Tobu history](https://www.tobu.co.jp/corporation/history/fhistory07.html): Kuki extension is 2006-03-18, correcting the prior 2003 claim. The [Tokyu announcement](https://www.tokyu.co.jp/image/news/pdf/020829.pdf) and [Metro history](https://www.tokyometro.jp/corporate/profile/history/index.html) support the Minami-Kurihashi corridor from 2003-03-19.
- [Tokyu's 2001 announcement](https://www.tokyu.co.jp/company/news/pdf/010221.pdf): Mita–Musashi-Kosugi from 2000-09-26 and Urawa-Misono–Musashi-Kosugi from 2001-03-28. Hiyoshi stays a separately dated 2008 extension. Metro history supports Yurakucho–Seibu Hanno from 1998-03-26.
- [Noseden history](https://noseden.hankyu.co.jp/100th/history.html): Nissei-Chuo–Hankyu Umeda from 1997-11-17. [Sanyo history](https://www.sanyo-railway.co.jp/company/history.html): Himeji–Hanshin Umeda from 1998-02-15. [Nagoya history](https://www.kotsu.city.nagoya.jp/rp/about/trp0004819.htm): Kamiiida/Komaki through operation from 2003-03-27, with the initial Inuyama endpoint still requiring evidence.
- [Kyoto chronology](https://www.city.kyoto.lg.jp/kotsu/page/0000219240.html): the complete Kokusaikaikan–Kintetsu Nara corridor begins 2000-03-15; the older Kitaoji–Shin-Tanabe corridor is not represented by that whole path. [Kyoto's extension announcement](https://www.city.kyoto.lg.jp/kotsu/page/0000024682.html) and [chronology PDF](https://www.city.kyoto.lg.jp/kotsu/cmsfiles/contents/0000073/73257/05_sonota03.pdf) establish Keishin's city-hall terminus before the 2008-01-16 Uzumasa extension. The record now splits at Kyoto Shiyakusho-mae; 2004-11-26 was an unrelated eastern extension.
- [Odakyu's 2018 diagram announcement](https://www.odakyu.jp/news/o5oaa10000005s29-att/o5oaa10000005s2g.pdf) and [Metro's confirmed revision date](https://www.tokyometro.jp/news/2017/190856.html): split the Isehara extension at Hon-Atsugi from 2018-03-17, preserving the earlier shorter corridor.
- [Keikyu chronology](https://www.keikyu.co.jp/history/chronology07.html): Narita–Haneda airport through operation from 1998-11-18; this does not date other Keikyu endpoints.
- Six previously reviewed workbench onset constraints are now in the production catalog: the two Shonan-Shinjuku branches (2001-12-01), the two Gakkentoshi–Tozai branches (1997-03-08), Komachi (1997-03-22), and Hakutaka (1997-03-22). Their `historicalReview` evidence is explicitly limited to service opening; unproven initial outer endpoints remain flagged.

`legVariants` stores ordered indices into one shared `legs` array, with source URLs, notes and half-open periods. It is required when alternate legs would otherwise produce a new interior adjacency by filtering. Haruka's existing pre/post-2021 choices are now explicit. Its pre-2005 footprint, pandemic suspensions and missing Umeda freight geometry are unresolved, so those variants do not certify complete operation on every day. An unmatched, overlapping or malformed variant returns no path.

## Official evidence

- [Rinkai Line official timetable](https://www.twr.co.jp/chtw/tabid/270/Default.aspx) lists Kawagoe-bound trains and shorter workings via Osaki and the Saikyo Line; the [JR East Tokyo suburban network map](https://www.jreast.co.jp/map/pdf/map_tokyo.pdf) identifies the Saikyo/Kawagoe corridor. Added 2026-10-04: Shin-Kiba–Osaki–Ikebukuro–Akabane–Omiya–Kawagoe, using the Tohoku row via Musashi-Urawa. Reversed stored row order is expressed with from/to station anchors, without a separate physical reverse row. Stopping patterns are not modeled.
- [JR East Tokyo suburban network map](https://www.jreast.co.jp/map/pdf/map_tokyo.pdf) and [current map index](https://www.jreast.co.jp/map/): JK Keihin-Tohoku/Negishi, JS Shonan-Shinjuku and JO Sobu Rapid/Yokosuka. JK uses the surface Tohoku/Tokaido corridor and Negishi. JS uses the Shinjuku/Osaki/Musashi-Kosugi corridor, with separate Utsunomiya–Zushi and Takasaki–Odawara patterns. The surveyed Yamate, Akabane and Osaki branch rows represent the corridor geometry; they do not claim JS stops at every intermediate station.
- [Tokyo Metro 2025 fact book, through operation table](https://www.tokyometro.jp/corporate/ir/library/factbook/pdf/factbook_2025.pdf): partner networks for Hibiya, Tozai, Chiyoda, Yurakucho, Hanzomon, Namboku and Fukutoshin. The table’s snapshot is 2025-03-31. Records cover representative corridors through those connections. [Sotetsu/Tokyu network announcement](https://www.tokyometro.jp/news/2022/214156.html) establishes the Shin-Yokohama connection; one anchored Sotetsu–Tokyu–Namboku–Saitama corridor is included.
- [Toei Asakusa through-running map](https://www.kotsu.metro.tokyo.jp/subway/map/asakusa_sogo.html) and [current Toei Asakusa operator list](https://www.kotsu.metro.tokyo.jp/subway/schedule/asakusa.html): Keisei, Keikyu and Hokuso connections. This catalog includes Keisei Main Line and Narita Sky Access routes to Haneda via Aoto, Oshiage, Sengakuji and Keikyu Kamata. Hokuso branches remain a gap.
- [Toei Shinjuku through-running map](https://www.kotsu.metro.tokyo.jp/subway/map/shinjuku_sogo.html): representative Keio Sagamihara corridor through Shinjuku, Sasazuka and Chofu.
- [Nagoya Tsurumai first/last trains](https://kotsu.city.nagoya.jp/jp/trp_redirect.html?trp=trp0000190): through trains to Toyotashi. [Meitetsu Inuyama train location guide](https://top.meitetsu.co.jp/trainlocation/TrainRunningPositionIY.aspx) identifies Tsurumai through trains; [Meitetsu timetable index](https://www.meitetsu.co.jp/train/timetable/) explicitly groups Komaki and Kamiiida between Inuyama and Heian-dori. Inuyama and Toyota branches are separate records, avoiding a claim that all combinations have through trains.
- [Osaka Metro mutual-operation connections](https://subway.osakametro.co.jp/guide/fare/various_fares/mutual_price/price_sogo.php/1000): Esaka/Kita-Osaka, Nagata/Kintetsu Keihanna and Tenjimbashisuji-Rokuchome/Hankyu Senri/Kyoto. Records include current Minoh-Kayano and Yumeshima inventory endpoints. Kyoto branch is conservatively anchored at Takatsukishi.
- [Kyoto City subway route and timetable FAQ](https://www.city.kyoto.lg.jp/kotsu/page/0000204847.html): Karasuma/Kintetsu Kyoto and Tozai/Keihan Keishin direct operations. Representative endpoints are Shin-Tanabe and Biwako-Hamaotsu.
- [Fukuoka City 2025 subway business overview](https://subway.city.fukuoka.lg.jp/subway/about/pdf/subway_all.pdf): Airport Line/Chikuhi through trains to Karatsu. The explicit Nishitetsu transfer at Kaizuka does not establish through-running.

- [Hanshin current railway business overview](https://www.hanshin.co.jp/company/division/) explicitly identifies Osaka-Umeda–Sanyo-Himeji and Kobe-Sannomiya–Kintetsu-Nara through operations. [Sanyo through express timetable](https://www.sanyo-railway.co.jp/railway/express.html) independently confirms the western corridor. The Nara corridor uses the exact Namba/Osaka/Nara physical rows, joining at Osaka-Namba, Osaka-Uehommachi and Fuse.
- [Sotetsu railway business overview](https://www.sotetsu.co.jp/about/companies/transportation/) and [JR East operational line directory](https://www.jreast.co.jp/estation/facility_search.aspx?searchCategoryCd=1): representative Ebina–Shinjuku JR through corridor via Hazawa-Yokohama-Kokudai, Musashi-Kosugi, Nishi-Oi and Osaki.
- [JR Hokkaido Airport service](https://www.jrhokkaido.co.jp/airport/index.html): Otaru–Sapporo–New Chitose through rapid corridor, physically joining Hakodate and Chitose rows at Shiroishi and the airport branch at Minami-Chitose.
- [JR East Senzan explanation](https://media.jreast.co.jp/articles/4759) explicitly states that Senzan trains continue from Uzen-Chitose to Yamagata on the Ou Main Line. [Haranomachi October 2026 official timetable](https://timetables.jreast.co.jp/2610/timetable/tt1259/1259010.html) identifies ordinary trains with Sendai as their destination; the corridor joins at Iwanuma. [Sendai Airport Transit FAQ](https://www.senat.co.jp/question) explicitly establishes direct trains to Sendai, joining the Tohoku row at Natori.
- [JR Shikoku Marine Liner](https://www.jr-shikoku.co.jp/01_trainbus/vehicle-info/marine.html): Okayama–Takamatsu corridor over Uno and Honshi-Bisan rows with exact joins at Chayamachi, Kojima and Utazu. [Tokushima current station timetable](https://www.jr-shikoku.co.jp/01_trainbus/jikoku/pdf/tokushima.pdf) lists Naruto trains; physical Naruto and Kotoku rows join at Ikenotani.
- [JR Kyushu March 2026 Nippo/Miyazaki Airport timetable](https://www.jrkyushu.co.jp/byarea/kagoshima/info/__icsFiles/afieldfile/2026/03/12/nippo.miyazakiairport.pdf): through trains between Nobeoka and Miyazaki Airport across the Nippo, Nichinan and airport physical rows, joining at Minami-Miyazaki and Tayoshi. This conservatively models one evidenced corridor rather than every northern train origin.

## Remaining evidence gaps

100 of 176 patterns still lack an explicit opening boundary. An absent date means the recorded scope may predate the 2005 inventory; it does not establish existence in 1996. Additional historical endpoint patterns, withdrawals, temporary suspensions and operator transfers remain to be researched. Particular unresolved cases include Tama/Chiyoda interruptions, older Karasuma–Kintetsu endpoints, Haruka suspensions, Hakutaka's initial outer endpoints and the retired conventional Kaikyo corridor absent from the current package.

Corridor slicing preserves ordered station occurrences and checks available geometry and allowed traversal directions. It supplies physical intermediate visits, not a timetable-derived stopping list. Actual single-seat departures and complete historical coverage require dated evidence; operational continuity must never fill a physical geometry gap.

## Inspection-driven repair, 2026-10-10

The Catalyst inspection report covered 176 records and 103 temporal boundary samples. It flagged an unspecified start for `odakyu-jr-asagiri-numazu`. [Odakyu’s official chronology](https://www.odakyu.jp/company/history/) explicitly dates Shinjuku–Numazu mutual through operation to 1991-03-16; this onset and these outer endpoints are now encoded. The existing exclusive 2012-03-17 end is retained. This does not prove every stop, daily timetable or physical connection. At that first inspection stage, explicit starts covered 56 of 176 records; 120 remained unspecified.

The report also found missing source attribution on all three display connectors. Their already recorded service/physical-registry sources are now linked through `sourceURLs` and `physicalJunctionID`, with a limited `sourceScope`. The detector still treats physical passage and historical applicability as unresolved; linking an existing source does not certify its content or create geometry. The JR East PDF and Seibu page were unavailable through the web reader in this session; their retained catalog/registry references were reused, without a new content-verification claim.


### Automatic continuation: dated paths, one-day suspensions and surveyed connections

The 2026-10-10 continuation adds exact Rinkai Shin-Kiba–Kawagoe onset (JR East's 2002-12-01 revision timetable), the 2008 Fukutoshin northern corridors ending at Shibuya and their 2013 southern extensions, and Tozai–Sobu's documented Mitaka–Tsudanuma onset. Hibiya's 1988 Kikuna endpoint constraint is separated from its 2013 Naka-Meguro–Minami-Kurihashi replacement. Corridor joins do not promise one single-seat train across every outer endpoint.

Airport and endpoint opening constraints remain explicitly incomplete: Fukuoka Airport 1993-03-03, Miyazaki Airport 1996-07-18, Nankai Airport line 1994-06-15, Izumi-Chuo 1995-04-01, Kami-Otai 1993-08-12 and Hokushin mutual operation 1988-04-02. Current operator IDs do not establish predecessor identities. Nankai Rapi:t's actual 1994-09-04 debut replaces the incorrect conflation with the airport line's June opening.

JR West's [construction notice](https://www.westjr.co.jp/press/article/items/221209_00_press_senrokirikae.pdf) specifies Haruka's complete 2023-02-12 suspension and Kuroshio's Tennoji short-turn operation. Sparse ordered variants reuse the normal legs, encode the bounded full suspension explicitly, and resume normal selection on 2023-02-13. Haruka's unverified claim that all Maibara services stopped on 2020-04-24 is withdrawn.

Four Osaka Loop display legs now carry a source-attributed forward traversal of the current package's station order, selecting Nishikujo rather than the eastern arc and correctly wrapping from Kyobashi. Rapid direction comes from [JR West's 2015 revision](https://www.westjr.co.jp/press/article/items/141219_00_honsya.pdf); express western passage comes from the construction notice. This selects the current physical-base display proxy and does not reconstruct historical freight-line geometry. The absent Umeda freight line and historical geometry limits remain open.


The additional regional packet records six named-service/operator opening constraints: Odoriko 1981-10-01, Super Hakuto 1994-12-03, Ibara 1999-01-11, Wakasa 1987-10-14 and Nishikigawa 1987-07-25. Their initial full outer endpoints remain explicitly unconfirmed. Super Inaba's erroneous 1994 opening assertion is replaced by the operator's month-precision predecessor (1997-11) and named-service (2003-10) chronology. Sunrise's competing official July 10/11 extracts and Hashidate's unresolved exact historical boundaries remain unknown. The current count is 76 explicit starts and 100 unspecified starts among 176 records; explicit starts include limited opening constraints and do not certify complete history. Evidence packets are retained in `ios/ThroughWorkbench/Reports/Evidence`.


## Feasibility audit — 2026-11-05

The trip editor uses one rule, `TripConnectivity.link` (`ios/RailKit/Sources/RailCore/Routing/TripConnectivity.swift`), for whole-trip plans and for line changes at a via. One train continues from row A onto row B at station S on the ride date only through:

- a reviewed physical junction in `app/data/physical-rail-junctions.json` that names exactly A and B at S, cites evidence, and is valid on that date (a cross-identity `endJunction` also needs same-train evidence, as in the route graph), or
- a dated record here whose consecutive legs continue from A onto B at S.

Anything else is a transfer. That covers a shared N02 group code such as 浅草 003522 (Ginza, Asakusa and Tobu), a crossing without a station, a nearby station of another operator, and a shared name. A transfer is never planned as one train; the editor shows its existing "not connected" notice.

Before this audit the editor planner did not read the junction registry. Real single-train trips across reviewed junctions were therefore refused, such as 東京→博多 at 新大阪 or 東京→金沢 at 大宮, 高崎 and 上越妙高.

Records added in this audit (all `throughRunning`, onset constraint only, stopping patterns not modelled):

| id | Corridor | validFrom | Sources |
|---|---|---|---|
| `tokaido-sanyo-shinkansen` | 東京–新大阪–博多 | 1975-03-10 (岡山–博多 opening) | [Kyoto Railway Museum, Sanyo Shinkansen 50th](https://www.kyotorailwaymuseum.jp/pdf/sanyo_shinkansen_50th.pdf); ja.wikipedia 山陽新幹線. Physical junction `shin-osaka-tokaido-sanyo`. |
| `sanyo-kyushu-shinkansen` | 新大阪–博多–鹿児島中央 | 2011-03-12 | [JR Kyushu history](https://www.jrkyushu.co.jp/company/info/history/history05.html); junction `west-hakata` (2011-03-12). |
| `joetsu-shinkansen-tokyo` | 東京–大宮–新潟 | 1991-06-20 (Tokyo terminal) | ja.wikipedia 上越新幹線 (secondary); junction `omiya-joetsu-tohoku`. The 1985–1991 Ueno terminal is outside the Tokyo–Ueno row and is not a record. |
| `hokuriku-shinkansen-tsuruga` | 東京–大宮–高崎–上越妙高–敦賀 | 2024-03-16 (敦賀 extension) | [JR East/JR West 2025 press PDF](https://www.jreast.co.jp/press/2024/20250228_ho03.pdf) (search summary only); ja.wikipedia 北陸新幹線. For earlier rides the junction dates (`takasaki-joetsu-hokuriku` 1997-10-01, `joetsu-myoko-hokuriku-east-hokuriku-west` 2015-03-14) still let the planner route. |
| `toyoko-minatomirai` | 渋谷–横浜–元町・中華街 | 2004-02-01 | [Tokyu Toyoko history](https://www.tokyu.co.jp/railway/train-history/ty/) (February 2004); [Tokyu 100-year history ch. 7](https://www.tokyu.co.jp/history/chapter07_2_2/). Before this audit only the post-2013 Fukutoshin corridors existed. |
| `denentoshi-hanzomon` | 長津田–渋谷–青山一丁目 | 1978-08-01 | [Tokyu 100-year history ch. 5](https://www.tokyu.co.jp/history/chapter05_2_1): 「1978（昭和53）年8月1日に田園都市線・新玉川線・半蔵門線3線の相互直通運転が開始」. The outer endpoints are limited to the stations that existed in 1978. |

Several operator sites refused the reader in this session (JR Central, JR East PDFs, Tokyo Metro history). Where a date comes from a secondary source, the table says so.

Researched but not encoded:

- Kaikyo and Hakucho via the Seikan conventional line (1988–2016): the line is not in the package.
- Hokuso–Shin-Keisei (1991–1992): low confidence.
- Asa Kaigan–Mugi, Matsuura–Sasebo and Aichi Loop–Chuo: low confidence.
- Hokuetsu Express to Echigo-Yuzawa: the end with the 2023-03-18 revision is inferred, not stated, so `validTo` is unchanged.
- Wakasa–Inbi to Tottori: still running. 2020-03-14 ended only JR rolling stock on the line, so no end was added.

Other regions, for later: Korail ↔ Seoul Metro through running on lines 1, 3 and 4; the Hong Kong intercity through train (suspended 2020). Taiwan and Macau have no cross-operator through running.
