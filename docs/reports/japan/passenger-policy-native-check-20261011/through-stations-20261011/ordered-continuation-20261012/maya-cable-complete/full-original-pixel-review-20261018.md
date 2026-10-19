# #58 摩耶缆车：全部旧原图复核

2026-10-18。实际逐张打开全 **4/4对、8张原始basemap/smooth PNG**，剩余未看0对。精确本线 `jp-こうべ未来都市機構-摩耶ケーブル線`，摩耶ケーブル006971→虹006940，仅一个缆车区间。路径为 BatchEvidence/captures/000167/000000..000003，绝对路径/实际view IDs见 `full-original-pixel-review-20261018-viewed-manifest.json`。没有native、build、capture、tests、apply或生产改动。

p0显示城市边缘起站及上山弯线，红线连续；p1是山地直坡及与图示Sanyo Shinkansen的二维交叉，红线持续跟随自己的上山方向，未折向新干线。不能从平面交叉断言实际连接或高程。p2/3显示虹站附近上段和缓弯，红线连续，无孤立V/反向钩/断裂。中坡部分红在蓝线东侧有持续小横差，但不是已确权的错误走线；标准森林底图没有可独立测定的轨道像素。保留真实山地与缆车弯线，不自动拉直。

当前来源最大转角约10.24°（#0 v13 [135.21254,34.7268]）；实际旧渲染未显示需删除的独立尖角。两站蓝色填色不能证明缆车自身usable platform caps/纵向中心，也不能当作普通复线站台处理。虹站另一段摩耶ロープウェー独立，未把它接入本线。

前序准备已逐段确认旧named plan/current source、display坐标及站ID精确匹配，receipt文件存在且符合保存byteCount。本次确实查看了原图，但它们仍是z17、1024×768、light、`fixed-z17-v2` isolated centreline、ownLane=0/mainLane=0；全4对审图不等于当前specified-capture-v3或Main多线/站圈验收，也不证明survey精度。没有足够证据支持显示修复；保留来源。
