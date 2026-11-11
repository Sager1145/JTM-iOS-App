# Operator English names: conventions and sources

Applies to `ios/RailKit/Sources/RailCore/Resources/operator-english-names.json`
(identity code → English display label). Identity codes are the ones in
`operator-identities.json`, which every registry-bundle operator record points
to through its `identity` field.

## Rules

- The app shows an operator's English label only when the interface language
  is English. Every other language keeps the native label (`label` in
  `operator-identities.json`), unchanged.
- One label per operator, at the **same level as the native label**: a short
  brand stays short (JR東日本 → JR East, 阪急 → Hankyu), a full company name
  stays a company name (上海申通地铁集团有限公司 → Shanghai Shentong Metro
  Group Co., Ltd.). The full corporate English name is
  kept below as evidence only; the UI does not need both.
- The source is the company's own English name: official English website,
  corporate materials, signage. Without that, an established English name
  from a reliable secondary source (Wikipedia citing operator usage, Railway
  Gazette, government English pages, or the earlier curated
  `operator-identities.json` `names.en` list) is used and marked `other`.
- No machine translation and no invented romanization, with one explicit
  exception: the four non-cn operators with no official or established
  English name (jp.jukkoku, jp.maya-cable, jp.tango-kairiku, kr.sillim) carry
  a romanized label by user decision 2026-11-10, marked `unofficial`. Every
  non-cn operator must have a label (guarded by `OperatorIdentityTests`).
  Other operators without an English name (all remaining are `cn`, region
  disabled) stay absent and untranslated (`none`).
- Legal suffixes that could not be confirmed are not added. For example,
  China Railway bureau groups are written "China Railway Jinan Group" without
  "Co., Ltd.".
- Joined labels (`中国铁路／港铁`) translate only when every part has an
  English name. Joined free text is translated part by part at runtime by
  `OperatorIdentity.englishLabel(forCompanyText:)` under the same rule.

Research: 2026-11-05, web research by region. `official` = checked against
the operator's own English material; `other` = secondary or existing curated
list, not re-verified against an official page in this pass; `unofficial` =
romanization chosen by the user, not an established English name.

