# 手势施法调研报告——各产品用过哪些手势 & 三角形为什么微妙

> 调研日期：2026-10-23。方法：三路并行网络调研（VR/手部追踪游戏、经典画符游戏、平台官方手势词表+学术文献），辅以内置搜索；结合本项目 `dollar_recognizer.gd` / `gesture_fsm.gd` 源码做针对性分析。
> 局限：中文搜索通道（智谱 web_search）因 API 余额不足（错误 1113）未能使用，中文区体感游戏（抖音 H5、国产摄像头游戏）覆盖不全，结论以英文资料为主。

---

## 0. 一句话结论

**三角形的问题不是玄学，是被学术数据和二十年的游戏史双重证实的**：它是本项目四个符文里唯一"闭合 + 多角点"的形状，学术上恰属"用户间一致性最低、互相混淆最严重"的类别（圆↔三角是已发表的低误差混淆对）；历史上没有任何一家画符游戏把闭合三角形作为必画图形——恶魔城最简单的封印用的是 **V 字开放折线**而不是三角。**替换首选：S 形波（∿，水波语义契合冰霜）；保留方案：加"三角几何门槛 + 多模板 + 开口容忍"三件套。**

---

## 1. 手势素材三大类总览

行业里"手势施法"分三类，各产品的用法如下表（后文逐个展开）：

| 类别 | 典型例子 | 可靠性规律 |
|---|---|---|
| **静态手形（pose）** | 捏合、握拳、张掌、比耶、指点、OK、我爱你、点赞 | 最鲁棒；跨平台公认词表就 8~10 个；怕"长时间保持"和近形混淆 |
| **动态动作（motion）** | 推、掷、挥、甩腕、拍手、响指、张合 | 可靠性居中；方向判定类（甩腕方向）远稳于精细动作类（响指） |
| **空中画符（stroke glyph）** | 圆、直线、Z、S、V、弓形、螺旋 | 最难做可靠；只适合低频大招（"手势税"）；必须"果断快画" |

### 1.1 静态手形：跨平台官方词表（精确清单）

