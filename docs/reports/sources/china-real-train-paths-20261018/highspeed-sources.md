# Official G/D/C passenger stop evidence — 2026-10-18

The corpus contains 62 real train schedules queried directly from official China Railway 12306 endpoints for service date **2026-10-18**. These are published schedules, not independent proof of actual operation. Every station below is observed in the stop-response JSON; no intermediate stops were guessed.

## Method

1. Read `https://search.12306.cn/search/v1/train/search?keyword=G1&date=20261018` to resolve a public train number to its internal `train_no`, origin, destination and `total_num`.
2. Read `https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=24000000G10L&leftTicketDTO.train_date=2026-10-18&rand_code=` to obtain its ordered passenger stops.
3. Require count and endpoint agreement before marking the sequence full. Exact-name station code joins use the official 3,404-station table already saved in `railway-sources/local/china/evidence/official-20261018/12306-national-stations.json`.

Raw search and stop JSON is retained in `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/`; detailed per-stop train aliases, arrival/departure times and day offsets are retained in `highspeed-sources.json`. A dated schedule does not identify the exact track at non-stopping junctions.

The 62 public-number records represent **61 unique internal services**: G383 and G386 are aliases of the same service. They may be useful as alias tests but should not be counted as independent services. Some official `station_no` values skip numbers; these are preserved. “Full” denotes the entire returned passenger list matching official search count and endpoints, not a list of every physical station.

## Observed schedules

