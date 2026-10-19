# 南リアス#3 恋し浜→甫嶺完整原图复核（2026-10-19）

**完整8/8对、16张basemap/smooth原PNG已逐张实际查看。** 精确本线`jp-三陸鉄道-南リアス線`，#3恋し浜000952→甫嶺000950。本轮仅该站间；其余110对本轮实际查看0，不宣称118对全线视觉验收。每张用`functions.view_image`分别打开原始PNG，未裁切、拼图或修改像素。

复用本scope根`existing-evidence-20261019.json`已经核准的named plan与receipt记录；实际原图来自legacy slot000500 p0..7。当前#3 source31点与生产JS `app/public/rail-network.js` decoder所得display31点，重新对命名immutable plan逐点IEEE64bits完全匹配，station IDs相同；自身无display/station aliases。原16 PNG本次actual bytes也与receipt重新相符，其余receipt可用性复用已验证记录，没有hash campaign。完整named plan绝对路径、camera及两张原图绝对路径见manifest。

恋し浜北出有真实缓弯，随后沿NNW山内长直走向，通过鬼沢聚落山侧，再沿真实缓弯北入甫嶺。八对均连续，未见孤立假V、直角回头或突然跳接西侧県道9号。沿海道路的绕行和铁路较直山内走向应分别保留，不把道路弯替代铁路。

**具体未解决偏移：p0恋し浜站及北侧县道交叉附近红线显著在蓝色站组/轨带西侧，p1随后转到较东侧；p2/p3山内长段红线偏蓝glyph东侧，p6/p7甫嶺站接近和站组也略偏东。** 这是可供后续自身来源研究的侧移，不是已经确权可删的单点假V；完整平台caps、face和站点中心未证，不提出fallback坐标。

桥隧限制：p1–3长山地段只见标准地图直glyph与绿色填色，图中缺少可可靠定位的工程洞口/隧道轴细节；不能据山内直线或红蓝分离宣称地下轴正确或错误。鬼沢过渡及甫嶺南口河渠、道路交叉上下文连续，但标准地图不独立证明桥梁结构轴、桥端和洞口坐标。保留自身真曲线，未建立明确来源窗口前不改几何。未运行native/build/tests，不改生产/owner/父status，止于该站间。

## 实际查看清单

每行两张原PNG均已分别打开；完整文件与named identity见`interval-3-viewed-originals-20261019.json`。

| Point | 原图目录（basemap.png / smooth.png均已看） | 观察 |
|---:|---|---|
| 0 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000500/000000` | 恋し浜站及北出真实弯连续；红线在站组和北侧道路交叉附近明显偏西，再向山内长段靠拢。平台caps与自身物理轴未证。 |
| 1 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000500/000001` | 恋し浜北出向NNW进入山地长直走向，红线先西侧后东侧偏移，连续无孤立V。 |
| 2 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000500/000002` | 山内长直段仅有标准地图细铁路glyph，红线偏东侧；地下/隧道工程轴不能由绿色填色证明。 |
| 3 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000500/000003` | 长NNW山内段向鬼沢聚落过渡，红线连续偏东，未见孤立V或借沿海道路跳接；准确洞口未知。 |
| 4 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000500/000004` | 鬼沢聚落山侧长直走向连续，交叉道路与铁路方向分开，无回头；桥/洞口细节不足。 |
| 5 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000500/000005` | 向甫嶺南侧真实缓北弯，红线连续，近河渠交叉无尖钩；不能仅据标准地图确认桥梁工程。 |
| 6 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000500/000006` | 甫嶺南接近北向缓弯和河渠跨越连续，红线略东偏；站口真弯保留，完整平台端帽未证。 |
| 7 | `/Users/sager/Library/Application Support/RailAlignmentInspector/BatchEvidence/captures/000500/000007` | 甫嶺站及北延伸，红线偏站组东侧，未跳接西侧県道9号；没有精确face/caps或新站点中心。 |
