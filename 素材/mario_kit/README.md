# mario_kit · 马里奥棱面卡通资产包 v0.2

马里奥系列 20 单位，Blender 5.2 程序化建模，**风格 v1 棱面卡通**：显面 ico 多面体 + googly 大眼 + 方硬四肢 + 高饱和纯色 + Freestyle 粗描边。v0.2 新增 17 单位 idle/move 循环动画。

## 资产清单（20）

| group | key | 中文名 | group | key | 中文名 |
|---|---|---|---|---|---|
| heroes | mario | 马力欧 | enemies | goomba | 栗宝宝 |
| heroes | luigi | 路易吉 | enemies | koopa | 慢慢龟 |
| heroes | toad | 奇诺比奥 | enemies | shyguy | 嘿呵 |
| heroes | yoshi | 耀西 | enemies | boo | 害羞幽灵 |
| heroes | bowser | 库巴 | enemies | piranha | 吞食花 |
| heroes | peach | 碧琪公主 | items | mushroom | 超级蘑菇 |
| items | star | 无敌星星 | items | coin | 金币 |
| items | qblock | 问号砖块 | items | shell | 龟壳 |
| items | pipe | 水管 | items | brick | 普通砖块 |
| items | fireflower | 火之花 | items | onepup | 1UP蘑菇 |

总账见 [docs/assets_manifest.csv](docs/assets_manifest.csv)。

## 动画（v0.2 新增，24fps 循环，首尾无缝）

移动设计依据 `mario/research/movement.md`（按 SMB1/SMB2美版/SMW/NSMB/3DWorld 原版移动语言转译）：

| key | idle | move |
|---|---|---|
| mario | 呼吸浮沉+眨眼 | 走路：腿交替滑步+抬脚、臂反相摆、前倾 |
| luigi | 同上（碎步版） | 走路（步频更快） |
| toad | 呼吸+眨眼 | 急行小碎步（前倾, 10帧循环） |
| yoshi | 呼吸+眨眼 | 弹跳跑：抛物线跳、空中收脚、落地压扁 |
| bowser | 沉浮+微摇 | 重踏：慢节拍大步、左右摇、臂大摆 |
| peach | 呼吸+裙微摆 | 优雅快步：小步幅、裙摆 sway 加大 |
| goomba | 浮沉+微摇 | **招牌摇摆**：身体绕脚支点左右倾摆+小跳（还原2帧镜像waddle） |
| koopa | 呼吸+眨眼 | 走路：滑步+抬脚+臂摆 |
| shyguy | 呼吸 | 行军小步（袍身颠） |
| boo | 悬浮浮沉 | 悬浮漂移：正弦浮沉+双臂随波 |
| piranha | 茎摇+点头咬合 | 前扑吞吐 |
| mushroom / onepup | 轻浮+眨眼 | 小幅摇摆蹭行（贴地滑行转译） |
| star | 轻浮+眨眼 | 蹦跳（落地压扁） |
| coin | **绕轴自转**+浮沉（还原8帧金币转） | — |
| shell | — | 高速自转+微弹（被踢滑行） |
| fireflower | 茎摇+浮沉 | — |
| pipe / brick / qblock | 静态无动画 | — |

## 接入

- **单件**：`models/单件GLB/<key>.glb`，根节点 = key，自带该资产全部动画片段（无片段即纯静态）。
- **动画合包**：`models/mario_animated.glb`，顶层每资产一个 Empty 组（名=key），片段命名 `<key>_idle` / `<key>_move`。
- **静态合包**：`models/mario.glb`（同结构，无动画）。
- 循环片段直接 loop 播放；世界位移（前进）不烘进片段，由引擎驱动根节点。

## 目录

```
mario_kit/
├── models/   mario.glb(静态20) + mario_animated.glb(动画) + mario.blend(源) + 单件GLB/ ×20
├── sheets/   singles/ ×20(512透明) + catalog_wave.png(20单位目录) + catalog_anim.png(动画检查) + group_*.png
├── web/      模型预览.html — 单文件 3D 预览器(GLB 全内联 2.25MB, 双击即开; three.js 走 jsdelivr CDN 首次需联网)
└── docs/     assets_manifest.csv
```

## 风格参数（复现用）

- 图元：ico subd=1（头/壳）、box bevel（鞋/躯干）、cyl seg 6-16（臂/缘圈）
- 眼：白球 squash(1,0.55,1) + 黑瞳 r×0.48；眨眼=scale Y 脉冲
- 动画：REST 相对关键帧 → NLA 同名轨道合并导出（NLA_TRACKS）；位移步态不做关节旋转
- 渲染：Cycles GPU + OptiX 降噪，Standard 视变换，Freestyle 折角80°+剪影，线宽 2.4px
- 源码：`mario/scripts/`（m_kit 图元库 / build_wave1+2 / m_anim_lib / anim_wave / export_kit_v02）

## 版本记录

- v0.2（2026-10-05）：+5 单位（碧琪/水管/砖块/火之花/1UP）；17 单位 idle/move 动画；动画合包；20 单位对账 PASS。
- v0.1（2026-10-05）：波次1 15 单位首发。
