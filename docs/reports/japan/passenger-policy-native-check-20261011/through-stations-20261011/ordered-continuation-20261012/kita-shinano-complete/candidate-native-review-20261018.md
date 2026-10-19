# 北しなの線候选：旧69短台阶删除原图复核（2026-10-18）

实际查看候选 **26/26对、52张basemap/smooth原始PNG**，另独立打开冻结historical p14的两张原PNG作比较。所有图片逐张用`functions.view_image`打开，没有裁切、拼图或修改像素。精确本线`jp-しなの鉄道-北しなの線` #0 妙高高原001746→黒姫001788；仅该候选区间，未验收其他区间。

采集目录`/private/tmp/jtm-kita-shinano-step-native-20261018`已evidenceReady，26/26 captured、0failed，dependenciesVerified true，invocation `E2F53A26-52EF-441B-A788-E8259DADDBDC`。light/standard/z17/1600×1200。逐个named identity的physical/source114点精确等于冻结old interval、display113点精确等于仅删除旧decoded69、两端station IDs一致；52个PNG存在且实际byteCount与receipt匹配。未重算hash。采集完成和身份匹配本身不是像素验收。

## 有界图像结论

**支持仅删除旧decodedvertex69的短右台阶。** historical p14 smooth在本线近南北直段上存在红色短横向右阶，basemap的Apple-labelled自身Kita Shinano蓝符连续；候选p14在相应位置红线连续通过，没有短横腿、回头或缺口。候选p13、p15也实际查看，两侧保留弧/近直段没有为此删除产生新V、钩或断口。数据身份明确保留旧68及所有其他控制，冻结guard66/67/68/70/71；该保留事实来自named coordinates与frozen evidence比较，不能只靠图像推断。

本轮肯定结论只覆盖这一个短台阶的显示处理。目标上方p11–14已有较宽红线东偏仍然保留，熊坂p3–9部分弧段也有持续侧偏/红蓝交叉，妙高高原南侧与黑姬站廊仍有小位置差；没有把这些范围外偏移接受为准确线路中心，也没有为贴蓝符拉直真弯。尤其不把OSM的另一个约70m位置作为平移依据。本次不是全物理中心、工程/地下隧道位置、乘客平台face/caps或整线/Main像素验收。

候选p0–12保留妙高高原南出站、熊坂连续弧线及18号跨越前后反弯；p16–25保留野尻近直段、赤渋→熊倉→黒姫真实东南弧和站场进出方向。未见新的孤立V、横钩、断口或跳到道路/北侧妙高はねうま走廊。底图宽站场填色不证明平台归属；山地区域标准图符也不证明地表可见、隧道或高程。

历史对照来自`vertex68-own-source-20261018/apple-p14-basemap.png`与`apple-p14-smooth.png`（1024×768）；候选1600×1200，因此不是相同像素坐标逐像素差分，未声明测得像素残差或新的米数。parent提供的原约6m量级不作为本轮重新测量结果。

## 实际查看清单

每行两张PNG均实际打开，完整绝对路径、camera、identity、receipt和观察见`candidate-native-viewed-originals-20261018.json`。另有上述历史2张原图独立记录。

