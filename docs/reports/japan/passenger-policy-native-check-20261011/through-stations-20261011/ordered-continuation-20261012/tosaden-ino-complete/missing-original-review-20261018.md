# 伊野線补采原图复核（2026-10-18）

实际逐对查看 **38/38视点、76张basemap/smooth原始PNG**，分别用`functions.view_image`打开，没有裁切/拼图或修改像素。精确本线`jp-とさでん交通-伊野線`，15个补采区间；本轮没有重看原41个legacy视点，不能写成整线79视点视觉通过。

采集根目录`/private/tmp/jtm-tosaden-ino-missing-20261018`。run-status evidenceReady、dependenciesVerified true、38/38 captured、0 failed；invocation `0CBB9516-820E-4E01-95D9-CF509B63F494`。标准/light/z17/1600×1200。逐视点named identity source/display坐标及from/to station IDs与current own line一致，76个原PNG实际文件大小与receipt一致，未重算hash。成功凭据只证明可用性；下面是实际看图结论。

**没有已确权可直接修复的孤立假V、直角、回头、断口或错线跳接。** 西段#0/#6/#9–12普遍可见红线比底图自身电车线偏北，局部把街道缓弯概化成肩部；这是后续来源核对线索，不能仅以标准底图蓝符中心改线。本轮没有identified own passenger waychain、raw N02窗口和边界证据，故不提出source-ready修复。朝倉后逐渐更贴近自身街道路廊，市区#18/#21/#25–28红线略偏南，也未测量或确认为错误轨道。

#17鴨部→鏡川橋的东行→北行跨镜川→东转，#18桥北国道33号曲线，都是自身电车街道走向；不能把真实转弯当作假直角抹去。JR土讃线在朝倉北侧另走独立弧线，镜川JR桥在电车桥西侧；红线没有沿最近JR轨符跳接。

#32堀詰→はりまや橋从西沿东西向街道接近交叉口，红线维持东西向并止于该本线东端，未转入北向駅前線或南向桟橋線。图中十字街道、站名与蓝色电车符可用于区分方向，但本轮不证明十字道岔的物理连接、各乘客站台face、精确端帽或surveyed centre。标准地图也不能作为地下/桥梁工程位置的测量证明。

## 实际查看清单

每行两张原PNG均已打开；完整绝对路径、camera、身份和receipt字节数见`missing-viewed-originals-20261018.json`。重复端点地理视野均独立打开，但不扩大地理覆盖声明。