### G1 — 北京南 → 上海虹桥

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:00.429475+00:00; completeness: full (7 stops).
- Ordered stops: 北京南 (`VNP`) → 沧州西 (`CBP`) → 德州东 (`DIP`) → 曲阜东 (`QAK`) → 南京南 (`NKH`) → 苏州北 (`OHH`) → 上海虹桥 (`AOH`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=24000000G10L&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G1.json`.

### G10 — 上海虹桥 → 北京南

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:00.431941+00:00; completeness: full (4 stops).
- Ordered stops: 上海虹桥 (`AOH`) → 南京南 (`NKH`) → 济南西 (`JGK`) → 北京南 (`VNP`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=5l00000G1010&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G10.json`.

### G101 — 北京朝阳 → 牡丹江

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:01.468283+00:00; completeness: full (5 stops).
- Ordered stops: 北京朝阳 (`IFP`) → 沈阳北 (`SBT`) → 长春西 (`CRT`) → 哈尔滨西 (`VAB`) → 牡丹江 (`MDB`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=240000G10121&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G101.json`.

### G169 — 大连北 → 北京朝阳

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:01.416751+00:00; completeness: full (4 stops).
- Ordered stops: 大连北 (`DFT`) → 营口东 (`YGT`) → 盘锦 (`PVD`) → 北京朝阳 (`IFP`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=1g0000G16900&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G169.json`.

### G201 — 上海虹桥 → 昆明南

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:02.578497+00:00; completeness: full (7 stops).
- Ordered stops: 上海虹桥 (`AOH`) → 杭州东 (`HGH`) → 南昌西 (`NXG`) → 长沙南 (`CWQ`) → 怀化南 (`KAQ`) → 贵阳北 (`KQW`) → 昆明南 (`KOM`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=5l0000G20100&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G201.json`.

### G203 — 南京南 → 贵阳北

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:02.586667+00:00; completeness: full (11 stops).
- Ordered stops: 南京南 (`NKH`) → 无锡东 (`WGH`) → 苏州北 (`OHH`) → 上海虹桥 (`AOH`) → 杭州东 (`HGH`) → 义乌 (`YWH`) → 上饶 (`SRG`) → 南昌西 (`NXG`) → 长沙南 (`CWQ`) → 怀化南 (`KAQ`) → 贵阳北 (`KQW`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=5l0000G20302&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G203.json`.

### G237 — 上海虹桥 → 成都东

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:03.680689+00:00; completeness: full (10 stops).
- Ordered stops: 上海虹桥 (`AOH`) → 杭州东 (`HGH`) → 金华 (`JBH`) → 南昌西 (`NXG`) → 新余北 (`XBG`) → 长沙南 (`CWQ`) → 娄底南 (`UOQ`) → 怀化南 (`KAQ`) → 贵阳东 (`KEW`) → 成都东 (`ICW`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=5l0000G23700&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G237.json`.

### G255 — 上海南 → 厦门北

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:03.773172+00:00; completeness: full (8 stops).
- Ordered stops: 上海南 (`SNH`) → 杭州东 (`HGH`) → 金华 (`JBH`) → 南平市 (`NOS`) → 福州 (`FZS`) → 莆田 (`PTS`) → 泉州东 (`QRS`) → 厦门北 (`XKS`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=550000G25500&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G255.json`.

### G353 — 北京西 → 银川

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:04.771239+00:00; completeness: full (7 stops).
- Ordered stops: 北京西 (`BXP`) → 石家庄 (`SJP`) → 郑州东 (`ZAF`) → 西安北 (`EAY`) → 庆阳 (`QOJ`) → 吴忠 (`WVJ`) → 银川 (`YIJ`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G3&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=240000G35301&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G353.json`.

### G369 — 北京西 → 西安北

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:04.828286+00:00; completeness: full (4 stops).
- Ordered stops: 北京西 (`BXP`) → 石家庄 (`SJP`) → 郑州东 (`ZAF`) → 西安北 (`EAY`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G3&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=240000G36910&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G369.json`.

### G381 — 北京西 → 香港西九龙

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:05.934628+00:00; completeness: full (8 stops).
- Ordered stops: 北京西 (`BXP`) → 石家庄 (`SJP`) → 郑州东 (`ZAF`) → 武汉 (`WHN`) → 长沙南 (`CWQ`) → 广州南 (`IZQ`) → 深圳北 (`IOQ`) → 香港西九龙 (`XJA`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G3&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=240000G38120&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G381.json`.

### G382 — 香港西九龙 → 北京西

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:05.843371+00:00; completeness: full (8 stops).
- Ordered stops: 香港西九龙 (`XJA`) → 深圳北 (`IOQ`) → 广州南 (`IZQ`) → 长沙南 (`CWQ`) → 武汉 (`WHN`) → 郑州东 (`ZAF`) → 石家庄 (`SJP`) → 北京西 (`BXP`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G3&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=6x0000G38200&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G382.json`.

### G383 — 香港西九龙 → 上海虹桥

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:06.896237+00:00; completeness: full (11 stops).
- Ordered stops: 香港西九龙 (`XJA`) → 福田 (`NZQ`) → 深圳北 (`IOQ`) → 广州南 (`IZQ`) → 衡阳东 (`HVQ`) → 长沙南 (`CWQ`) → 武汉 (`WHN`) → 合肥南 (`ENH`) → 南京南 (`NKH`) → 无锡东 (`WGH`) → 上海虹桥 (`AOH`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G3&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=6x0000G38603&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G383.json`.

### G386 — 香港西九龙 → 上海虹桥

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:07.030210+00:00; completeness: full (11 stops).
- Ordered stops: 香港西九龙 (`XJA`) → 福田 (`NZQ`) → 深圳北 (`IOQ`) → 广州南 (`IZQ`) → 衡阳东 (`HVQ`) → 长沙南 (`CWQ`) → 武汉 (`WHN`) → 合肥南 (`ENH`) → 南京南 (`NKH`) → 无锡东 (`WGH`) → 上海虹桥 (`AOH`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G3&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=6x0000G38603&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G386.json`.

### G671 — 北京西 → 西宁

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:08.021276+00:00; completeness: full (14 stops).
- Ordered stops: 北京西 (`BXP`) → 定州东 (`DOP`) → 石家庄 (`SJP`) → 邯郸东 (`HPP`) → 安阳东 (`ADF`) → 郑州东 (`ZAF`) → 洛阳龙门 (`LLF`) → 西安北 (`EAY`) → 杨陵南 (`YEY`) → 宝鸡南 (`BBY`) → 天水南 (`TIJ`) → 通渭 (`TWJ`) → 兰州西 (`LAJ`) → 西宁 (`XNO`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G6&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=240000G67100&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G671.json`.

### G729 — 大连北 → 哈尔滨西

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:08.176055+00:00; completeness: full (11 stops).
- Ordered stops: 大连北 (`DFT`) → 金普 (`PWT`) → 鲅鱼圈 (`BYT`) → 海城西 (`HXT`) → 鞍山西 (`AXT`) → 辽阳 (`LYT`) → 沈阳 (`SYT`) → 铁岭西 (`PXT`) → 昌图西 (`CPT`) → 长春西 (`CRT`) → 哈尔滨西 (`VAB`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G7&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=1g0000G7290L&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G729.json`.

### G903 — 天津西 → 香港西九龙

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:09.170967+00:00; completeness: full (17 stops).
- Ordered stops: 天津西 (`TXP`) → 胜芳 (`SUP`) → 白洋淀 (`FWP`) → 石家庄 (`SJP`) → 邯郸东 (`HPP`) → 郑州东 (`ZAF`) → 武汉 (`WHN`) → 岳阳东 (`YIQ`) → 汨罗东 (`MQQ`) → 长沙南 (`CWQ`) → 株洲西 (`ZAQ`) → 衡阳东 (`HVQ`) → 郴州西 (`ICQ`) → 广州北 (`GBQ`) → 广州南 (`IZQ`) → 深圳北 (`IOQ`) → 香港西九龙 (`XJA`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G9&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=250000G90301&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G903.json`.

### G906 — 香港西九龙 → 重庆西

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:09.312363+00:00; completeness: full (8 stops).
- Ordered stops: 香港西九龙 (`XJA`) → 深圳北 (`IOQ`) → 广州南 (`IZQ`) → 贺州 (`HXZ`) → 桂林西 (`GEZ`) → 贵阳东 (`KEW`) → 遵义 (`ZYE`) → 重庆西 (`CXW`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G9&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=6x0000G90600&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G906.json`.

### G908 — 香港西九龙 → 昆明南

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:10.241004+00:00; completeness: full (6 stops).
- Ordered stops: 香港西九龙 (`XJA`) → 深圳北 (`IOQ`) → 广州南 (`IZQ`) → 桂林西 (`GEZ`) → 贵阳北 (`KQW`) → 昆明南 (`KOM`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G9&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=6x0000G90801&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G908.json`.

### G902 — 香港西九龙 → 上海虹桥

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:10.441412+00:00; completeness: full (11 stops).
- Ordered stops: 香港西九龙 (`XJA`) → 深圳北 (`IOQ`) → 惠州北 (`HUA`) → 河源东 (`HEA`) → 赣州西 (`GOG`) → 南昌东 (`NUG`) → 景德镇北 (`JDG`) → 黄山北 (`NYH`) → 杭州西 (`HVU`) → 苏州南 (`SMU`) → 上海虹桥 (`AOH`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G9&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=6x0000G90200&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G902.json`.

### G1021 — 福州南 → 珠海

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:11.344207+00:00; completeness: full (12 stops).
- Ordered stops: 福州南 (`FYS`) → 莆田 (`PTS`) → 泉州南 (`QNS`) → 厦门北 (`XKS`) → 漳州 (`ZUS`) → 云霄 (`YBS`) → 潮汕 (`CBQ`) → 深圳北 (`IOQ`) → 虎门 (`IUQ`) → 广州南 (`IZQ`) → 中山 (`ZSQ`) → 珠海 (`ZHQ`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=5n000G102103&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G1021.json`.

### G2003 — 济南东 → 兰州西

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:11.534472+00:00; completeness: full (11 stops).
- Ordered stops: 济南东 (`MDK`) → 济南西 (`JGK`) → 聊城西 (`VXK`) → 莘县 (`SNK`) → 濮阳东 (`PUF`) → 郑州东 (`ZAF`) → 洛阳龙门 (`LLF`) → 西安北 (`EAY`) → 宝鸡南 (`BBY`) → 天水南 (`TIJ`) → 兰州西 (`LAJ`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=47000G200601&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G2003.json`.

### G2087 — 烟台 → 成都东

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:12.783656+00:00; completeness: full (36 stops).
- Ordered stops: 烟台 (`YAK`) → 福山 (`FUK`) → 烟台西 (`DCK`) → 蓬莱 (`POK`) → 龙口市 (`UKK`) → 招远 (`VDK`) → 莱州 (`VPK`) → 灰埠 (`KBK`) → 昌邑 (`CRK`) → 潍坊北 (`WJK`) → 青州市北 (`QOK`) → 临淄北 (`UEK`) → 淄博北 (`ZRK`) → 邹平 (`ZLK`) → 济南东 (`MDK`) → 齐河 (`QIK`) → 禹城东 (`YSK`) → 德州东 (`DIP`) → 衡水北 (`IHP`) → 辛集南 (`IJP`) → 藁城南 (`GUP`) → 石家庄 (`SJP`) → 高邑西 (`GNP`) → 邯郸东 (`HPP`) → 安阳东 (`ADF`) → 郑州东 (`ZAF`) → 洛阳龙门 (`LLF`) → 华山北 (`HDY`) → 西安北 (`EAY`) → 鄠邑 (`KXY`) → 洋县西 (`YXY`) → 汉中 (`HOY`) → 广元 (`GYW`) → 绵阳 (`MYW`) → 德阳 (`DYW`) → 成都东 (`ICW`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=49000G20900N&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G2087.json`.

### G3033 — 杭州西 → 汕头

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:12.749530+00:00; completeness: full (14 stops).
- Ordered stops: 杭州西 (`HVU`) → 千岛湖 (`QDU`) → 黄山北 (`NYH`) → 景德镇北 (`JDG`) → 鄱阳 (`POG`) → 南昌东 (`NUG`) → 樟树东 (`ZOG`) → 吉安西 (`JIG`) → 赣州西 (`GOG`) → 五华 (`WHA`) → 梅州西 (`MXA`) → 揭阳 (`JYA`) → 潮汕 (`CBQ`) → 汕头 (`OTQ`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G3&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=56000G303304&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G3033.json`.

### G6045 — 香港西九龙 → 湛江西

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:13.959453+00:00; completeness: full (12 stops).
- Ordered stops: 香港西九龙 (`XJA`) → 福田 (`NZQ`) → 深圳北 (`IOQ`) → 虎门 (`IUQ`) → 广州南 (`IZQ`) → 江门 (`JOQ`) → 台山 (`PUQ`) → 开平南 (`PVQ`) → 恩平 (`PXQ`) → 阳江 (`WRQ`) → 茂名 (`MDQ`) → 湛江西 (`ZWQ`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G6&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=6x000G604806&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G6045.json`.

### G6079 — 张家界西 → 香港西九龙

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:14.026427+00:00; completeness: full (15 stops).
- Ordered stops: 张家界西 (`JXA`) → 芙蓉镇 (`FRA`) → 吉首东 (`JDA`) → 凤凰古城 (`FCA`) → 怀化南 (`KAQ`) → 洞口 (`DKA`) → 邵阳 (`SYQ`) → 衡阳东 (`HVQ`) → 耒阳西 (`LPQ`) → 韶关 (`SNQ`) → 广州北 (`GBQ`) → 广州南 (`IZQ`) → 虎门 (`IUQ`) → 深圳北 (`IOQ`) → 香港西九龙 (`XJA`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G6&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=64000G607905&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G6079.json`.

### G7001 — 南京 → 上海

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:14.997844+00:00; completeness: full (5 stops).
- Ordered stops: 南京 (`NJH`) → 常州 (`CZH`) → 无锡 (`WXH`) → 苏州 (`SZH`) → 上海 (`SHH`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G7&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=54000G700194&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G7001.json`.

### G8002 — 长春 → 大连北

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:15.288248+00:00; completeness: full (11 stops).
- Ordered stops: 长春 (`CCT`) → 四平东 (`PPT`) → 昌图西 (`CPT`) → 铁岭西 (`PXT`) → 沈阳北 (`SBT`) → 沈阳 (`SYT`) → 鞍山西 (`AXT`) → 营口东 (`YGT`) → 鲅鱼圈 (`BYT`) → 瓦房店西 (`WXT`) → 大连北 (`DFT`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=G8&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=11000G80020F&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-G8002.json`.

### D1 — 北京西 → 长沙

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:16.061188+00:00; completeness: full (6 stops).
- Ordered stops: 北京西 (`BXP`) → 石家庄 (`SJP`) → 郑州 (`ZZF`) → 武昌 (`WCN`) → 岳阳 (`YYQ`) → 长沙 (`CSQ`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=24000000D131&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D1.json`.

### D69 — 北京西 → 乌鲁木齐

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:16.527968+00:00; completeness: full (15 stops).
- Ordered stops: 北京西 (`BXP`) → 保定 (`BDP`) → 石家庄北 (`VVP`) → 阳泉北 (`YPP`) → 太原 (`TYV`) → 吕梁 (`LHV`) → 绥德 (`ODY`) → 靖边 (`JIY`) → 定边 (`DYJ`) → 武威 (`WUJ`) → 金昌 (`JCJ`) → 嘉峪关 (`JGJ`) → 哈密 (`HMR`) → 吐鲁番北 (`TAR`) → 乌鲁木齐 (`WAR`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D6&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=2400000D6900&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D69.json`.

### D239 — 成都南 → 香格里拉

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:17.101321+00:00; completeness: full (8 stops).
- Ordered stops: 成都南 (`CNW`) → 西昌西 (`XCE`) → 攀枝花南 (`PNE`) → 广通北 (`GPM`) → 楚雄 (`CUM`) → 丽江 (`LHM`) → 小中甸 (`EDM`) → 香格里拉 (`EUM`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=760000D23901&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D239.json`.

### D271 — 成都南 → 西双版纳

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:17.677740+00:00; completeness: full (15 stops).
- Ordered stops: 成都南 (`CNW`) → 彭山 (`PSW`) → 西昌西 (`XCE`) → 德昌西 (`DXE`) → 米易东 (`MDE`) → 盐边 (`YBE`) → 攀枝花南 (`PNE`) → 元谋西 (`AMM`) → 广通北 (`GPM`) → 禄丰南 (`LQM`) → 昆明 (`KMM`) → 昆明南 (`KOM`) → 玉溪 (`AXM`) → 普洱 (`PEM`) → 西双版纳 (`ENM`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=760000D27104&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D271.json`.

### D575 — 兰州西 → 乌鲁木齐

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:18.259912+00:00; completeness: full (12 stops).
- Ordered stops: 兰州西 (`LAJ`) → 西宁 (`XNO`) → 山丹马场 (`JEJ`) → 民乐 (`MBJ`) → 张掖西 (`ZEJ`) → 酒泉南 (`JNJ`) → 嘉峪关南 (`JBJ`) → 玉门 (`YXJ`) → 柳园南 (`LNR`) → 哈密 (`HMR`) → 吐鲁番北 (`TAR`) → 乌鲁木齐 (`WAR`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D5&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=8d0000D57500&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D575.json`.

### D954 — 成都东 → 上海

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:18.764423+00:00; completeness: full (10 stops).
- Ordered stops: 成都东 (`ICW`) → 重庆北 (`CUW`) → 恩施 (`ESN`) → 宜昌东 (`HAN`) → 汉口 (`HKN`) → 合肥南 (`ENH`) → 南京南 (`NKH`) → 常州 (`CZH`) → 苏州 (`SZH`) → 上海 (`SHH`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D9&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=760000D95406&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D954.json`.

### D1067 — 北京北 → 银川

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:19.345621+00:00; completeness: full (8 stops).
- Ordered stops: 北京北 (`VAP`) → 张家口 (`ZMP`) → 乌兰察布 (`WPC`) → 呼和浩特东 (`NDC`) → 包头 (`BTC`) → 巴彦淖尔 (`FMC`) → 乌海 (`IAC`) → 银川 (`YIJ`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=24000D106701&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D1067.json`.

### D1077 — 清河 → 包头

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:19.821783+00:00; completeness: full (11 stops).
- Ordered stops: 清河 (`QIP`) → 东花园北 (`QBP`) → 宣化北 (`VJP`) → 张家口 (`ZMP`) → 兴和北 (`EBC`) → 乌兰察布 (`WPC`) → 呼和浩特东 (`NDC`) → 呼和浩特 (`HHC`) → 萨拉齐 (`SLC`) → 包头东 (`BDC`) → 包头 (`BTC`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=24000D107703&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D1077.json`.

### D1201 — 成都东 → 包头

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:20.555923+00:00; completeness: full (22 stops).
- Ordered stops: 成都东 (`ICW`) → 罗江东 (`IKW`) → 绵阳 (`MYW`) → 江油 (`JFW`) → 广元 (`GYW`) → 宁强南 (`NOY`) → 汉中 (`HOY`) → 城固北 (`CBY`) → 鄠邑 (`KXY`) → 西安北 (`EAY`) → 咸阳北 (`EBY`) → 乾县 (`QBY`) → 宁县 (`AXJ`) → 庆阳 (`QOJ`) → 环县 (`KXJ`) → 惠安堡 (`KBJ`) → 河东机场 (`HFJ`) → 银川 (`YIJ`) → 石嘴山 (`OZJ`) → 乌海 (`IAC`) → 巴彦淖尔 (`FMC`) → 包头 (`BTC`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=76000D120401&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D1201.json`.

### D2248 — 巴中东 → 杭州东

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:21.072829+00:00; completeness: full (21 stops).
- Ordered stops: 巴中东 (`BDE`) → 南充北 (`NCE`) → 重庆北 (`CUW`) → 恩施 (`ESN`) → 建始 (`JRN`) → 高坪 (`GGN`) → 野三关 (`BNN`) → 宜昌东 (`HAN`) → 荆州 (`JBN`) → 仙桃西 (`XAN`) → 汉口 (`HKN`) → 红安西 (`VXN`) → 金寨 (`JZH`) → 六安 (`UAH`) → 合肥南 (`ENH`) → 全椒 (`INH`) → 南京南 (`NKH`) → 句容西 (`JWH`) → 溧水 (`LDH`) → 德清 (`DRH`) → 杭州东 (`HGH`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=76000D224502&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D2248.json`.

### D3060 — 上海南 → 汉口

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:21.720432+00:00; completeness: full (13 stops).
- Ordered stops: 上海南 (`SNH`) → 上海虹桥 (`AOH`) → 昆山南 (`KNH`) → 苏州 (`SZH`) → 常州 (`CZH`) → 镇江 (`ZJH`) → 南京南 (`NKH`) → 全椒 (`INH`) → 合肥南 (`ENH`) → 六安 (`UAH`) → 麻城北 (`MBN`) → 红安西 (`VXN`) → 汉口 (`HKN`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D3&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=55000D306003&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D3060.json`.

### D3289 — 武汉 → 厦门北

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:22.409841+00:00; completeness: full (20 stops).
- Ordered stops: 武汉 (`WHN`) → 鄂州 (`ECN`) → 黄石北 (`KSN`) → 大冶北 (`DBN`) → 阳新 (`YON`) → 庐山 (`LSG`) → 德安 (`DAG`) → 永修 (`ACG`) → 南昌西 (`NXG`) → 抚州 (`FZG`) → 南城 (`NDG`) → 南丰 (`NFG`) → 泰宁 (`TNS`) → 将乐 (`JLS`) → 三明北 (`SHS`) → 尤溪 (`YXS`) → 永泰 (`YTS`) → 仙游 (`XWS`) → 泉州 (`QYS`) → 厦门北 (`XKS`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D3&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=4e000D32890D&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D3289.json`.

### D7149 — 广州东 → 汕头

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:22.806346+00:00; completeness: full (9 stops).
- Ordered stops: 广州东 (`GGQ`) → 广州新塘 (`XWQ`) → 惠州南 (`KNA`) → 惠东 (`KDA`) → 汕尾 (`OGQ`) → 陆丰 (`LLQ`) → 潮阳 (`CNQ`) → 潮汕 (`CBQ`) → 汕头 (`OTQ`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D7&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=65000D71520I&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D7149.json`.

### D8306 — 北海 → 南宁东

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:23.541891+00:00; completeness: full (3 stops).
- Ordered stops: 北海 (`BHZ`) → 钦州东 (`QDZ`) → 南宁东 (`NFZ`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D8&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=73000D83060H&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D8306.json`.

### D920 — 南宁东 → 北京西

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:24.709308+00:00; completeness: full (9 stops).
- Ordered stops: 南宁东 (`NFZ`) → 柳州 (`LZZ`) → 桂林北 (`GBZ`) → 永州 (`AOQ`) → 祁阳 (`QWQ`) → 祁东 (`QMQ`) → 长沙南 (`CWQ`) → 石家庄 (`SJP`) → 北京西 (`BXP`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=D9&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=710000D92007&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-D920.json`.

### C15 — 黄龙九寨 → 成都东

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:24.572232+00:00; completeness: full (2 stops).
- Ordered stops: 黄龙九寨 (`HIE`) → 成都东 (`ICW`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=7600000C1801&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C15.json`.

### C85 — 香格里拉 → 昆明

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:25.593868+00:00; completeness: full (3 stops).
- Ordered stops: 香格里拉 (`EUM`) → 丽江 (`LHM`) → 昆明 (`KMM`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C8&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=8c00000C8802&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C85.json`.

### C118 — 昆明 → 香格里拉

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:25.766513+00:00; completeness: full (4 stops).
- Ordered stops: 昆明 (`KMM`) → 丽江 (`LHM`) → 小中甸 (`EDM`) → 香格里拉 (`EUM`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=800000C11807&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C118.json`.

### C202 — 西安 → 神木

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:26.682872+00:00; completeness: full (9 stops).
- Ordered stops: 西安 (`XAY`) → 蒲城东 (`PEY`) → 延安 (`YWY`) → 清涧县 (`QNY`) → 绥德 (`ODY`) → 米脂 (`MEY`) → 榆林 (`ALY`) → 锦界 (`JEY`) → 神木 (`HMY`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=410000C2020F&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C202.json`.

### C293 — 昆明 → 西双版纳

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:26.807422+00:00; completeness: full (6 stops).
- Ordered stops: 昆明 (`KMM`) → 昆明南 (`KOM`) → 元江 (`AJM`) → 宁洱 (`NEM`) → 普洱 (`PEM`) → 西双版纳 (`ENM`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=800000C29603&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C293.json`.

### C319 — 大理 → 丽江

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:28.113889+00:00; completeness: full (2 stops).
- Ordered stops: 大理 (`DKM`) → 丽江 (`LHM`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C3&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=8c0000C31909&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C319.json`.

### C541 — 大连北 → 丹东

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:27.974317+00:00; completeness: full (12 stops).
- Ordered stops: 大连北 (`DFT`) → 金州 (`JZT`) → 登沙河 (`DWT`) → 杏树屯 (`XDT`) → 皮口 (`PUT`) → 城子坦 (`CWT`) → 花园口 (`HYT`) → 庄河北 (`ZUT`) → 大孤山 (`RMT`) → 北井子 (`BRT`) → 东港北 (`RGT`) → 丹东 (`DUT`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C5&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=1g0000C54106&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C541.json`.

### C649 — 呼和浩特东 → 鄂尔多斯

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:29.105911+00:00; completeness: full (6 stops).
- Ordered stops: 呼和浩特东 (`NDC`) → 呼和浩特 (`HHC`) → 托克托东 (`TVC`) → 准格尔 (`ZEC`) → 东胜东 (`RSC`) → 鄂尔多斯 (`EEC`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C6&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=330000C64903&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C649.json`.

### C875 — 福州 → 厦门

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:29.278523+00:00; completeness: full (11 stops).
- Ordered stops: 福州 (`FZS`) → 三明北 (`SHS`) → 泰宁 (`TNS`) → 建宁县北 (`JCS`) → 水茜 (`SSS`) → 宁化 (`NHS`) → 清流 (`QLS`) → 杨源 (`AYS`) → 冠豸山 (`GPS`) → 龙岩 (`LYS`) → 厦门 (`XMS`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C8&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=580000C87808&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C875.json`.

### C881 — 拉萨 → 林芝

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:30.250288+00:00; completeness: full (6 stops).
- Ordered stops: 拉萨 (`LSO`) → 山南 (`SAO`) → 加查 (`JIO`) → 朗县 (`LIO`) → 米林 (`MIO`) → 林芝 (`LZO`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C8&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=880000C88103&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C881.json`.

### C883 — 拉萨 → 日喀则

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:30.291855+00:00; completeness: full (2 stops).
- Ordered stops: 拉萨 (`LSO`) → 日喀则 (`RKO`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C8&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=880000C88320&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C883.json`.

### C1001 — 长春 → 延吉西

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:31.288973+00:00; completeness: full (4 stops).
- Ordered stops: 长春 (`CCT`) → 吉林 (`JLL`) → 蛟河西 (`JOL`) → 延吉西 (`YXL`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C1&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=11000C10010F&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C1001.json`.

### C2136 — 天津西 → 北京南

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:31.284533+00:00; completeness: full (2 stops).
- Ordered stops: 天津西 (`TXP`) → 北京南 (`VNP`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C2&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=25000C213623&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C2136.json`.

### C3005 — 南京南 → 上海南

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:32.440616+00:00; completeness: full (8 stops).
- Ordered stops: 南京南 (`NKH`) → 溧阳 (`LEH`) → 宜兴 (`YUH`) → 湖州东 (`HKU`) → 湖州南浔 (`KIU`) → 盛泽 (`SJU`) → 苏州南 (`SMU`) → 上海南 (`SNH`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C3&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=5l000C300501&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C3005.json`.

### C4802 — 竹料 → 白云机场北

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:32.311663+00:00; completeness: full (3 stops).
- Ordered stops: 竹料 (`ZUA`) → 白云机场东 (`BDA`) → 白云机场北 (`BBA`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C4&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=6t000C480206&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C4802.json`.

### C6132 — 雅安 → 泸州

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:33.417540+00:00; completeness: full (8 stops).
- Ordered stops: 雅安 (`YAE`) → 朝阳湖 (`CYE`) → 邛崃 (`QLE`) → 崇州 (`CZE`) → 成都东 (`ICW`) → 自贡 (`ZGE`) → 富顺 (`FSE`) → 泸州 (`LUE`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C6&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=76000C61320B&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C6132.json`.

### C7099 — 广州北 → 深圳

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:33.499203+00:00; completeness: full (7 stops).
- Ordered stops: 广州北 (`GBQ`) → 广州白云 (`GBA`) → 广州东 (`GGQ`) → 广州新塘 (`XWQ`) → 常平 (`DAQ`) → 平湖 (`PHQ`) → 深圳 (`SZQ`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C7&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=63000C709903&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C7099.json`.

### C9317 — 西安东 → 安康西

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:34.443542+00:00; completeness: full (5 stops).
- Ordered stops: 西安东 (`XDY`) → 牛背梁 (`NGY`) → 柞水西 (`ZCY`) → 镇安西 (`ZTY`) → 安康西 (`APY`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C9&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=41000C931702&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C9317.json`.

### C9685 — 银川 → 中卫南

- Service date: 2026-10-18; retrieved 2026-10-18T20:24:34.638347+00:00; completeness: full (5 stops).
- Ordered stops: 银川 (`YIJ`) → 河东机场 (`HFJ`) → 吴忠 (`WVJ`) → 中宁东 (`ZDJ`) → 中卫南 (`ZTJ`).
- Sources: [official train search](https://search.12306.cn/search/v1/train/search?keyword=C9&date=20261018), [official stop sequence](https://kyfw.12306.cn/otn/queryTrainInfo/query?leftTicketDTO.train_no=87000C968500&leftTicketDTO.train_date=2026-10-18&rand_code=).
- Raw: `railway-sources/local/china/evidence/real-train-paths-20261018/highspeed-raw/stops-C9685.json`.

## Unavailable candidates

Candidates were not substituted with invented data: `[{"missingTrainNumber": "D910"}, {"missingTrainNumber": "C7301"}]`.
