# 京叶同类接头复查（2026-10-12）

按原唯一铁路清单，在大崎接头修复后检查京叶东/西支臂及两侧主线。京叶源数据本次未改；两臂各只有一个非identity follow，新过滤不会改变其执行路径。

三个独立Mac检测app串行新采集4个完整区间60视点：西船桥→南船桥17、西船桥→市川盐滨18、南船桥→二俣新町11、二俣新町→市川盐滨14。失败0；包括两端及短尾，60/60三联截图共180面板全部人工复查，见native-review.md与coverage.json。未见走错支臂、道路/建筑吸附、回折或中心线断口。此前全京叶19区间183视点是历史整线证据，本60点为重新采集，不合并宣称唯一总数。

## 实际主应用

main目录保存overlay/basemap配对：east-handoff-close（35.6913233641,139.9642970964,.003）、west-handoff-close（35.6877494901,139.9509532591,.003）、east-middle-curve（35.6862790338,139.9835297793,.003）、west-region（35.6877518737,139.9509559859,.05）、whole-both-arms和whole-both-arms-endpoints。普通network的红色共享代表在两处分岔、中段及全范围连续，没有重新出现方向支臂碎片。区域图不能证明站台中心精确位置。首次whole-both-arms中南端被面板遮挡，最后有效相机为35.68,139.975,.08，市川盐滨、西船桥、南船桥三个端点均可见。留下network ON，15lines/13overlays、budgetDrops0，5364vertices，见left-running-final截图/AX。三Inspector正常退出，无全国默认采集。

## 保留问题

production-join-probe.mjs/out对两臂完整路径每10米、z10–19检查，所有点finite，共站端点0或浮点量级。east family 0.1米边界取整造成约0.062米映射差，z19接头约0.544px；west z14接头约0.377px，即使去取整仍约0.376px，属于曲线/LOD残差。选中arm共享路径对最终trunk最大局部差：east z18约2.733px（own4188.8米），west z14约0.963px（own2449.9米）。普通network该span由trunk绘制，本次Main未执行选中arm/ride跟车，不能关闭这些WARNING。原平台中心、地下和西臂共享精度待修项保留在唯一README；没有凭静态中心线通过勾选整个京叶地理完成。