| Own interval | Stations | Point | 原图目录 | 实际观察 |
|---|---|---:|---|---|
| #0 | 伊野→伊野駅前 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000000/000000` (`basemap.png`, `smooth.png`) | 伊野终端/伊野駅前本线向东街道：红线北于蓝色电车符；JR土讃线南侧独立。无独立V，终端帽端和位置差未确权。 |
| #0 | 伊野→伊野駅前 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000000/000001` (`basemap.png`, `smooth.png`) | 伊野终端/伊野駅前本线向东街道：红线北于蓝色电车符；JR土讃线南侧独立。无独立V，终端帽端和位置差未确权。 |
| #6 | 枝川→中山 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000013/000000` (`basemap.png`, `smooth.png`) | 枝川→中山本线沿194号街道真实缓弯；红线偏北，JR南侧独立。未见孤立V或跳入JR，偏移待own source。 |
| #6 | 枝川→中山 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000013/000001` (`basemap.png`, `smooth.png`) | 枝川→中山本线沿194号街道真实缓弯；红线偏北，JR南侧独立。未见孤立V或跳入JR，偏移待own source。 |
| #9 | 宇治団地前→咥内 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000014/000000` (`basemap.png`, `smooth.png`) | 宇治団地前→咥内沿386号街道真实起伏/缓弯，红线较电车符偏北；土讃线独立弧线不可借用。未见独立V，偏移待来源。 |
| #9 | 宇治団地前→咥内 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000014/000001` (`basemap.png`, `smooth.png`) | 宇治団地前→咥内沿386号街道真实起伏/缓弯，红线较电车符偏北；土讃线独立弧线不可借用。未见独立V，偏移待来源。 |
| #9 | 宇治団地前→咥内 | 2 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000014/000002` (`basemap.png`, `smooth.png`) | 宇治団地前→咥内沿386号街道真实起伏/缓弯，红线较电车符偏北；土讃线独立弧线不可借用。未见独立V，偏移待来源。 |
| #9 | 宇治団地前→咥内 | 3 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000014/000003` (`basemap.png`, `smooth.png`) | 宇治団地前→咥内沿386号街道真实起伏/缓弯，红线较电车符偏北；土讃线独立弧线不可借用。未见独立V，偏移待来源。 |
| #10 | 咥内→宮の奥 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000001/000000` (`basemap.png`, `smooth.png`) | 咥内→宮の奥本线沿386号街道，保留真实曲线；红线偏北，有概化肩部但未见孤立假V。土讃线在北侧，未混接。 |
| #10 | 咥内→宮の奥 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000001/000001` (`basemap.png`, `smooth.png`) | 咥内→宮の奥本线沿386号街道，保留真实曲线；红线偏北，有概化肩部但未见孤立假V。土讃线在北侧，未混接。 |
| #10 | 咥内→宮の奥 | 2 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000001/000002` (`basemap.png`, `smooth.png`) | 咥内→宮の奥本线沿386号街道，保留真实曲线；红线偏北，有概化肩部但未见孤立假V。土讃线在北侧，未混接。 |
| #11 | 宮の奥→朝倉神社前 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000002/000000` (`basemap.png`, `smooth.png`) | 宮の奥→朝倉神社前真实街道曲线，红线偏北，东侧与朝倉街道连续；北侧JR独立，不按邻近轨符改线。 |
| #11 | 宮の奥→朝倉神社前 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000002/000001` (`basemap.png`, `smooth.png`) | 宮の奥→朝倉神社前真实街道曲线，红线偏北，东侧与朝倉街道连续；北侧JR独立，不按邻近轨符改线。 |
| #11 | 宮の奥→朝倉神社前 | 2 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000002/000002` (`basemap.png`, `smooth.png`) | 宮の奥→朝倉神社前真实街道曲线，红线偏北，东侧与朝倉街道连续；北侧JR独立，不按邻近轨符改线。 |
| #12 | 朝倉神社前→朝倉駅前 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000003/000000` (`basemap.png`, `smooth.png`) | 朝倉神社前→朝倉駅前本线向东南再向东的真实街道曲线；红线逐渐接近底图电车线，北侧JR弧线独立。未见接缝V/直角。 |
| #12 | 朝倉神社前→朝倉駅前 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000003/000001` (`basemap.png`, `smooth.png`) | 朝倉神社前→朝倉駅前本线向东南再向东的真实街道曲线；红线逐渐接近底图电车线，北侧JR弧线独立。未见接缝V/直角。 |
| #12 | 朝倉神社前→朝倉駅前 | 2 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000003/000002` (`basemap.png`, `smooth.png`) | 朝倉神社前→朝倉駅前本线向东南再向东的真实街道曲线；红线逐渐接近底图电车线，北侧JR弧线独立。未见接缝V/直角。 |
| #13 | 朝倉駅前→朝倉 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000004/000000` (`basemap.png`, `smooth.png`) | 朝倉駅前→朝倉沿274号向东街道连续，西端真实反弯保留；不借北侧JR走向，站台face/caps未证实。 |
| #13 | 朝倉駅前→朝倉 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000004/000001` (`basemap.png`, `smooth.png`) | 朝倉駅前→朝倉沿274号向东街道连续，西端真实反弯保留；不借北侧JR走向，站台face/caps未证实。 |
| #17 | 鴨部→鏡川橋 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000005/000000` (`basemap.png`, `smooth.png`) | 鴨部→鏡川橋沿274号街道东行后向北过镜川，再向东，真实大转弯必须保留。红连续，无孤立V，JR桥在西侧独立。 |
| #17 | 鴨部→鏡川橋 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000005/000001` (`basemap.png`, `smooth.png`) | 鴨部→鏡川橋沿274号街道东行后向北过镜川，再向东，真实大转弯必须保留。红连续，无孤立V，JR桥在西侧独立。 |
| #17 | 鴨部→鏡川橋 | 2 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000005/000002` (`basemap.png`, `smooth.png`) | 鴨部→鏡川橋沿274号街道东行后向北过镜川，再向东，真实大转弯必须保留。红连续，无孤立V，JR桥在西侧独立。 |
| #18 | 鏡川橋→蛍橋 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000006/000000` (`basemap.png`, `smooth.png`) | 鏡川橋→蛍橋本线桥北真实东转及国道33号缓弯；红线稍偏南但没有回头或跳入北侧JR。 |
| #18 | 鏡川橋→蛍橋 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000006/000001` (`basemap.png`, `smooth.png`) | 鏡川橋→蛍橋本线桥北真实东转及国道33号缓弯；红线稍偏南但没有回头或跳入北侧JR。 |
| #18 | 鏡川橋→蛍橋 | 2 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000006/000002` (`basemap.png`, `smooth.png`) | 鏡川橋→蛍橋本线桥北真实东转及国道33号缓弯；红线稍偏南但没有回头或跳入北侧JR。 |
| #21 | 旭駅前通→旭町一丁目 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000007/000000` (`basemap.png`, `smooth.png`) | 旭駅前通→旭町一丁目沿33号街道向东，真实轻微曲线保留；红线平行稍偏南，无孤立尖角或北侧JR混接。 |
| #21 | 旭駅前通→旭町一丁目 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000007/000001` (`basemap.png`, `smooth.png`) | 旭駅前通→旭町一丁目沿33号街道向东，真实轻微曲线保留；红线平行稍偏南，无孤立尖角或北侧JR混接。 |
| #21 | 旭駅前通→旭町一丁目 | 2 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000007/000002` (`basemap.png`, `smooth.png`) | 旭駅前通→旭町一丁目沿33号街道向东，真实轻微曲线保留；红线平行稍偏南，无孤立尖角或北侧JR混接。 |
| #25 | 上町二丁目→上町一丁目 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000008/000000` (`basemap.png`, `smooth.png`) | 上町二丁目→上町一丁目沿东西街道，红线略偏南，方向连续，未见站间接缝钩；宽站符不证明帽端。 |
| #25 | 上町二丁目→上町一丁目 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000008/000001` (`basemap.png`, `smooth.png`) | 上町二丁目→上町一丁目沿东西街道，红线略偏南，方向连续，未见站间接缝钩；宽站符不证明帽端。 |
| #26 | 上町一丁目→枡形 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000009/000000` (`basemap.png`, `smooth.png`) | 上町一丁目→枡形本线东西街道，向东北缓转是真实街道变化；红连续，无直角/邻线跳接。 |
| #26 | 上町一丁目→枡形 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000009/000001` (`basemap.png`, `smooth.png`) | 上町一丁目→枡形本线东西街道，向东北缓转是真实街道变化；红连续，无直角/邻线跳接。 |
| #27 | 枡形→グランド通 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000010/000000` (`basemap.png`, `smooth.png`) | 枡形→グランド通沿真实街道向东北，红线平行稍偏南；无假V，不能拉直街道缓弯。 |
| #27 | 枡形→グランド通 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000010/000001` (`basemap.png`, `smooth.png`) | 枡形→グランド通沿真实街道向东北，红线平行稍偏南；无假V，不能拉直街道缓弯。 |
| #28 | グランド通→県庁前 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000011/000000` (`basemap.png`, `smooth.png`) | グランド通→県庁前保持东西/东北街道方向，红线连续，未见尖角或错接；精确平台端未证实。 |
| #28 | グランド通→県庁前 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000011/000001` (`basemap.png`, `smooth.png`) | グランド通→県庁前保持东西/东北街道方向，红线连续，未见尖角或错接；精确平台端未证实。 |
| #32 | 堀詰→はりまや橋 | 0 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000012/000000` (`basemap.png`, `smooth.png`) | 堀詰→はりまや橋从西沿东西向街道接近十字路口；红线止于本线东端，未转入北向駅前或南向桟橋臂。未见假V；十字道岔实际连接/站台face仍未验收。 |
| #32 | 堀詰→はりまや橋 | 1 | `/private/tmp/jtm-tosaden-ino-missing-20261018/alignment/captures/000012/000001` (`basemap.png`, `smooth.png`) | 堀詰→はりまや橋从西沿东西向街道接近十字路口；红线止于本线东端，未转入北向駅前或南向桟橋臂。未见假V；十字道岔实际连接/站台face仍未验收。 |

仅写本报告与manifest；未启动native/app/build/tests，未改源码、生产几何或其他scope。