| Code | Native label | English label | Full corporate name | Source type | Source | Note |
|---|---|---|---|---|---|---|
| cn.op1 | 中国铁路／港铁 | China Railway / MTR | China Railway / MTR Corporation Limited | official | https://www.12306.cn/en/index.html | China Railway per 12306 English; MTR per mtr.com.hk |
| cn.op10 | 中国铁路西安局 | China Railway Xi'an Group | China Railway Xi'an Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway | label is old bureau name; group form per Wikipedia |
| cn.op100 | 南昌轨道交通地铁运营有限公司 | — |  | none |  | no English name found |
| cn.op101 | 大连交通集团 | — | Dalian Public Transportation Group Co., Ltd. | none | https://en.wikipedia.org/wiki/Dalian_Rail_Transit | dropped in review: only a Dalian Metro article; not this group |
| cn.op102 | 长春公交集团电车公司 | — |  | none |  | no English name found |
| cn.op103 | 南昌中铁穗城轨道交通建设运营有限公司 | — |  | none |  | no English name found |
| cn.op104 | 南昌地铁 | Nanchang Metro |  | other | https://en.wikipedia.org/wiki/Nanchang_Metro | Wikipedia article title |
| cn.op105 | 昆明地铁运营有限公司 | — |  | none |  | no English name found |
| cn.op106 | 宁波市轨道交通集团有限公司 | — | Ningbo Rail Transit Group Co., Ltd. | none | https://www.cbinsights.com/company/ningbo-rail-transit | dropped in review: aggregator (CB Insights) only |
| cn.op108 | 北京市地铁运营一分有限公司 | — |  | none |  | no English name found |
| cn.op109 | 杭州杭港地铁有限公司 | Hangzhou MTR Corporation Limited | Hangzhou MTR Corporation Limited | official | https://www.mtr.com.hk/en/corporate/consultancy/hzmtr.html | MTR site; Chinese label is JV 杭港地铁 |
| cn.op11 | 中国铁路武汉局集团有限公司 | China Railway Wuhan Group | China Railway Wuhan Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway | Wikipedia lists 'Group Company'; Co., Ltd. form by pattern, unverified; legal suffix not confirmed, so dropped |
| cn.op110 | 苏州高新有轨电车 | — |  | none |  | no English name found |
| cn.op111 | 上海磁浮交通发展有限公司 | Shanghai Maglev Transportation Development Co., Ltd. | Shanghai Maglev Transportation Development Co., Ltd. | other | https://en.wikipedia.org/wiki/Shanghai_maglev_train | company site smtdc.com/en exists but fetch failed; likely official |
| cn.op113 | 长沙轨道交通集团有限公司 | Changsha Metro Group Co., Ltd. | Changsha Metro Group Co., Ltd. | other | https://www.railwaygazette.com/data/changsha-metro-group-csm/51439.article | Railway Gazette; doubtful |
| cn.op114 | 无锡地铁 | Wuxi Metro |  | other | https://en.wikipedia.org/wiki/Wuxi_Metro | Wikipedia |
| cn.op116 | 西安市轨道交通集团有限公司 | Xi'an Rail Transit Group Co., Ltd. | Xi'an Rail Transit Group Co., Ltd. | other | https://en.wikipedia.org/wiki/Xi%27an_Metro | unverified; doubtful |
| cn.op117 | 郑州地铁 | Zhengzhou Metro |  | other | https://en.wikipedia.org/wiki/Zhengzhou_Metro | Wikipedia |
| cn.op118 | 天津一号线轨道交通运营有限公司 | — |  | none |  | no English name found |
| cn.op119 | 神铁二号线（天津）轨道交通运营有限公司 | — |  | none |  | no English name found |
| cn.op12 | 中国铁路济南局集团有限公司 | China Railway Jinan Group | China Railway Jinan Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway | as op11; legal suffix not confirmed, so dropped |
| cn.op120 | 天津三号线轨道交通运营有限公司 | — |  | none |  | no English name found |
| cn.op121 | 沈阳地铁 | Shenyang Metro |  | other | https://en.wikipedia.org/wiki/Shenyang_Metro | Wikipedia |
| cn.op122 | 合肥轨道交通集团有限公司 | — |  | none |  | no English name found |
| cn.op123 | 沈阳浑南现代交通运营有限公司 | — |  | none |  | no English name found |
| cn.op124 | 福州地铁 | Fuzhou Metro |  | other | https://en.wikipedia.org/wiki/Fuzhou_Metro | Wikipedia |
| cn.op125 | 东莞市轨道交通有限公司 | — |  | none |  | no English name found |
| cn.op128 | 南宁轨道交通 | Nanning Rail Transit |  | other | https://en.wikipedia.org/wiki/Nanning_Rail_Transit | Wikipedia |
| cn.op129 | 徐州地铁 | Xuzhou Metro |  | other | https://en.wikipedia.org/wiki/Xuzhou_Metro | Wikipedia |
| cn.op13 | 中国铁路西安局集团有限公司 | China Railway Xi'an Group | China Railway Xi'an Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Xi%27an_Group | Wikipedia infobox; legal suffix not confirmed, so dropped |
| cn.op130 | 石家庄市轨道交通集团有限责任公司 | — |  | none |  | no English name found |
| cn.op131 | 天津致诚轨道交通运营有限公司 | — |  | none |  | no English name found |
| cn.op132 | 广州地铁运营集团有限公司 | — |  | none |  | no English name found |
| cn.op133 | 广州有轨电车有限责任公司 | — |  | none |  | no English name found |
| cn.op134 | 重庆轨道四号线建设运营 | — |  | none |  | no English name found |
| cn.op135 | 苏州轨道交通公司 | Suzhou Rail Transit |  | other | https://en.wikipedia.org/wiki/Suzhou_Rail_Transit | Wikipedia |
| cn.op137 | 云南京建轨道交通投资建设有限公司 | — |  | none |  | no English name found |
| cn.op138 | 上海金山铁路发展有限公司 | — |  | none |  | no English name found |
| cn.op139 | 上海申凯公共交通运营管理有限公司 | — |  | none |  | no English name found |
| cn.op14 | CN-narrow-gauge | — |  | none |  | not an operator (placeholder) |
| cn.op140 | 三亚市轨道交通有限公司 | — |  | none |  | no English name found |
| cn.op141 | 济南轨道交通集团有限公司 | Jinan Rail Transit Group Co., Ltd. | Jinan Rail Transit Group Co., Ltd. | other | https://en.wikipedia.org/wiki/Jinan_Metro | unverified; doubtful |
| cn.op142 | 天津轨道交通集团有限公司 | Tianjin Rail Transit Group Co., Ltd. | Tianjin Rail Transit Group Co., Ltd. | other | https://en.wikipedia.org/wiki/Tianjin_Metro | unverified; doubtful |
| cn.op143 | 青岛地铁运营有限公司 | — |  | none |  | no English name found |
| cn.op144 | 成都轨道交通集团有限公司 | Chengdu Rail Transit Group Co., Ltd. | Chengdu Rail Transit Group Co., Ltd. | other | https://www.railwaygazette.com/china/140.subject?page=4 | Railway Gazette |
| cn.op146 | 上海磁悬浮交通发展有限公司 | Shanghai Maglev Transportation Development Co., Ltd. | Shanghai Maglev Transportation Development Co., Ltd. | other | https://en.wikipedia.org/wiki/Shanghai_maglev_train | variant spelling of op111 |
| cn.op147 | Beijing Metro Operation Administration (BJMOA) Corp., Ltd. | Beijing Metro Operation Administration (BJMOA) Corp., Ltd. | Beijing Metro Operation Administration (BJMOA) Corp., Ltd. | official | http://www.bjmoa.cn | label already English; self-name, site not fetched |
| cn.op148 | 重庆江跳线轨道交通运营管理 | — |  | none |  | no English name found |
| cn.op149 | 杭州杭港地铁五号线有限公司 | — |  | none |  | no English name found |
| cn.op15 | 中国铁路南宁局集团有限公司 | China Railway Nanning Group | China Railway Nanning Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Nanning_Group | Wikipedia; legal suffix not confirmed, so dropped |
| cn.op150 | 呼和浩特市城市轨道交通建设管理有限责任公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op151 | 成都有轨电车 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op152 | 佛山市轨道交通发展有限公司运营事业总部 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op153 | 上海地铁 | Shanghai Metro | Shanghai Shentong Metro Group Co., Ltd. | other | https://en.wikipedia.org/wiki/Shanghai_Metro | Brand per Wikipedia; group per Shentong Metro Group article |
| cn.op154 | 西安中铁轨道交通有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op155 | 天水有轨电车 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op156 | 杭州地铁集团运营分公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op157 | 台州轨道交通 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op158 | 太原市轨道交通发展有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op159 | 青岛公交集团轨道巴士有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op16 | 中国铁路沈阳局 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op160 | 洛阳市轨道交通 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op161 | 北京亦庄公交有轨电车有限责任公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op162 | 淮安轨道交通 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op163 | 重庆云巴轨道交通运营管理 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op164 | 常州地铁 | Changzhou Metro |  | other | https://en.wikipedia.org/wiki/Changzhou_Metro | Established Wikipedia name; not verified via company site in this pass |
| cn.op165 | 绍兴京越地铁有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op166 | 杭州地铁运营有限公司客运三公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op167 | 杭州市地铁集团有限责任公司 | Hangzhou Metro Group Co., Ltd. | Hangzhou Metro Group Co., Ltd. | other | https://www.mtr.com.hk/en/corporate/consultancy/hzmtr.html | MTR site says 'Hangzhou Metro Group Company Limited'; wording varies (Hangzhou Subway Group) |
| cn.op168 | 青岛地铁 | Qingdao Metro | Qingdao Metro Group Co., Ltd. | other | https://en.wikipedia.org/wiki/Qingdao_Metro | Brand; full name from China Daily/qd-metro.com listing; alias Qingdao Metro Corporation exists in input |
| cn.op169 | 南昌轨道交通集团有限公司运营分公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op17 | 国能新朔铁路有限责任公司大准铁路分公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op170 | 浙江轨道交通运营集团海宁分公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op171 | 浙江幸福轨道交通运营管理有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op172 | 佛山市轨道交通发展有限公司 | Foshan Rail Transit Development Co., Ltd. | Foshan Rail Transit Development Co., Ltd. | other | https://en.wikipedia.org/wiki/Guangfo_line | Used in Wikipedia as owner; not seen on company site |
| cn.op173 | 哈尔滨地铁集团 | Harbin Metro Group |  | other | https://en.wikipedia.org/wiki/Harbin_Metro | Wikipedia lists 'Harbin Metro Group Corporation'; short form used |
| cn.op174 | 温州市铁路与轨道交通投资集团有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op175 | 杭州地铁运营有限公司客运三分公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op176 | 杭州地铁集团运营第二分公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op177 | 洛阳轨道交通有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op178 | 佛山市地铁运营有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op179 | 深圳地铁集团有限公司运营分公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op18 | 中国铁路沈阳局集团有限公司 | China Railway Shenyang Group | China Railway Shenyang Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Shenyang_Group | Wikipedia uses 'China Railway Shenyang Group'; Co., Ltd. suffix by pattern, unconfirmed; legal suffix not confirmed, so dropped |
| cn.op180 | 北京市轨道交通运营管理有限公司 | Beijing Metro Operation Administration Corp., Ltd. | Beijing Mass Transit Railway Operation Corporation Limited | official | http://www.bjmoa.cn | 北京市轨道交通运营管理有限公司 = BJMOA; English self-name as used by the company (also registered as op147) |
| cn.op181 | 大连地铁 | Dalian Metro | Dalian Metro Group Co., Ltd. | other | https://en.wikipedia.org/wiki/Dalian_Metro | Wikipedia operator listing; not confirmed on company site |
| cn.op183 | 天津致新轨道交通运营有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op184 | 浙中都市圈城际轨道交通 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op185 | 中铁建（天津）轨道交通投资发展有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op186 | 深圳市现代有轨电车有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op187 | 上海机场集团 | Shanghai Airport Authority | Shanghai Airport (Group) Co., Ltd. | other | https://en.wikipedia.org/wiki/Shanghai_Airport_Authority | Wikipedia; full form from secondary profiles |
| cn.op19 | 奎北铁路有限责任公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op190 | 凤凰磁浮文化旅游有限责任公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op191 | 深圳市东部城市轨道交通投资建设有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op192 | 黄石市城市轨道交通运营责任有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op193 | 重庆轨道十八号线建设运营 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op194 | 滁州轨道交通 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op195 | 大王山欢乐云巴 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op196 | 南京有轨电车 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op197 | 松江有轨电车 | Songjiang Tram |  | other | https://en.wikipedia.org/wiki/Songjiang_Tram | Wikipedia name for line/system; operator company is Shanghai Songjiang Tram Investment Operation Co., Ltd. |
| cn.op198 | 上海市域铁路运营有限公司 | — |  | none |  | No official or reliable English name found in this pass (branch/subsidiary or unlisted) |
| cn.op199 | 武汉地铁集团 | Wuhan Metro Group Co., Ltd. | Wuhan Metro Group Co., Ltd. | other | https://en.wikipedia.org/wiki/Wuhan_Metro | Wikipedia infobox; official site wuhanrt.com not verified |
| cn.op2 | 中国铁路 | China Railway | China State Railway Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway | 12306/China Railway brand; full corporate name China State Railway Group Co., Ltd. |
| cn.op20 | 中国铁路兰州局集团有限公司 | China Railway Lanzhou Group | China Railway Lanzhou Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Lanzhou_Group | Wikipedia; legal suffix not confirmed, so dropped |
| cn.op200 | 中交（天津）轨道交通运营管理有限公司十一号线分公司 | — |  | none |  | No official/reliable English name found |
| cn.op201 | 南通城市轨道交通有限公司 | Nantong Rail Transit Co., Ltd. | Nantong Rail Transit Co., Ltd. | other | https://en.wikipedia.org/wiki/Nantong_Rail_Transit | Wikipedia infobox, China Daily; matches alias |
| cn.op202 | 重庆璧铜线轨道交通运营管理 | — |  | none |  | No official/reliable English name found |
| cn.op203 | 北京八达岭畅安地面缆车运营有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op204 | 沈阳有轨电车 | — |  | none |  | No official/reliable English name found |
| cn.op205 | 西安云巴交通运营有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op206 | 西安昆明池景区运营管理有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op207 | 苏州市轨道交通集团有限公司运营二分公司 | — |  | none |  | No official/reliable English name found |
| cn.op208 | 北京市地铁运营有限公司运营四分公司 | — |  | none |  | No official/reliable English name found |
| cn.op209 | 北京地铁 | Beijing Subway |  | other | https://en.wikipedia.org/wiki/Beijing_Subway | Established brand name; short brand level |
| cn.op21 | 中国能源集团 | — |  | none |  | No official/reliable English name found |
| cn.op210 | 清远磁浮交通有限公司 | Qingyuan Maglev Transportation Co., Ltd. | Qingyuan Maglev Transportation Co., Ltd. | other | https://en.wikipedia.org/wiki/Qingyuan_Maglev_Tourist_Line | Variant renderings; doubtful |
| cn.op211 | 中铁（天津）轨道交通投资建设有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op212 | 中建（天津）轨道交通投资发展有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op214 | 天津滨海快速交通发展有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op215 | 长寿永恒缆车有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op216 | 辽源市交投运营发展集团有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op217 | 吉林市文化旅游集团有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op22 | 中国铁路南昌局集团有限公司 | China Railway Nanchang Group | China Railway Nanchang Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Nanchang_Group | Wikipedia; Co., Ltd. suffix by pattern, doubtful; legal suffix not confirmed, so dropped |
| cn.op23 | 中国铁路青藏集团有限公司 | China Railway Qinghai-Tibet Group | China Railway Qinghai-Tibet Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Qinghai-Tibet_Group | Sources vary (Qingzang/Qinghai-Tibet); doubtful; legal suffix not confirmed, so dropped |
| cn.op24 | 山东高速轨道交通集团有限公司岚山管理处 | — |  | none |  | No official/reliable English name found |
| cn.op25 | 中国铁路成都局集团宜宾车务段 | — |  | none |  | No official/reliable English name found |
| cn.op27 | 清绿铁路 | — |  | none |  | No official/reliable English name found |
| cn.op28 | 内蒙古东乌铁路有限责任公司 | — |  | none |  | No official/reliable English name found |
| cn.op29 | 川铁（宜宾）铁路有限责任公司 | — |  | none |  | No official/reliable English name found |
| cn.op3 | 中国铁路乌鲁木齐局集团有限公司 | China Railway Urumqi Group | China Railway Urumqi Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Urumqi_Group | Wikipedia; suffix by pattern; legal suffix not confirmed, so dropped |
| cn.op30 | 河北易县地方铁路管理局 | — |  | none |  | No official/reliable English name found |
| cn.op32 | 广东城际铁路运营有限公司 | Guangdong Intercity Railway Operation Co., Ltd. | Guangdong Intercity Railway Operation Co., Ltd. | other | https://en.wikipedia.org/wiki/Guangdong_Intercity | Wikipedia |
| cn.op33 | 广东地方铁路有限责任公司 | — |  | none |  | No official/reliable English name found |
| cn.op34 | 鄂尔多斯南部铁路有限责任公司 | — |  | none |  | No official/reliable English name found |
| cn.op35 | 库俄铁路有限责任公司 | — |  | none |  | No official/reliable English name found |
| cn.op36 | 新疆红淖三铁路有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op37 | 哈罗铁路有限责任公司 | — |  | none |  | No official/reliable English name found |
| cn.op38 | 山东高速轨道交通集团有限公司益羊铁路管理处 | — |  | none |  | No official/reliable English name found |
| cn.op39 | 内蒙古三新铁路有限责任公司 | — |  | none |  | No official/reliable English name found |
| cn.op4 | 中国铁路广州局集团有限公司 | China Railway Guangzhou Group | China Railway Guangzhou Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Guangzhou_Group | Wikipedia; legal suffix not confirmed, so dropped |
| cn.op40 | 四川归连铁路有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op41 | 永煤集团股份有限公司铁路运输处 | — |  | none |  | No official/reliable English name found |
| cn.op42 | 乌准铁路有限责任公司 | — |  | none |  | No official/reliable English name found |
| cn.op43 | 深圳平盐海铁联运有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op44 | 包满铁路有限责任公司 | — |  | none |  | No official/reliable English name found |
| cn.op45 | 中国平煤神马能源化工集团有限责任公司铁路运输处 | — |  | none |  | No official/reliable English name found |
| cn.op46 | 西甘铁路有限责任公司 | — |  | none |  | No official/reliable English name found |
| cn.op47 | 宁夏宁东铁路有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op48 | 哈木铁路有限公司 | — |  | none |  | No official/reliable English name found |
| cn.op49 | 漯阜铁路 | — |  | none |  | No official/reliable English name found |
| cn.op5 | 中国铁路哈尔滨局集团有限公司 | China Railway Harbin Group | China Railway Harbin Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Harbin_Group | Wikipedia pattern; not verified from official, doubtful; legal suffix not confirmed, so dropped |
| cn.op50 | 内蒙古海公铁路有限责任公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op51 | 中国铁路北京局集团有限公司 | China Railway Beijing Group | China Railway Beijing Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Beijing_Group | Pattern per Wikipedia/CR naming; exact Co., Ltd. wording not seen on an official page; legal suffix not confirmed, so dropped |
| cn.op52 | 中国铁路郑州局集团有限公司 | China Railway Zhengzhou Group | China Railway Zhengzhou Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Zhengzhou_Group | Wikipedia gives full name; no official English page found; legal suffix not confirmed, so dropped |
| cn.op53 | 中铁十六局铁运公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op54 | 图木舒克城投集团铁路建设经营管理有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op55 | 新疆天山铁道有限责任公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op56 | 新疆北阿铁路有限责任公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op57 | 临哈铁路有限责任公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op58 | 中国铁路南昌局 | China Railway Nanchang Group | China Railway Nanchang Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Nanchang_Group | Label is old bureau name; group name used (doubtful) |
| cn.op59 | 贵州瓮马铁路有限责任公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op6 | 中国铁路呼和浩特局集团有限公司 | China Railway Hohhot Group | China Railway Hohhot Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Hohhot_Group | Wikipedia; Co., Ltd. by pattern; legal suffix not confirmed, so dropped |
| cn.op60 | 山西阳大铁路有限责任公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op61 | 中铁十六局集团铁运工程有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op62 | 吉林省宇辉地方铁路有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op63 | 哈尔滨宾西铁路有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op64 | 郑州煤炭工业（集团）有限责任公司铁路运输处 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op65 | 南涪铁路有限责任公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op66 | 中国铁路郑州局集团有限公司；中国铁路济南局集团有限公司 | China Railway Zhengzhou Group / China Railway Jinan Group | China Railway Zhengzhou Group Co., Ltd.；China Railway Jinan Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Zhengzhou_Group | Jinan part by same naming pattern, not separately verified (doubtful) |
| cn.op67 | 吉林省东北亚铁路集团股份有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op68 | 四川连乐铁路有限责任公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op69 | 南京地方铁路有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op7 | 中国铁路成都局集团 | China Railway Chengdu Group | China Railway Chengdu Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Chengdu_Group | Label is short form; Wikipedia |
| cn.op70 | 四川叙大铁路有限责任公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op72 | 庄河地方铁路 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op73 | 天津南环铁路有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op74 | 中铁三局集团有限公司运输工程分公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op75 | 甘肃朱中铁路有限责任公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op76 | 兖矿集团铁路运输处 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op77 | 上海申通地铁集团有限公司 | Shanghai Shentong Metro Group Co., Ltd. | Shanghai Shentong Metro Group Co., Ltd. | other | https://en.wikipedia.org/wiki/Shentong_Metro_Group | Wikipedia; also 'Company Limited' variant |
| cn.op78 | 四川隆叙宜铁路有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op79 | 湖南省永耒铁路运输服务有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op8 | 中国铁路昆明局集团有限公司 | China Railway Kunming Group | China Railway Kunming Group Co., Ltd. | other | https://en.wikipedia.org/wiki/China_Railway_Kunming_Group | Wikipedia; Co., Ltd. by pattern; legal suffix not confirmed, so dropped |
| cn.op80 | 上海地铁第四运营有限公司 | Shanghai No. 4 Metro Operation Co. Ltd. | Shanghai No. 4 Metro Operation Co. Ltd. | other | https://en.wikipedia.org/wiki/Shentong_Metro_Group | Wikipedia citing group 2015 annual report |
| cn.op81 | 上海地铁第三运营有限公司 | Shanghai No. 3 Metro Operation Co. Ltd. | Shanghai No. 3 Metro Operation Co. Ltd. | other | https://en.wikipedia.org/wiki/Shentong_Metro_Group | Wikipedia citing group 2015 annual report |
| cn.op82 | 上海地铁第一运营有限公司 | Shanghai No. 1 Metro Operation Co. Ltd. | Shanghai No. 1 Metro Operation Co. Ltd. | other | https://en.wikipedia.org/wiki/Shentong_Metro_Group | Wikipedia citing group 2015 annual report |
| cn.op83 | 上海地铁第二运营有限公司 | Shanghai No. 2 Metro Operation Co. Ltd. | Shanghai No. 2 Metro Operation Co. Ltd. | other | https://en.wikipedia.org/wiki/Shentong_Metro_Group | Wikipedia citing group 2015 annual report |
| cn.op84 | Shanghai Maglev Transportation Co., Ltd. | Shanghai Maglev Transportation Co., Ltd. | Shanghai Maglev Transportation Development Co., Ltd. | other | https://en.wikipedia.org/wiki/Shentong_Metro_Group | Label already English; Wikipedia full name includes 'Development' (doubtful) |
| cn.op85 | 广州地铁集团有限公司 | Guangzhou Metro Group Co., Ltd. | Guangzhou Metro Group Co., Ltd. | other | https://en.wikipedia.org/wiki/Guangzhou_Metro | Secondary sources; Wikipedia also uses 'Guangzhou Metro Corporation' |
| cn.op86 | 天津致远轨道交通运营有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op87 | 重庆轨道交通运营 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op89 | 北京市地铁运营有限公司 | Beijing Mass Transit Railway Operation Corporation Limited | Beijing Mass Transit Railway Operation Corporation Limited | other | https://en.wikipedia.org/wiki/Beijing_Mass_Transit_Railway_Operation_Corporation_Limited | Wikipedia; company also uses 'Beijing Subway Operation Co., Ltd.' (doubtful); site bjsubway.com/en |
| cn.op9 | 广西沿海铁路股份有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op90 | 南京地铁 | Nanjing Metro | Nanjing Metro Group Co., Ltd. | other | https://en.wikipedia.org/wiki/Nanjing_Metro | Short brand; group name from Wikipedia |
| cn.op92 | 北京市地铁运营二分有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op93 | 北京京城地铁有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op94 | 深圳市地铁集团有限公司 | Shenzhen Metro Group Co., Ltd. | Shenzhen Metro Group Co., Ltd. | other | https://qh.sz.gov.cn/en/services/transportation/content/post_10660085.html | Shenzhen govt English portal |
| cn.op97 | 成都地铁运营有限公司 | — |  | none |  | No English name found in official or reliable secondary sources |
| cn.op98 | 长春市轨道交通集团 | — | Changchun Rail Transit Corporation | none |  | dropped in review: no source |
| hk.mtr | MTR | MTR | MTR Corporation Limited | official | https://www.mtr.com.hk/en/corporate/ | brand; not re-fetched this run |
| hk.tramways | 香港電車 | Hong Kong Tramways | Hongkong Tramways Limited | official | https://www.hktramways.com/en/ | not re-fetched; company legal spelling Hongkong |
| jp.abukuma | 阿武隈急行 | Abukuma Express |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.aikan | 愛知環状鉄道 | Aichi Loop Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.ainokaze | あいの風とやま鉄道 | Ainokaze Toyama Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.aizu | 会津鉄道 | Aizu Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.akechi | 明知鉄道 | Akechi Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.akita-nairiku | 秋田内陸縦貫鉄道 | Akita Nairiku Jukan Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.alpico | アルピコ交通 | Alpico Kotsu |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.amagi | 甘木鉄道 | Amagi Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.aoimori | 青い森鉄道 | Aoimori Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.aonami | 名古屋臨海高速鉄道 | Nagoya Rinkai Rapid Transit |  | other | https://en.wikipedia.org/wiki/Aonami_Line | DOUBTFUL: replaced line name "Aonami Line"; no official English found |
| jp.asa-kaigan | 阿佐海岸鉄道 | Asa Kaigan Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.astram | 広島高速交通 | Hiroshima Rapid Transit | Hiroshima Rapid Transit Co., Ltd. | other | https://en.wikipedia.org/wiki/Hiroshima_Rapid_Transit | replaced line name "Astram Line" with company name; secondary source |
| jp.asunaro | 四日市あすなろう鉄道 | Yokkaichi Asunarou Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.chiba-monorail | 千葉都市モノレール | Chiba Urban Monorail |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.chichibu | 秩父鉄道 | Chichibu Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.chikuho | 筑豊電気鉄道 | Chikuho Electric Railroad |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.chitetsu | 富山地方鉄道 | Toyama Chiho Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.chizu | 智頭急行 | Chizu Express |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.choshi | 銚子電気鉄道 | Choshi Electric Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.disney-resort | 舞浜リゾートライン | Maihama Resort Line | Maihama Resort Line Co., Ltd. | other | https://www.olc.co.jp/en/tdr/profile/resortline.html | label is company; Disney Resort Line is the brand |
| jp.donan-isaribi | 道南いさりび鉄道 | South Hokkaido Railway | South Hokkaido Railway Company | other | https://visit-hokkaido.jp/en/spot/detail_10535.html | existing confirmed by Visit Hokkaido; official site shr-isaribi.jp |
| jp.echigo-tokimeki | えちごトキめき鉄道 | Echigo Tokimeki Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.echizen | えちぜん鉄道 | Echizen Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.eizan | 叡山電鉄 | Eizan Electric Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.enoden | 江ノ島電鉄 | Enoshima Electric Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.entetsu | 遠州鉄道 | Enshu Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.fujikyu | 富士山麓電気鉄道 | Fujikyu Railway |  | other | existing operator-identities.json | DOUBTFUL: label 富士山麓電気鉄道 is a distinct 2022 spin-off from Fuji Kyuko; no official English found |
| jp.fukui | 福井鉄道 | Fukui Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.fukuoka-subway | 福岡市営 | Fukuoka City Subway |  | other | existing operator-identities.json | municipal short form |
| jp.fukushima-kotsu | 福島交通 | Fukushima Kotsu |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.gakunan | 岳南電車 | Gakunan Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.hakodate-tram | 函館市電 | Hakodate City Tram |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.hakone-tozan | 小田急箱根 | Odakyu Hakone |  | other | https://www.hakonenavi.jp/international/en/ | label is brand 小田急箱根 (since 2024); replaced Hakone Tozan Railway |
| jp.hankai | 阪堺電気軌道 | Hankai Tramway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.hankyu | 阪急 | Hankyu | Hankyu Corporation | other | https://www.hankyu.co.jp/global/en/ | brand-level to match label; full per existing |
| jp.hanshin | 阪神 | Hanshin | Hanshin Electric Railway Co., Ltd. | other | https://rail.hanshin.co.jp/global/en/ | brand-level to match label |
| jp.hapi-line-fukui | ハピラインふくい | Hapi-Line Fukui |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.heisei-chikuho | 平成筑豊鉄道 | Heisei Chikuho Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.hieizan | 比叡山鉄道 | Hieizan Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.hiroden | 広島電鉄 | Hiroshima Electric Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.hisatsu-orange | 肥薩おれんじ鉄道 | Hisatsu Orange Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.hitachinaka | ひたちなか海浜鉄道 | Hitachinaka Seaside Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.hojo | 北条鉄道 | Hojo Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.hokuetsu | 北越急行 | Hokuetsu Express |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.hokuriku | 北陸鉄道 | Hokuriku Railroad |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.hokuso | 北総鉄道 | Hokuso Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.ibara | 井原鉄道 | Ibara Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.ichibata | 一畑電車 | Ichibata Electric Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.iga | 伊賀鉄道 | Iga Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.igr | アイジーアールいわて銀河鉄道 | IGR Iwate Galaxy Railway | Iwate Galaxy Railway Co., Ltd. | other | existing operator-identities.json | label is full name アイジーアールいわて銀河鉄道; combined existing forms; unverified |
| jp.ir-ishikawa | IRいしかわ鉄道 | IR Ishikawa Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.ise | 伊勢鉄道 | Ise Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.isumi | いすみ鉄道 | Isumi Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.iyo | 伊予鉄道 | Iyo Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.izu-hakone | 伊豆箱根鉄道 | Izu Hakone Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.izukyu | 伊豆急行 | Izukyu | Izukyu Corporation | other | existing operator-identities.json | full name per Wikipedia; unverified official |
| jp.jomo | 上毛電気鉄道 | Jomo Electric Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.joshin | 上信電鉄 | Joshin Electric Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.jr-central | JR東海 | JR Central | Central Japan Railway Company | official | https://global.jr-central.co.jp/en/ | well-known official name |
| jp.jr-central-transport | JR東海交通事業 | JR Central Transport Service | JR Central Transport Service Company | other | existing operator-identities.json | existing; unverified |
| jp.jr-east | JR東日本 | JR East | East Japan Railway Company | official | https://www.jreast.co.jp/e/ | well-known official name |
| jp.jr-hokkaido | JR北海道 | JR Hokkaido | Hokkaido Railway Company | official | https://www.jrhokkaido.co.jp/global/english/ | well-known official name |
| jp.jr-kyushu | JR九州 | JR Kyushu | Kyushu Railway Company | official | https://www.jrkyushu.co.jp/english/ | well-known official name |
| jp.jr-shikoku | JR四国 | JR Shikoku | Shikoku Railway Company | official | https://www.jr-shikoku.co.jp/global/en/ | well-known official name |
| jp.jr-west | JR西日本 | JR West | West Japan Railway Company | official | https://www.westjr.co.jp/global/en/ | well-known official name |
| jp.jukkoku | 十国峠 | Jukkokutoge |  | unofficial | existing operator-identities.json | user decision 2026-11-10: romanized, not an official name |
| jp.kagoshima-tram | 鹿児島市電 | Kagoshima City Tram |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.kanto | 関東鉄道 | Kanto Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.kashima | 鹿島臨海鉄道 | Kashima Coastal Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.keifuku | 京福電気鉄道 | Keifuku Electric Railroad |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.keihan | 京阪 | Keihan | Keihan Electric Railway Co., Ltd. | other | https://www.keihan.co.jp/en/ | brand-level to match label |
| jp.keikyu | 京急 | Keikyu | Keikyu Corporation | official | https://www.keikyu.co.jp/en/ | official English name Keikyu Corporation since 2010 (via search) |
| jp.keio | 京王 | Keio | Keio Corporation | other | https://www.keio.co.jp/en/ | brand-level to match label |
| jp.keisei | 京成 | Keisei | Keisei Electric Railway Co., Ltd. | other | https://www.keisei.co.jp/keisei/tetudou/skyliner/us/ | brand-level to match label |
| jp.kintetsu | 近鉄 | Kintetsu | Kintetsu Railway Co., Ltd. | other | https://www.kintetsu.co.jp/foreign/english/ | brand-level to match label |
| jp.kishu | 紀州鉄道 | Kishu Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.kita-osaka | 北大阪急行電鉄 | Kita-Osaka Kyuko Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.kitakyushu-monorail | 北九州高速鉄道 | Kitakyushu Monorail |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.kobe-new-transit | 神戸新交通 | Kobe New Transit |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.kobe-subway | 神戸市営 | Kobe Municipal Subway |  | other | existing operator-identities.json | municipal short form |
| jp.kominato | 小湊鐵道 | Kominato Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.konan | 弘南鉄道 | Konan Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.kotoden | 高松琴平電気鉄道 | Kotoden | Takamatsu-Kotohira Electric Railroad Co., Ltd. | other | existing operator-identities.json | brand level; full from general knowledge |
| jp.kumaden | 熊本電気鉄道 | Kumamoto Electric Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.kumagawa | くま川鉄道 | Kumagawa Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.kumamoto-tram | 熊本市電 | Kumamoto City Tram |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.kurama | 鞍馬寺 | Kurama-dera |  | other | existing operator-identities.json | DOUBTFUL: label is the temple; dropped "Cable"; unverified |
| jp.kurobe-gorge | 黒部峡谷鉄道 | Kurobe Gorge Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.kyoto-subway | 京都市営 | Kyoto Municipal Subway |  | other | existing operator-identities.json | municipal short form |
| jp.kyoto-tango | WILLER TRAINS | WILLER TRAINS |  | other | existing operator-identities.json | brand keeps WILLER TRAINS (matches label); unverified |
| jp.linimo | 愛知高速交通 | Aichi Rapid Transit | Aichi Rapid Transit Co., Ltd. | official | https://www.linimo.jp/language/en/company/ | label is company name; Linimo is the line brand |
| jp.manyosen | 万葉線 | Manyosen |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.matsuura | 松浦鉄道 | Matsuura Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.maya-cable | こうべ未来都市機構 | Kobe Future City |  | unofficial | https://en.wikipedia.org/wiki/Kobe_Future_City | user decision 2026-11-10: romanized, not an official name |
| jp.meitetsu | 名鉄 | Meitetsu | Nagoya Railroad Co., Ltd. | other | https://www.meitetsu.co.jp/eng/ | brand-level to match label |
| jp.minamiaso | 南阿蘇鉄道 | Minamiaso Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.minatomirai | 横浜高速鉄道 | Yokohama Minatomirai Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.mitake | 御岳登山鉄道 | Mitake Tozan Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.mizuma | 水間鉄道 | Mizuma Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.mizushima | 水島臨海鉄道 | Mizushima Rinkai Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.moka | 真岡鐵道 | Moka Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.nagaden | 長野電鉄 | Nagano Electric Railway |  | other | existing operator-identities.json | kept existing; not web-verified |
| jp.nagaragawa | 長良川鉄道 | Nagaragawa Railway |  | other | existing operator-identities.json |  |
| jp.nagasaki-tram | 長崎電気軌道 | Nagasaki Electric Tramway |  | other | existing operator-identities.json |  |
| jp.nagoya-subway | 名古屋市営 | Nagoya Municipal Subway | Transportation Bureau, City of Nagoya | other | existing operator-identities.json | municipal; brand name |
| jp.nankai | 南海 | Nankai | Nankai Electric Railway Co., Ltd. | other | existing operator-identities.json | short brand |
| jp.new-shuttle | 埼玉新都市交通 | Saitama New Urban Transit | Saitama New Urban Transit Co., Ltd. | official | https://www.new-shuttle.jp/company/files/pdf/pdf_newshuttle_corporate_information.pdf | label is company name; 'New Shuttle' is the system brand |
| jp.nishikigawa | 錦川鉄道 | Nishikigawa Railway |  | other | existing operator-identities.json |  |
| jp.nishitetsu | 西鉄 | Nishitetsu | Nishi-Nippon Railroad Co., Ltd. | other | existing operator-identities.json | short brand |
| jp.nose | 能勢電鉄 | Nose Electric Railway |  | other | existing operator-identities.json |  |
| jp.noto | のと鉄道 | Noto Railway |  | other | existing operator-identities.json |  |
| jp.odakyu | 小田急 | Odakyu | Odakyu Electric Railway Co., Ltd. | other | existing operator-identities.json | short brand |
| jp.ohmi | 近江鉄道 | Ohmi Railway |  | other | existing operator-identities.json |  |
| jp.oigawa | 大井川鐵道 | Oigawa Railway |  | other | existing operator-identities.json |  |
| jp.okaden | 岡山電気軌道 | Okayama Electric Tramway |  | other | existing operator-identities.json |  |
| jp.osaka-metro | 大阪メトロ | Osaka Metro | Osaka Metro Co., Ltd. | other | existing operator-identities.json |  |
| jp.osaka-monorail | 大阪モノレール | Osaka Monorail |  | other | existing operator-identities.json |  |
| jp.oyama-cable | 大山観光電鉄 | Oyama Cable Car |  | other | existing operator-identities.json | DOUBTFUL: label is company 大山観光電鉄; en is service name, unverified |
| jp.rakutenchi | ラクテンチ | Rakutenchi |  | other | existing operator-identities.json |  |
| jp.rinkai | 東京臨海高速鉄道 | Tokyo Waterfront Area Rapid Transit | Tokyo Waterfront Area Rapid Transit, Inc. | other | existing operator-identities.json | label is company name; Rinkai Line is the line |
| jp.rokko-cable | 神戸六甲鉄道 | Rokko Cable |  | other | existing operator-identities.json | DOUBTFUL: label is company 神戸六甲鉄道; en is line name, unverified |
| jp.ryutetsu | 流鉄 | Ryutetsu |  | other | existing operator-identities.json |  |
| jp.sagano | 嵯峨野観光鉄道 | Sagano Scenic Railway |  | other | existing operator-identities.json |  |
| jp.saitama-rapid | 埼玉高速鉄道 | Saitama Rapid Railway |  | other | existing operator-identities.json |  |
| jp.sangi | 三岐鉄道 | Sangi Railway |  | other | existing operator-identities.json |  |
| jp.sanriku | 三陸鉄道 | Sanriku Railway |  | other | existing operator-identities.json |  |
| jp.sanyo | 山陽電気鉄道 | Sanyo Electric Railway |  | other | existing operator-identities.json |  |
| jp.sapporo-streetcar | 札幌市電 | Sapporo Streetcar |  | other | existing operator-identities.json | service brand |
| jp.sapporo-subway | 札幌市営 | Sapporo Municipal Subway |  | other | existing operator-identities.json | municipal; brand name |
| jp.sarakura | 皿倉登山鉄道 | Sarakura Tozan Railway | Sarakura Tozan Railway Co., Ltd. | official | https://www.sarakurayama-cablecar.co.jp/wp-content/uploads/2024/09/sarakurayamaccEnglish2025.pdf | official brochure gives company name; commonly known as Sarakurayama Cable Car; replaced existing |
| jp.seaside-line | 横浜シーサイドライン | Yokohama Seaside Line |  | other | existing operator-identities.json |  |
| jp.seibu | 西武 | Seibu | Seibu Railway Co., Ltd. | other | existing operator-identities.json | short brand |
| jp.seikan-tunnel | 青函トンネル記念館 | Seikan Tunnel Museum |  | other | existing operator-identities.json |  |
| jp.sendai-airport | 仙台空港鉄道 | Sendai Airport Transit | Sendai Airport Transit Co., Ltd. | official | https://www.senat.co.jp/en/top |  |
| jp.sendai-subway | 仙台市営 | Sendai Municipal Subway |  | other | existing operator-identities.json | municipal; brand name |
| jp.shibayama | 芝山鉄道 | Shibayama Railway |  | other | existing operator-identities.json |  |
| jp.shigaraki | 信楽高原鐵道 | Shigaraki Kogen Railway |  | other | existing operator-identities.json |  |
| jp.shikoku-cable | 四国ケーブル | Shikoku Cable |  | other | existing operator-identities.json |  |
| jp.shimabara | 島原鉄道 | Shimabara Railway |  | other | existing operator-identities.json |  |
| jp.shinano | しなの鉄道 | Shinano Railway |  | other | existing operator-identities.json |  |
| jp.shintetsu | 神戸電鉄 | Kobe Electric Railway | Kobe Electric Railway Co., Ltd. | other | existing operator-identities.json | label is full name; Shintetsu is nickname |
| jp.shizutetsu | 静岡鉄道 | Shizuoka Railway |  | other | existing operator-identities.json |  |
| jp.shonan-monorail | 湘南モノレール | Shonan Monorail |  | other | existing operator-identities.json |  |
| jp.sotetsu | 相鉄 | Sotetsu | Sagami Railway Co., Ltd. | other | existing operator-identities.json | short brand |
| jp.takao | 高尾登山電鉄 | Takao Tozan Electric Railway |  | other | existing operator-identities.json |  |
| jp.tama-monorail | 多摩都市モノレール | Tama Monorail |  | other | existing operator-identities.json |  |
| jp.tango-kairiku | 丹後海陸交通 | Tango Kairiku Kotsu |  | unofficial | existing operator-identities.json | user decision 2026-11-10: romanized, not an official name |
| jp.tarumi | 樽見鉄道 | Tarumi Railway |  | other | existing operator-identities.json |  |
| jp.tateyama-kurobe | 立山黒部貫光 | Tateyama Kurobe Kanko |  | other | existing operator-identities.json | DOUBTFUL: official English not found |
| jp.tenhama | 天竜浜名湖鉄道 | Tenryu Hamanako Railroad |  | other | existing operator-identities.json |  |
| jp.tobu | 東武 | Tobu | Tobu Railway Co., Ltd. | other | existing operator-identities.json | short brand |
| jp.toei | 都営 | Toei | Tokyo Metropolitan Bureau of Transportation | official | https://www.kotsu.metro.tokyo.jp/eng/ | short brand; Toei Subway is official service name |
| jp.tokyo-metro | 東京メトロ | Tokyo Metro | Tokyo Metro Co., Ltd. | other | existing operator-identities.json |  |
| jp.tokyo-monorail | 東京モノレール | Tokyo Monorail |  | other | existing operator-identities.json |  |
| jp.tokyu | 東急 | Tokyu | Tokyu Corporation | other | existing operator-identities.json | short brand |
| jp.tosa-kuroshio | 土佐くろしお鉄道 | Tosa Kuroshio Railway |  | other | existing operator-identities.json |  |
| jp.tosaden | とさでん交通 | Tosaden Traffic | Tosaden Traffic Co., Ltd. | official | https://www.tosaden.co.jp/multilingual/en/bus/route/ticket.html | footer shows TOSADEN TRAFFIC CO., LTD |
| jp.toyo-rapid | 東葉高速鉄道 | Toyo Rapid Railway |  | other | existing operator-identities.json |  |
| jp.toyotetsu | 豊橋鉄道 | Toyohashi Railroad |  | other | existing operator-identities.json |  |
| jp.tsugaru | 津軽鉄道 | Tsugaru Railway |  | other | existing operator-identities.json |  |
| jp.tsukuba-cable | 筑波観光鉄道 | Tsukuba Scenic Railway | Tsukuba Scenic Railway Co., Ltd. | official | https://www.mt-tsukuba.com/global/en/ | English site footer; replaced existing 'Mt. Tsukuba Cable Car' (service name) |
| jp.tsukuba-express | 首都圏新都市鉄道 | Metropolitan Intercity Railway Company |  | other | https://en.wikipedia.org/wiki/Metropolitan_Intercity_Railway_Company | label is company name; 'Tsukuba Express' is the line brand; official site not confirmed; replaced existing |
| jp.ueda | 上田電鉄 | Ueda Electric Railway |  | other | existing operator-identities.json |  |
| jp.utsunomiya-lrt | 宇都宮ライトレール | Utsunomiya Light Rail |  | other | existing operator-identities.json |  |
| jp.wakasa | 若桜鉄道 | Wakasa Railway |  | other | existing operator-identities.json |  |
| jp.wakayama-electric | 和歌山電鐵 | Wakayama Electric Railway |  | other | existing operator-identities.json |  |
| jp.watarase | わたらせ渓谷鐵道 | Watarase Keikoku Railway |  | other | existing operator-identities.json |  |
| jp.yagan | 野岩鉄道 | Yagan Railway |  | other | existing operator-identities.json |  |
| jp.yamagata | 山形鉄道 | Yamagata Railway |  | other | existing operator-identities.json |  |
| jp.yamaman | 山万 | Yamaman |  | other | existing operator-identities.json |  |
| jp.yokohama-subway | 横浜市営 | Yokohama Municipal Subway |  | other | existing operator-identities.json |  |
| jp.yoro | 養老鉄道 | Yoro Railway |  | other | existing operator-identities.json |  |
| jp.yui-rail | 沖縄都市モノレール | Okinawa Urban Monorail |  | other | https://en.wikipedia.org/wiki/Okinawa_Urban_Monorail | label is company name; Yui Rail is the brand |
| jp.yuri-kogen | 由利高原鉄道 | Yuri Kogen Railway |  | other | existing operator-identities.json |  |
| jp.yurikamome | ゆりかもめ | Yurikamome |  | other | existing operator-identities.json |  |
| jp.yutorito | 名古屋ガイドウェイバス | Nagoya Guideway Bus |  | other | existing operator-identities.json | label is company name; Yutorito Line is the line |
| kr.arex | 공항철도주식회사 | Airport Railroad | Airport Railroad Co., Ltd. | other | existing operator-identities.json | label is company name; AREX is the brand |
| kr.busan-gimhae | 부산·김해경전철주식회사 | Busan-Gimhae Light Rail |  | other | existing operator-identities.json |  |
| kr.busan-metro | 부산교통공사 | Busan Transportation Corporation | Busan Transportation Corporation | other | existing operator-identities.json | per instruction |
| kr.daegu-metro | 대구교통공사 | Daegu Transportation Corporation |  | other | existing operator-identities.json |  |
| kr.daejeon-metro | 대전교통공사 | Daejeon Transportation Corporation |  | other | existing operator-identities.json |  |
| kr.everline | 용인에버라인운영(주) | Yongin EverLine |  | other | existing operator-identities.json | unverified |
| kr.gimpo-goldline | 김포골드라인SRS | Gimpo Goldline |  | other | existing operator-identities.json | unverified |
| kr.gtx-a | 지티엑스에이운영주식회사 | GTX-A |  | other | existing operator-identities.json | DOUBTFUL: operator-company English not found |
| kr.gwangju-metro | 광주교통공사 | Gwangju Metropolitan Transit Corporation |  | other | existing operator-identities.json |  |
| kr.haeundae-blueline | 해운대블루라인(주) | Haeundae Blueline Park |  | other | existing operator-identities.json | DOUBTFUL: tourist brand name |
| kr.incheon-airport-shuttle | 인천공항시설관리 | Incheon Airport Shuttle Train |  | other | existing operator-identities.json | DOUBTFUL: label is facility manager company; en is service name |
| kr.incheon-metro | 인천교통공사 | Incheon Transit Corporation |  | other | existing operator-identities.json |  |
| kr.jukbyeon-skyrail | (주)스카이레일 | Jukbyeon Coastal Skyrail |  | other | existing operator-identities.json | DOUBTFUL: unverified |
| kr.korail | 한국철도공사 | Korail | Korea Railroad Corporation | other | existing operator-identities.json |  |
| kr.neotrans | 네오트랜스주식회사 | NeoTrans | NeoTrans Co., Ltd. | other | existing operator-identities.json | Shinbundang Line is the line |
| kr.seoul-line9 | 서울시메트로9호선 | Seoul Metro Line 9 |  | other | existing operator-identities.json | unverified |
| kr.seoul-metro | 서울교통공사 | Seoul Metro | Seoul Metro | other | existing operator-identities.json | Seoul Transportation Corporation is older English |
| kr.sillim | 로템SRS | Rotem SRS |  | unofficial | existing operator-identities.json | user decision 2026-11-10: romanized, not an official name |
| kr.sr | 에스알 | SR | SR Co., Ltd. | other | existing operator-identities.json | SRT is the service |
| kr.ui-sinseol | 우이신설 도시철도 | Ui-Sinseol LRT |  | other | existing operator-identities.json | DOUBTFUL: unverified |
| kr.uijeongbu-lrt | (주)우진메트로 | Uijeongbu Light Rail |  | other | existing operator-identities.json | unverified |
| mo.lrt | 澳門輕軌 | Macao LRT | Macao Light Rapid Transit Corporation, Limited | other | https://macaobusiness/gazette: images.io.gov.mo/bo/i/2019/12/rega-8-2019.pdf | company name per 2019 gazette; short brand |
| tw.alishan | 阿里山林鐵 | Alishan Forest Railway |  | other | existing operator-identities.json |  |
| tw.kaohsiung-metro | 高雄捷運 | Kaohsiung Metro | Kaohsiung Rapid Transit Corporation | other | existing operator-identities.json | MRT variant also in use; unverified |
| tw.new-taipei-metro | 新北捷運 | New Taipei Metro |  | other | existing operator-identities.json |  |
| tw.taichung-metro | 台中捷運 | Taichung Metro |  | other | existing operator-identities.json |  |
| tw.taipei-metro | 台北捷運 | Taipei Metro | Taipei Rapid Transit Corporation | other | existing operator-identities.json |  |
| tw.taoyuan-metro | 桃園捷運 | Taoyuan Metro |  | other | existing operator-identities.json |  |
| tw.thsr | 台灣高鐵 | Taiwan High Speed Rail | Taiwan High Speed Rail Corporation | other | https://www.thsrc.com.tw/en/ |  |
| tw.tra | 台鐵 | Taiwan Railway | Taiwan Railway Corporation | other | existing operator-identities.json | per instruction; official site not confirmed |