**Google MediaPipe Gesture Recognizer 内置 8 类**（[官方文档](https://developers.google.com/edge/mediapipe/solutions/vision/gesture_recognizer)）：
`None / Closed_Fist 握拳 / Open_Palm 张掌 / Pointing_Up 食指上指 / Thumb_Up 点赞 / Thumb_Down 点踩 / Victory 比耶 / ILoveYou 我爱你（拇指+食指+小指）`

**Meta Quest（Horizon OS）**（[交互类型](https://developers.meta.com/vr/design/hands-interaction-types)、[设计指南](https://developers.meta.com/vr/design/hands-gesture-design)）：
- 核心 = **食指-拇指捏合**（官方明确：捏合时**其余手指放松伸展**才是标准姿势，攥拳捏是错误示例）、抓握 grab、指点 point
- 系统手势 = **非惯用手掌心朝上捏合**（菜单）、掌心朝上翻转（控制中心）
- 官方原则：**集合要极小**（用户期待接近 100% 可靠）、手形彼此区分度要大、每个手势配视觉+声音反馈、**不依赖长时间保持**（追踪丢失时 pinch 会自动释放）
- **中指捏合：各家官方都未采用**（一律食指捏合）

**Apple Vision Pro**（[官方手势指南](https://support.apple.com/guide/apple-vision-pro/basic-gestures-and-controls-tan1e2a29e00/visionos)）：
点按 Tap（看+捏）、捏合拖动、捏合长按、**双手捏合拉开/合拢缩放**、**捏合后快速甩腕 flick** 滚动、看向手掌+点按（主视图）

**Ultraleap/Leap Motion**（[官方手形指南](https://docs.ultraleap.com/xr-guidelines/Interactions/hand_poses.html)）：
单手捏、双手捏（拉开生成物体）、点赞（确认）、数手指；核心建议：**手形彼此高度区分、数量少、逐一引入、持续反馈、只留给高价值操作**

**Google Soli / Pixel 4 Motion Sense**（[官方帮助](https://support.google.com/pixelphone/answer/9517454?hl=en)）：
左右挥手切歌、挥手关闹钟/静音、靠近唤醒、空中轻点；评测指出需要**大幅、刻意**的动作才被识别（[Ars Technica](https://arstechnica.com/gadgets/2019/10/pixel-4-hands-on-project-soli-just-seems-like-wii-waggle)）

**→ 公认鲁棒的静态手形集合（按跨产品出现频率）**：
捏合 > 握拳/抓握 > 张掌 > 指点 > 比耶(V) > 点赞 > OK > 我爱你 > 中指捏（无官方采用）
本项目已占用：捏合（画符）、握拳（聚气）、张掌（推出/护盾/掌心火弹）。**空位且鲁棒的：比耶、指点、OK、点赞**。GDD §4.2 已规划的"比耶=分裂"恰好落在鲁棒区，可行。

### 1.2 动态动作：各 VR/体感游戏实际用过的

| 动作 | 出处 | 备注 |
|---|---|---|
| 挥臂投掷（棒球式） | The Unspoken 火球、The Mage's Tale、I'm Wizard (VP) | VR 施法最常见；Unspoken 官方放弃"物理精确投掷"改瞄准辅助 |
| **握拳蓄能→张手释放（两段式）** | Masters of Light、I'm Wizard (Vision Pro)、VP 独立 roguelite | **2024-2026 新品主流**，防误触且好识别；本项目掌心火弹已是此式 ✅ |
| 推/猛推 | Fable: The Journey 魔弹、First Hand 激光 | 方向判定，稳 |
| 甩腕（flick） | The Unspoken 召唤、Sorcery 奥术弹、VP 滚动 | Sorcery 是"识别简化成方向判定"的成功样本 |
| 手指摆动 wiggle | Waltz of the Wizard 施法 | 低精度要求，稳 |
| 拍手 clap | Waltz（震慑）、I'm Wizard（冲击波） | **双手重叠会让摄像头丢一只手**，手部追踪下高频翻车 |
| 响指 snap | Waltz 召唤 | **社区第一难用手势**：官方定义"中指弹拇指"，玩家本能用食指 → 大量失败（[r/PSVR](https://www.reddit.com/r/PSVR/comments/1incztv/waltz_of_the_wizard_hand_tracking_issue/)） |
| 双拳举起 | First Hand 护盾 | 简单可靠 |
| 掌心引导光束 | Waltz Natural Magic、First Hand | 用 UX（射线预览）掩盖追踪不可靠，Meta 官方推荐思路 |
| 举杖上举-下收 | Harry Potter Kinect | 识别无响应，IGN 5.9/10，失败案例 |

### 1.3 空中/触屏画符：各游戏用过的形状全集

| 游戏 | 平台/输入 | 用过的形状 |
|---|---|---|
| **Arx Fatalis** (2002) | 鼠标 | 20 个自造符文（字母式开放笔画），最多 3 符文组合 |
| **Ultima IX** (1999) | 鼠标 | 法术 sigil 符号 |
| **Black & White** (2001) | 鼠标 | 螺旋（进手势模式）、圆（火球/护盾）、直线（水）、N 折线（食物）、心形（治疗）、漩涡（传送）、方形螺旋 |
| **LostMagic** (NDS 2006) | 触屏 | 18 笔画符文（6 元素×3 级） |
| **恶魔城 苍月** (NDS 2005) | 触屏 | 5 个封印全是**连接圆周亮点的开放折线**；封印 1 = **V 字**（不是三角！） |
| **大神 Okami** (2006) | 手柄模拟笔 | **圆、直线、点、月牙弧、盘旋圈、倒 Q（圆+引线）、连线、两条横线（雾隐）** 等 13 笔法 |
| **The Wizards** (2017 VR) | 控制器/手部追踪 | 掌心翻转、画弓形等复合形状 |
| **Wonderbook** (2012 PS Move) | 挥杖 | 描形状 + 电影正典"swish and flick" |
| **Ni no Kuni DS** (2010) | 触屏 | **只在学咒时画一次，学会后改按键** |
| **Waltz of the Wizard** (手部追踪) | 裸手 | 空中描符文（食指） |
| **The Unspoken** (2016) | Touch | 空中**画矩形**（强力盾）、描画符文激活神器 |

**关键规律：没有一家把"闭合三角形"作为必画图形。** 闭合形状只出现在"圆"（Okami/B&W，且 Okami 的圆有"画太大不识别"的抱怨）；多线段图形全部做成"连接编号锚点"（恶魔城）而非自由描形；开放折线（V、Z、N、螺旋）是主流。

---

## 2. 案例深挖：翻车与成功经验

### 2.1 失败/翻车案例（对本项目最有价值）

**Arx Fatalis**（[Wiki](https://wiki.arx-libertatis.org/Spells)、[Steam 讨论区](https://steamcommunity.com/app/1700/discussions/0/882962139168974186)）：识别苛刻到"画歪变另一个法术"，实时战斗里画符被公认为不可用；社区技巧是**"画小一点"**（本项目 GDD"15% 画面区域画完即有效"与此暗合 ✅）；有 Shift 预存 3 个法术的补救机制。开源移植版专门放宽了识别。

**恶魔城 苍月 Magic Seal**（[Fandom](https://castlevania.fandom.com/wiki/Magic_Seal)）：封印失败 → **Boss 回血重打**，被骂到 2024 年重制版直接改成按键 QTE（官方承认失败）。教训：画符失败+硬惩罚=口碑杀手。

**Harry Potter Kinect**（[IGN 5.9](https://www.ign.com/games/harry-potter-for-kinect)）：举杖施法无响应，"挫败而非神奇"。

**The Wizards**（[SkarredGhost 评测](https://skarredghost.com/2017/08/03/wizards-review-entertaining-vr-spellcaster-game-early-access)）：**犹豫、慢速的画形必然识别失败，必须"果断快速"画**；冰霜弓（复合形状）是公认最难手势；战斗中手势被误读成另一个法术是常见恶性 bug。后期加入"改卡"系统允许玩家简化手势。

**VRIK（Skyrim VR 模组）**（[Nexus](https://www.nexusmods.com/skyrimspecialedition/mods/23416)）："张手即施法"被官方文档级标注 **"risky in built up areas"**——纯静态张掌触发=误触典型；对照 I'm Wizard 等"握拳→张手"两段式是正解。

**IRONSTRIKE 开发者复盘**（[Game Developer](https://www.gamedeveloper.com/design/conjuring-a-gestural-spellcasting-system-for-vr)）：提出 **"手势税"**——空中手势打断节奏、伤手；两大失败根源 = **不认可的手势** 与 **过于相似的手势**；好手势 = 不需教学 + 身体负担小 + 互相差异显著；**空中画形只适合低频大招，不适合高频攻击**。

### 2.2 成功经验

- **LostMagic 渐进惩罚**（[档案站](https://lostmagic.skapxd.dev/)）：重采样 64 点与模板比对，**≥0.70 判合格、≥0.85 威力更强**——画歪只是变弱不是失败；每符文最多 **6 个模板**；旋转宽容约 30°。口碑最好的画符识别设计。
- **Black & White 可跳过**（[BAWSite](http://bawsite.com/miracles.html)）：手势只是快捷方式，识别不灵可双击图标施放，挫败感有兜底出口。
- **Okami 时间冻结**：出笔瞬间近乎暂停，画符与时间压力解耦——公认正面样板（反例是 Arx/LostMagic/恶魔城全部死在时间压力上）。
- **Sorcery 方向判定**（[Eurogamer](https://www.eurogamer.net/sorcery-review)）：把"识别"简化成甩腕方向判定而非形状匹配，是 2012 体感三连（Wonderbook/HP Kinect/Fable Journey）里唯一口碑尚可的。
- **Meta 用 UX 掩盖不可靠**（First Hand）：激光预览、抓取锥、意图锥——不追求识别 100%，追求"失败不惩罚"。
- **Ni no Kuni 一次性画符**：只在学咒时画，学会后按键——把画符当仪式而非战斗机制。

---

## 3. 学术证据：形状难度的定量结论

| 结论 | 出处 |
|---|---|
| **用户内一致性 .91，用户间仅 .55**——同一个人重画同一形状挺像，不同人之间差异巨大；**几何复杂度越低越一致；角点数与一致性呈对数线性关系** | [Anthony, Vatavu & Wobbrock, GI 2013](https://graphicsinterface.org/proceedings/gi2013/gi2013-12/)，40,305 样本/63 手势/113 人 |
| **感知难度与几何复杂度强相关，但熟悉度可抵消复杂度**——勾、圆等熟悉形状即使复杂度不低也被评为"容易" | [Vatavu et al., INTERACT 2011](https://dl.ifip.org/db/conf/interact/interact2011-2/VatavuVCG11.pdf) |
| **圆↔三角是已证实的低形状误差混淆对**（书写路径高度重合）；同类还有 v↔check、问号↔花括号 | [Vatavu, Anthony & Wobbrock, Gesture Heatmaps, ICMI 2014](https://faculty.washington.edu/wobbrock/pubs/icmi-14.01.pdf) |
| 空中书写识别率 94.1% vs 纸面/触屏 96.6%——空中天然掉 2.5 个点 | [Air-writing recognition using smart-bands](https://www.researchgate.net/publication/342234536) |
| 空中笔画反应时 **1.12~1.58 秒**（仅简单笔画！）——空中画符天然比触屏慢 | [Xiao et al. 2021, Symmetry](https://www.mdpi.com/2073-8994/13/10/1926) |
| **符号类手势（画 X、竖拇指）回忆正确率显著优于纯方向笔画**；方向词与符号学一致是可学习性关键 | 同上 |
| $1 识别器：1 模板 ~97%，3+ 模板 ~99% | [Wobbrock 2007](https://faculty.washington.edu/wobbrock/pubs/uist-07.01.pdf) |
| $1 原始 16 模板集包含 triangle（还有 x/rect/circle/check/caret/zigzag/arrow/bracket/v/star/pigtail…） | [UW 官方项目页](https://depts.washington.edu/acelab/proj/dollar/index.html) |
| $P 点云识别器：方向不变、点序不变、多笔画，>99% | [Vatavu et al., ICMI 2012](https://dl.acm.org/doi/10.1145/2388676.2388732) |
| 3D 空中轨迹投影 2D 后 $P+3 显著最优；用户独立场景仍显著难于用户依赖 | [CSCW/TOCHI 2020](https://dl.acm.org/doi/10.1145/3427326) |
| 用户自创手势的一致性因命令而异；偏好单手单指 | [Wobbrock, CHI 2009 User-Defined Gestures](https://dl.acm.org/doi/10.1145/1518701.1518866) |

---

## 4. 三角形为什么微妙——结合本项目代码

本项目四个符文：slash 斜线（0 角点）、circle 圆（0 角点闭合）、zigzag Z 字（2 角点）、**triangle 三角（3 角点 + 闭合）**（模板见 [dollar_recognizer.gd:19-26](../scripts/dollar_recognizer.gd#L19)）。三角微妙的原因可以精确列出：

1. **它是符文表里唯一"闭合+多角点"的形状，学术上正中一致性最差区**。GI 2013：角点越多用户间一致性越低；ICMI 2014：**圆↔三角是低误差混淆对**。本项目恰好圆和三角同表共存，撞在枪口上。
2. **圆度门槛两头受气**（[dollar_recognizer.gd:96-121](../scripts/dollar_recognizer.gd#L96)）：`circle_like > 0.85` 会强制判圆。三角的圆度约 0.77（代码注释自证），安全余量只有 0.08——**手抖+低帧率采样把三角的三个尖角磨圆后，圆度上探 0.85 就被圆抢走**（画成火球）。反之，没画闭合（手提前抬起）则闭合度掉到 0.25 以下，圆被剔除后开口三角 = 一个"✓/V"形折线，**往 zigzag（链电）上撞**——这正是"三角形微妙"的体感来源：不是不识别，是识别成别人。
3. **角点在低帧率下最先糊掉**。树莓派部署下采样帧率有限 + FSM 三票表决滞后（~100ms），画三角时指尖在三个尖角处速度最快、方向突变最大，恰好是采样最稀、抖动最大的地方——尖角被切掉/磨圆，形状特征崩得比圆（无角）和斜线（无角）快得多。
4. **±45° 旋转不变是全体模板共享的**（`ANGLE_RANGE`，[dollar_recognizer.gd:11](../scripts/dollar_recognizer.gd#L11)），无法给三角单独收紧——玩家画歪 30° 的三角仍会参与旋转匹配，放大了第 2 条的混淆面。
5. **耗时目标 1.5s 是四符文最慢的，而学术数据显示这偏乐观**：空中简单笔画反应时就已 1.12~1.58s，3 角点+闭合的三角 realistically 1.8~2.5s。GDD §4.1"符文复杂度≈法术强度"的定价里，冰霜领域付出的时间成本被低估了。
6. **佐证：历史上没人这么干**。恶魔城封印 1 用 V 字开放折线而不闭合；Arx 符文全是开放笔画；LostMagic 18 符文无闭合三角形。闭合图形只有"圆"成功过（且靠几何特征兜底——本项目 circle_like 门就是同样思路）。

---

## 5. 方案建议（按推荐顺序）

### 方案 A（首选）：三角 → S 形波（∿ 横向正弦/波浪）

- **语义**：水波 ↔ 冰霜，直觉自洽（GDD 里正弦波原本规划给治疗——治疗可改用其他符号，如"十"字或勾）。
- **识别性**：平滑无尖角（不怕角点磨圆）、开放（不与圆的闭合度门槛竞争）、2 个反向弯曲与 Z 字（2 个尖角折返）在 $1 归一化后区分度足够；还可以仿照 `circle_like` 加一个"平滑度/弯曲度"几何门槛，进一步与 zigzag 隔离。
- **耗时**：估计 ~1.0s，比三角快 1/3，且画错率低——修正"冰霜领域定价过高"的问题。
- **风险**：与 zigzag 的区分需实测（建议单测加"慢速波浪 vs 慢速 Z"混淆用例）；旋转不变下 ∽ 与 Z 的最短距离需验证，必要时给 wave 关掉部分旋转自由度（GDD §3.4 本就规划了按符文的旋转开关）。

### 方案 B：保留三角，做"三件套"加固（改动最小）

1. **三角几何门槛**（仿 circle_like）：闭合度 0.6~0.85 + 检测到 3 个尖角 → 直接判三角，绕开 $1 的模板距离竞争；同时把"强制判圆"的阈值从 `>0.85` 提到三角不可能达到的区间，或对"圆度 0.8~0.9 且有 3 尖角"的轨迹优先判三角。
2. **多模板**：内置 3~6 套三角模板（尖角朝上/朝下、略开口、胖三角/瘦三角）——$1 论文：3+ 模板即 99%；LostMagic 每符文 6 模板。玩家录制样本机制已有（`rune_samples.gd`，上限 10）✅。
3. **开口容忍**：把"未完全闭合"的三角（尾端离起点 < 边长的 30~40%）也纳入模板，堵住"提前抬手→判成 zigzag"的洞。
- 代价：不解决"画得慢"（1.5s+）的问题，只是让它别认错。

### 方案 C：换触发形态（不动形状，动交互）

- 冰霜领域改为**动作类**：如"张掌向下压"（下压=冰霜落地，方向判定，Sorcery 式简化识别）或"双手掌合拢再推开"（I'm Wizard 的散射手势）。可靠但与"画符=施法"的核心卖点偏离，只建议作为备选。

### 系统性建议（与选哪个方案正交，均来自成功案例）

1. **渐进惩罚**（LostMagic）：识别分 0.70~0.85 时施放"弱化版"冰域（半径 60%/时长减半）而非失败——把二元失败改成梯度，挫败感大降。
2. **失败不重罚**（恶魔城反面教材）：画错法术不进硬冷却，只耗少量法力或干脆免费重画（本项目冷却 0.8s 已较温和 ✅）。
3. **画符慢动作**（Okami 样板 + 本项目 GDD 已有的"聚气"概念）：起笔后敌人/弹幕时间流速 ×0.3~0.5，把"画符 vs 时间"的核心张力从"惩罚"改成"张力选择"。
4. **新符文设计红线**（IRONSTRIKE）：任何两个符文的形状差异必须肉眼级显著；角点 ≤2；开放优于闭合；熟悉符号 > 抽象图形（GDD 规划中的矩形石盾、五角星陨石都要过这三条——**五角星（5 尖角+闭合+笔画交叉）按学术数据会是比三角更深的坑，建议改月牙/十字**）。

### 静态手形扩展（若按 GDD §4.2 加副手姿势）

按鲁棒性排序的空位手形：**比耶 Victory**（MediaPipe 内置、与现有捏/拳/掌零冲突，GDD 已规划"分裂"）、**指点**、**OK 环**、**点赞**。避免：中指捏合（无官方采用）、响指（社区第一难用）、需双手重叠的动作（拍手类，丢追踪）。

---

## 6. 主要参考来源

- [MediaPipe Gesture Recognizer 官方文档](https://developers.google.com/edge/mediapipe/solutions/vision/gesture_recognizer)
- [Meta Hands 设计指南](https://developers.meta.com/vr/design/hands-best-practices) / [交互类型](https://developers.meta.com/vr/design/hands-interaction-types)
- [Apple Vision Pro 基本手势](https://support.apple.com/guide/apple-vision-pro/basic-gestures-and-controls-tan1e2a29e00/visionos)
- [Ultraleap Hand Poses 指南](https://docs.ultraleap.com/xr-guidelines/Interactions/hand_poses.html)
- [$1 Unistroke Recognizer 项目页（UW）](https://depts.washington.edu/acelab/proj/dollar/index.html) / [论文 PDF](https://faculty.washington.edu/wobbrock/pubs/uist-07.01.pdf)
- [Wobbrock et al. CHI 2009 User-Defined Gestures](https://dl.acm.org/doi/10.1145/1518701.1518866)
- [Anthony et al. GI 2013 一致性研究](https://graphicsinterface.org/proceedings/gi2013/gi2013-12/) / [PDF](https://faculty.washington.edu/wobbrock/pubs/gi-13.02.pdf)
- [Vatavu et al. ICMI 2014 Gesture Heatmaps（圆↔三角混淆对）](https://faculty.washington.edu/wobbrock/pubs/icmi-14.01.pdf)
- [Vatavu et al. INTERACT 2011 感知难度](https://dl.ifip.org/db/conf/interact/interact2011-2/VatavuVCG11.pdf)
- [$P 识别器 ICMI 2012](https://dl.acm.org/doi/10.1145/2388676.2388732) / [3D 轨迹识别 TOCHI 2020](https://dl.acm.org/doi/10.1145/3427326)
- [Xiao et al. 2021 空中符号手势](https://www.mdpi.com/2073-8994/13/10/1926)
- [Arx Fatalis Wiki: Spells](https://wiki.arx-libertatis.org/Spells) / [Steam 讨论](https://steamcommunity.com/app/1700/discussions/0/882962139168974186)
- [LostMagic 档案站（0.70/0.85 机制）](https://lostmagic.skapxd.dev/)
- [恶魔城 Magic Seal（Fandom）](https://castlevania.fandom.com/wiki/Magic_Seal)
- [Okami Celestial Brush（Fandom）](https://okami.fandom.com/wiki/Celestial_Brush_techniques)
- [BAWSite: Black & White Miracles](http://bawsite.com/miracles.html)
- [Sorcery 评测（Eurogamer）](https://www.eurogamer.net/sorcery-review)
- [HP Kinect 评测（IGN）](https://www.ign.com/games/harry-potter-for-kinect)
- [The Unspoken 官方访谈（Meta 博客）](https://www.meta.com/blog/oculus-touch-tuesdays-the-unspoken/)
- [Waltz of the Wizard 手部追踪更新（Aldin）](https://medium.com/aldin-dynamics/waltz-of-the-wizard-ps-vr2-hand-tracking-update-758efd445b04)
- [The Wizards 评测（SkarredGhost）](https://skarredghost.com/2017/08/03/wizards-review-entertaining-vr-spellcaster-game-early-access)
- [Masters of Light 报道（Mixed News）](https://mixed-news.com/en/meta-quest-masters-of-light-relies-on-magic-through-hand-tracking)
- [First Hand 评测（SkarredGhost）](https://skarredghost.com/first-hand-meta-review) / [Meta 开发者博客](https://developers.meta.com/vr/blog/introducing-first-hand)
- [VRIK（Nexus Mods）](https://www.nexusmods.com/skyrimspecialedition/mods/23416)
- [IRONSTRIKE 手势设计复盘（Game Developer）](https://www.gamedeveloper.com/design/conjuring-a-gestural-spellcasting-system-for-vr)
- [I'm Wizard（Vision Pro）](https://appsforapplevision.com/apps-directory/im-wizard-magic-combat-game)
