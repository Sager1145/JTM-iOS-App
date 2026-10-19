# 大崎当前碎线修复与原生结果（2026-10-12）

后续用户报告站南合流与南侧总武／横须贺分岔两处仍错位，本页碎线数量结果不能关闭接头问题。生产 lane/follow 复查已推翻下文“未发现功能缺陷”的接头范围推断；新原因、整段回归及最终验收见 `../branch-join-recheck/results.md`。原图与过程记录保留。

用户第68条要求站区 JR 南侧两根进路汇成一根进站、北侧一根离开。按这一新的局部显示合同，山手线现有连续 part 担任站内与北侧 owner；两条大崎支线的 displayBranchLeadIns 退役，physical 方向、northJunction、stations、segments、里程均保留。支线 display 前215.48m与山手线既有支持反向共享；南侧200m有界过渡后保留独立西进路和原总武共享尾。临海线的公司线、圆点与成员独立保留。这是用户要求的站区概括，不能解释成原来不同平台组物理合轨。

Owning source 为 repair-tokyo-southern-branches.py/integrate_legacy_display 与 repair-shinagawa-display-lanes.mjs/repairOsakiLanes。实际前后比较仅两条支线显示字段改变、其余653条线路精确不变；cached rulers、follow/family同步更新。source与lanes各自重放幂等，JS两个专项回归通过；已有 Swift PrecomputedRouteDisplayTests/osakiSurveyedMain 单项通过。独立审查未发现功能缺陷，旧注释已更正；production merge角小于1.74度。初始新family未定义颜色被资源builder拒绝，已改用既有大崎组后构建成功，不使用失败中间产物。

最终构建 /private/tmp/jtm-osaki-station-final-build.log BUILD SUCCEEDED。主 compact 与源相同；三个独立Inspector compact逐字节同步并重签。三个 app 顺序采集、root实际查看4个完整区间29个视点（品川→大崎7、大崎→五反田4、支线base/p1各9），无failed/pending scope；不可用计数代替视觉检查。原始native数据 /private/tmp/jtm-osaki-station-final-evidence，contact与coverage在 final-station-representative。

主App实际检查：station-close-after同before camera35.6195,139.728,.006，南二/站一/北一JR绿线，两个旧北短端点消失；south-merge-after35.6157,139.730,.012，南两进路汇合且外侧真实分岔保持；whole-adjacent-intervals-after35.615,139.734,.032覆盖品川/五反田/西大井完整关联区间，连续。实际点击大崎点，card保留山手线、大崎支线、临海线三名称（支线两个逻辑方向仍在network）。所有保存视窗budgetDrops0，线路全局count不是本站线数。

before最初因REPL闭包仍引用旧目录而落入 kisuki/full-line-review/final-minami-daito/main；已将 station-throat/station-close 的PNG/AX原样复制至 osaki/latest-fragments-before，未删除原文件。后续保存函数显式传目录，最终before/after可检索。本结果验收局部代表线与接续，不认证屋盖逐股道测量。