| Point | 原图目录 | 实际观察 |
|---:|---|---|
| 0 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000000` (`basemap.png`, `smooth.png`) | 妙高高原自身端点与南向出站：红线走本线南向，妙高はねうま线北向另标；站台面/共用端点物理归属未证明。 |
| 1 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000001` (`basemap.png`, `smooth.png`) | 妙高高原南侧近直线段与北端缓弯，红线偏西于蓝符，未见断口或跳邻线；非本次位置验收。 |
| 2 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000002` (`basemap.png`, `smooth.png`) | 関川东侧近直段接南侧真缓弯，红连续，旧宽侧偏保留。 |
| 3 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000003` (`basemap.png`, `smooth.png`) | 熊坂北侧真南→西南缓弯，红东偏明显但连续，未被本次修正或接受。 |
| 4 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000004` (`basemap.png`, `smooth.png`) | 熊坂西南向真弯与北侧近直段连续，原有红蓝宽偏保留，无新V。 |
| 5 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000005` (`basemap.png`, `smooth.png`) | 熊坂真实西南→西向弧线保留；红蓝交叉及局部偏移仍在，不能宣称全弧准确。 |
| 6 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000006` (`basemap.png`, `smooth.png`) | 熊坂南侧真弧与直段，红北偏较蓝符，未见新短横或回头。 |
| 7 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000007` (`basemap.png`, `smooth.png`) | 跨国道18号前后保留真反弯，红北/东偏位置差保留；没有转入道路。 |
| 8 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000008` (`basemap.png`, `smooth.png`) | 国道18号跨越上下文、东侧真缓弯保留，红连续，无新V。 |
| 9 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000009` (`basemap.png`, `smooth.png`) | 18号以南本线真缓弯接直段，红连续，残余侧偏不作准确性验收。 |
| 10 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000010` (`basemap.png`, `smooth.png`) | 高速公路东侧北南向真缓弯，红连续，无孤立新钩。 |
| 11 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000011` (`basemap.png`, `smooth.png`) | 目标以北自身连续缓曲，较底图蓝符有宽东偏，保持既有形态；本次不接受整段中心。 |
| 12 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000012` (`basemap.png`, `smooth.png`) | 目标以北保留长弧：红较蓝符东偏明显，无突然横向新接缝；范围外未验收。 |
| 13 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000013` (`basemap.png`, `smooth.png`) | 目标北侧保留弧到直段；红东偏在目标上方保留，进入目标段连续，无新钩。 |
| 14 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000014` (`basemap.png`, `smooth.png`) | 关键目标视点：旧decoded69红色短右台阶已不可见；经过保留68到70的红线连续，没有短横腿、回头或缺口。宽东偏上段仍保留，非全线中心验收。 |
| 15 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000015` (`basemap.png`, `smooth.png`) | 目标南侧近直段及后继真缓弯，红线连续，没有为删除69产生新V或横接缝。 |
| 16 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000016` (`basemap.png`, `smooth.png`) | 野尻北侧真缓弯及南侧长直线，红连续，未出现新孤立角点。 |
| 17 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000017` (`basemap.png`, `smooth.png`) | 六月/野尻长直段、高速穿越北侧上下文，红连续，未跳到公路。 |
| 18 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000018` (`basemap.png`, `smooth.png`) | 高速交叉与119号路附近长直段，红沿本线连续；工程高程/地下位置未证明。 |
| 19 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000019` (`basemap.png`, `smooth.png`) | 信濃町IC西侧长直段接南侧真弯，红连续，无新钩。 |
| 20 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000020` (`basemap.png`, `smooth.png`) | 赤渋北侧南→东南真弯保留，红连续，无新V；侧偏仍非测量证明。 |
| 21 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000021` (`basemap.png`, `smooth.png`) | 赤渋→熊倉南东向真弯保持，红没有跳入18号道路。 |
| 22 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000022` (`basemap.png`, `smooth.png`) | 熊倉/みどりが丘东南向进黑姬廊道连续，红稍偏西南，未新改站场方向。 |
| 23 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000023` (`basemap.png`, `smooth.png`) | 黑姬北侧进站真缓弯到斜直段连续，无新帽端钩；站台face未证明。 |
| 24 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000024` (`basemap.png`, `smooth.png`) | 黑姬自身站场及两侧东南向斜直段，红连续，宽蓝站填色不证明具体乘客平台/caps。 |
| 25 | `/private/tmp/jtm-kita-shinano-step-native-20261018/alignment/captures/000000/000025` (`basemap.png`, `smooth.png`) | 黑姬自身区间终点和南端上下文：红连续进入站廊，无新断口/横钩；后继区间与整线不在本次验收。 |

本轮只写报告与manifest，无源码/production编辑，无apply/tests/native/app/build操作。
