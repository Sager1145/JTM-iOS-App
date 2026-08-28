# Taiwan line badges

Railprint uses these route-code badges before falling back to the operating
company mark. Branches that keep the same public line code intentionally share
one asset (for example, R and the Xinbeitou branch).

| Assets | Lines | Reference |
| --- | --- | --- |
| `trtc-bl.svg`, `trtc-r.svg`, `trtc-g.svg`, `trtc-o.svg`, `trtc-br.svg` | Taipei Metro BL/R/G/O/BR | Wikimedia Commons route symbols: [BL](https://commons.wikimedia.org/wiki/File:Taipei_Metro_Line_BL.svg), [R](https://commons.wikimedia.org/wiki/File:Taipei_Metro_Line_R.svg), [G](https://commons.wikimedia.org/wiki/File:Taipei_Metro_Line_G.svg), [O](https://commons.wikimedia.org/wiki/File:Taipei_Metro_Line_O.svg), [BR](https://commons.wikimedia.org/wiki/File:Taipei_Metro_Line_BR.svg) |
| `ntmetro-y.svg`, `ntmetro-v.svg`, `ntmetro-k.svg` | New Taipei Metro Y/V/K | Wikimedia Commons route symbols: [Y](https://commons.wikimedia.org/wiki/File:New_Taipei_Metro_Line_Y.svg), [V](https://commons.wikimedia.org/wiki/File:New_Taipei_Metro_Line_V_Danhai_LRT.svg), [K](https://commons.wikimedia.org/wiki/File:New_Taipei_Metro_Line_K.svg) |
| `tym-a.svg` | Taoyuan Metro A | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Taoyuan_Metro_Line_A.svg) |
| `tcmrt-g.svg` | Taichung Metro Green Line (`1` badge) | cleaned vector paths from the [Wikimedia Commons Green Line icon](https://commons.wikimedia.org/wiki/File:Taichung_Metro_Green_Line_icon.svg) |
| `krtc-r.svg`, `krtc-o.svg`, `krtc-c.svg` | Kaohsiung Metro R/O/C | clean route-code badges using official-package line colors; Commons references: [R](https://commons.wikimedia.org/wiki/File:Kaohsiung_Rapid_Transit_Red_Line.svg), [O](https://commons.wikimedia.org/wiki/File:Kaohsiung_Rapid_Transit_Orange_Line.svg), [C](https://commons.wikimedia.org/wiki/File:Kaohsiung_Rapid_Transit_Circular_Line.svg) |

The route symbols and trademarks remain the property of their respective
owners. Wikimedia assets retain the licenses stated on their file pages.

# Japan line badges

| Asset | Line | Reference |
| --- | --- | --- |
| `tokyo-metro-marunouchi-branch.svg` | Tokyo Metro Marunouchi branch line (`Mb`) | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Logo_of_Tokyo_Metro_Marunouchi_branch_Line.svg) |

## Shinkansen

JR publishes no per-route Shinkansen symbol. The mark passengers see on
signage is the operating company's own Shinkansen pictogram, and the route
itself is identified by its line colour and name. The popup therefore gives
every Shinkansen railway the official pictogram of the company that runs it,
instead of the JR company mark the operator fallback would otherwise supply.
Railways sharing an operator share a pictogram, and the two operator records
of the 北陸新幹線 each follow the company running that half.

The Japan package ships raster copies of these same five pictograms, but that
art stays outside the audited line-badge set — an operator pictogram is not a
route badge — so each railway is pointed at the vector original stored here.
Every file is the Commons asset kept byte for byte: no recolour, crop or
redraw. A popup test hashes all five so later edits cannot silently alter the
operators' artwork.

| Asset | Operator | Railways | Reference |
| --- | --- | --- | --- |
| `shinkansen-jr-hokkaido.svg` | JR北海道 | 北海道新幹線 | [Commons File:Shinkansen jrh.svg](https://commons.wikimedia.org/wiki/File:Shinkansen_jrh.svg), CC BY-SA 4.0 by KANAO22 |
| `shinkansen-jr-east.svg` | JR東日本 | 東北新幹線, 上越新幹線, 北陸新幹線 (JR東日本 segment) | [Commons File:Shinkansen jre.svg](https://commons.wikimedia.org/wiki/File:Shinkansen_jre.svg), CC BY-SA 4.0, vector by Carnby and Perhelion |
| `shinkansen-jr-central.svg` | JR東海 | 東海道新幹線 | [Commons File:Shinkansen jrc.svg](https://commons.wikimedia.org/wiki/File:Shinkansen_jrc.svg), CC BY-SA 4.0 by KANAO22 |
| `shinkansen-jr-west.svg` | JR西日本 | 山陽新幹線, 北陸新幹線 (JR西日本 segment) | [Commons File:Shinkansen jrw.svg](https://commons.wikimedia.org/wiki/File:Shinkansen_jrw.svg), CC BY-SA 4.0, credited to 西日本旅客鉄道 |
| `shinkansen-jr-kyushu.svg` | JR九州 | 九州新幹線, 西九州新幹線 | [Commons File:Shinkansen jrk.svg](https://commons.wikimedia.org/wiki/File:Shinkansen_jrk.svg), CC BY-SA 4.0 by Mliu92 |

# Hong Kong Light Rail route badges

The `mtr-lr-*.svg` badges reproduce the official Light Rail route numbers and
the route colours published by MTR's journey-planner payload. Heavy-rail lines
do not receive fabricated route-letter badges: they correctly fall back to the
official MTR company emblem in `../operator-logos/mtr-badge.png`.

Reference: <https://www.mtr.com.hk/en/customer/jp/index.php>

# Korea line badges

Korea was the largest branding gap in the app: all 82 rows of `../kr-2025.json`
resolved to no mark at all. Forty-seven of them do have an official route
symbol, and the `kr-*.svg` assets below are those symbols, taken from Wikimedia
Commons unchanged — no recolour, crop or redraw, the same rule the Shinkansen
pictograms follow. Every badge is a filled disc carrying a white glyph, except
대구's three lines and the 안심~하양 extension, whose published symbol is a
rounded square, and 수인·분당선, whose glyph is black on yellow. Rows that are a
through-service, a branch or an extension of another line share that line's
asset rather than a copy of it, because that is the badge on the platform: 경인선
runs as 1호선, 안산·과천·진접 as 4호선, 하남선 and 마천지선 as 5호선, 용산선 as
경의·중앙선, and so on.

Where Commons carries two versions of a symbol, these files take the newer
`<Name> Line.svg` family, which matches the colours published in the operators'
own line-colour tables. The older `Seoul Metro Line <Name>.svg` family does not:
its 경춘선 icon is filled with the 경의·중앙선 green, and its 신분당선 is `#DB0029`
against a published `#D4003B`.

Nine badges have no newer version to prefer. Commons publishes exactly one SVG
route symbol for 서울 지하철 1호선 through 9호선, and every one of them is a few
percent off the operator's published value — `#0D3692` against `#0052A4` for
1호선, `#33A23D` against `#00A84D` for 2호선, and so on down the line. They are
kept because they are the genuine symbol in the correct shape with the correct
numeral, and a hand-corrected fill would no longer be the Commons asset; the
alternative was leaving the country's nine busiest lines with no mark. AREX
(`#3681B7` against `#0090D2`), 인천 1호선 and 에버라인 sit in the same position.

| Assets | Lines | Reference |
| --- | --- | --- |
| `kr-seoul-1.svg` … `kr-seoul-9.svg` | 서울 지하철 1–9호선, plus 경인선 (1), 신정지선 and 성수지선 (2), 일산선 (3), 안산선·과천선·진접선 (4), 하남선·마천지선 (5), 별내선 (8) | Commons [File:Seoul Metro Line 1.svg](https://commons.wikimedia.org/wiki/File:Seoul_Metro_Line_1.svg) through [File:Seoul Metro Line 9.svg](https://commons.wikimedia.org/wiki/File:Seoul_Metro_Line_9.svg), CC BY-SA 4.0 by Jyg1093 |
| `kr-gyeongui-jungang.svg` | 경의선, 용산선 | [Commons File:Gyeongui-Jungang Line.svg](https://commons.wikimedia.org/wiki/File:Gyeongui-Jungang_Line.svg), CC BY-SA 4.0 by Jyg1093 |
| `kr-gyeongchun.svg` | 경춘선 | [Commons File:Gyeongchun Line.svg](https://commons.wikimedia.org/wiki/File:Gyeongchun_Line.svg), CC BY-SA 4.0 by Jyg1093 |
| `kr-suin-bundang.svg` | 수인선, 분당선 | [Commons File:Suin-Bundang Line.svg](https://commons.wikimedia.org/wiki/File:Suin-Bundang_Line.svg), CC BY-SA 4.0 by Tcfc2349 |
| `kr-donghae.svg` | 동해본선, 동해선 | [Commons File:Donghae Line.svg](https://commons.wikimedia.org/wiki/File:Donghae_Line.svg), CC BY-SA 4.0 by Jyg1093 |
| `kr-arex.svg` | 인천국제공항선 | [Commons File:Seoul Metro Line Arex.svg](https://commons.wikimedia.org/wiki/File:Seoul_Metro_Line_Arex.svg), CC BY-SA 4.0 by Chugun |
| `kr-sinbundang.svg` | 신분당선 | [Commons File:Shinbundang Line.svg](https://commons.wikimedia.org/wiki/File:Shinbundang_Line.svg), CC BY-SA 4.0 by Jyg1093 |
| `kr-gtx-a.svg` | 수도권광역급행철도 A선 | [Commons File:GTX-A Logo.svg](https://commons.wikimedia.org/wiki/File:GTX-A_Logo.svg), public domain, credited to GTX-A and SGRail Co., Ltd. |
| `kr-uisinseol.svg` | 우이신설선 | [Commons File:Seoul Metro Line Ui LRT.svg](https://commons.wikimedia.org/wiki/File:Seoul_Metro_Line_Ui_LRT.svg), CC BY-SA 4.0 by Tcfc2349 |
| `kr-sillim.svg` | 서울 경전철 신림선 | [Commons File:Seoul Metro Line Sillim Line.svg](https://commons.wikimedia.org/wiki/File:Seoul_Metro_Line_Sillim_Line.svg), CC BY-SA 4.0 by Tcfc2349 |
| `kr-gimpo-gold.svg` | 김포 골드라인 | [Commons File:Seoul Metro Line Gimpo Goldline.svg](https://commons.wikimedia.org/wiki/File:Seoul_Metro_Line_Gimpo_Goldline.svg), CC BY-SA 4.0 by Tcfc2349 |
| `kr-everline.svg` | 용인경전철 | [Commons File:Seoul Metro Line EverLine.svg](https://commons.wikimedia.org/wiki/File:Seoul_Metro_Line_EverLine.svg), CC0 by Chugun |
| `kr-uijeongbu-u.svg` | 의정부경전철 | [Commons File:Seoul Metro Line U Line.svg](https://commons.wikimedia.org/wiki/File:Seoul_Metro_Line_U_Line.svg), CC0 by Chugun |
| `kr-busan-1.svg` … `kr-busan-4.svg` | 부산 도시철도 1–4호선 | Commons [File:Busan Metro Line 1.svg](https://commons.wikimedia.org/wiki/File:Busan_Metro_Line_1.svg) through [File:Busan Metro Line 4.svg](https://commons.wikimedia.org/wiki/File:Busan_Metro_Line_4.svg), CC BY-SA 4.0 by Jyg1093 |
| `kr-busan-gimhae.svg` | 부산김해경전철 | [Commons File:Busan-Gimhae Line.svg](https://commons.wikimedia.org/wiki/File:Busan-Gimhae_Line.svg), CC BY-SA 4.0 by Tcfc2349 |
| `kr-daegu-1.svg`, `kr-daegu-2.svg`, `kr-daegu-3.svg` | 대구 도시철도 1–3호선, plus 안심~하양 복선전철 (1) | Commons [File:Daegu Metro Line 1.svg](https://commons.wikimedia.org/wiki/File:Daegu_Metro_Line_1.svg) through [File:Daegu Metro Line 3.svg](https://commons.wikimedia.org/wiki/File:Daegu_Metro_Line_3.svg), CC BY-SA 4.0 by Jyg1093 |
| `kr-incheon-1.svg`, `kr-incheon-2.svg` | 인천 도시철도 1–2호선 | Commons [File:Incheon Metro Line 1.svg](https://commons.wikimedia.org/wiki/File:Incheon_Metro_Line_1.svg), [File:Incheon Metro Line 2.svg](https://commons.wikimedia.org/wiki/File:Incheon_Metro_Line_2.svg), CC BY-SA 4.0 by Jyg1093 |
| `kr-gwangju-1.svg` | 광주 도시철도 1호선 | [Commons File:Gwangju Metro Line 1.svg](https://commons.wikimedia.org/wiki/File:Gwangju_Metro_Line_1.svg), CC BY-SA 4.0 by Tcfc2349 |
| `kr-daejeon-1.svg` | 대전 도시철도 1호선 | [Commons File:Daejeon Metro Line 1.svg](https://commons.wikimedia.org/wiki/File:Daejeon_Metro_Line_1.svg), CC BY-SA 4.0 by Jyg1093 |

Thirty-five rows deliberately get no route badge and fall through to the
operating company's mark. Thirty-three of them are intercity, high-speed,
freight, connector or depot lines — 경부선, 호남선, 전라선, 중앙선, 태백선,
가야선, 병점기지선 and the like — or tourist attractions such as 해운대 해변열차,
월미바다열차 and 죽변해안스카이레일, and airport people movers: none of these
carry a passenger-facing route symbol, so inventing one would say something
their operators do not. 경강선 and 서해선 are held back for a different reason.
Commons does publish a badge for each, but it belongs to the commuter section
only, while the package draws the full intercity corridor; putting a commuter
badge on a line that runs to 강릉 would overstate its scope.

The route symbols and trademarks remain the property of their respective
owners. Wikimedia assets retain the licenses stated on their file pages.
