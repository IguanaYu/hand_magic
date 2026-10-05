# RuneHand M0 原型 — 运行说明

> 对应设计文档：`docs/gdd-runehand-v0.1.md` §12 里程碑 M0 + M0.5 迷你游戏。
> 环境：Godot 4.6.1 stable（compatibility 渲染器）+ GDMP v0.6 + CameraServerExtension（均已内置）。

## 运行

用 Godot 4.6 打开项目（`project.godot`），按 F5 直接进入**守卫法阵迷你游戏**。

命令行方式：

```bash
# 带窗口运行游戏（有摄像头用手势，没有则鼠标兜底）
"Godot_v4.6.1-stable_win64.exe" --path E:\godot\magic

# 测试套件（headless）
"Godot_v4.6.1-stable_win64_console.exe" --headless --path E:\godot\magic -- --smoke-test    # 算法冒烟 14 项
"Godot_v4.6.1-stable_win64_console.exe" --headless --path E:\godot\magic -- --e2e-test      # 端到端 35 项
"Godot_v4.6.1-stable_win64_console.exe" --headless --path E:\godot\magic -- --robust-test   # 鲁棒性基准
"Godot_v4.6.1-stable_win64_console.exe" --headless --path E:\godot\magic -- --game-test     # 游戏逻辑 9 项
"Godot_v4.6.1-stable_win64.exe" --path E:\godot\magic -- --camera-test                      # 摄像头管线（需硬件）
```

## 守卫法阵（M0.5 迷你游戏）

暗影蚀影从屏幕四周爬向你的中央法阵（10 血），撞上就扣血。守住它！

**手势操作**（对准摄像头）：
1. **握拳 → 张开手掌** = 掌心火弹（快速，自动瞄准最近敌人，8 法力）
2. **握拳 → 伸食指画 ◯ → 张掌** = 火球 AoE（25 法力，在掌心位置爆炸）
3. 其余符文照常：Z=链电、△=冰域（减速敌人）、/=风刃

**鼠标兜底**（无摄像头自动启用）：单击 = 掌心火弹；按住画圈松开 = 火球。

**R 重新开始**，F1 调试 HUD（得分/法阵血/延迟/识别得分），ESC 退出。难度随时间收紧（生成间隔 2.5s→0.8s，敌速渐增）。

## 玩法（M0 范围）

对准摄像头坐着，让手出现在画面里：

1. **握拳**（~150ms）→ 聚气，掌心浮起微光
2. **伸出食指在空中画符** → 指尖发光拖尾
3. **张开手掌** → 施放！法术以掌心位置为锚点炸开

| 符文 | 一笔轨迹 | 法术 | 效果 |
|---|---|---|---|
| ◯ 圆 | 画个圈 | 火球术 | 锚点 AoE 爆炸 |
| Z 折线 | 画 Z 字 | 链电术 | 链最近 3 个靶 |
| △ 三角 | 一笔三角 | 冰霜领域 | 大范围冰冻染色 |
| ╱ 斜线 | 随手一划 | 风刃 | 快速穿透弹 |

画面里有 4 个水晶练习靶，打碎 2.5 秒后重生。

**快捷键**：F1 切换调试 HUD ｜ R 重置统计 ｜ ESC 退出。
**无摄像头兜底**：按住鼠标左键画符，松开施放。

## 调试 HUD 读法

- **延迟**：摄像头帧 → 识别回调的端到端延迟（EMA）。**M0 验收线 ≤150ms**
- **识别**：最近一次符文名 + 得分（阈值 0.80 施放 / 0.70 模糊）
- **姿势**：几何分类器当前判定（握拳/画符/张掌/无）
- **施放/失败**：成功施放与 FIZZLE 次数——两者比值即「输入健康度」

## M0 验收清单（对照 GDD §12）

- [ ] 手部骨架与掌心锚点稳定跟随（One Euro 平滑后无明显抖动）
- [ ] 良好光照下，四个符文各画 10 次，识别成功率 ≥90%
- [ ] HUD 延迟读数 ≤150ms
- [ ] 三段式手势（拳→指→掌）无频繁误触发
- [ ] FIZZLE 率 ≤15%（识别失败/误识别占比）
- [ ] 鼠标兜底模式可用（无摄像头也能完整走完施法流程）
- [ ] 10 名测试者中 ≥7 人表示「想继续玩」（GDD 定性门槛）

## 测试

```bash
G="Godot_v4.6.1-stable_win64_console.exe"
"$G" --headless --path E:\godot\magic -- --smoke-test    # 核心算法冒烟（14项）
"$G" --headless --path E:\godot\magic -- --e2e-test      # 端到端仿真（35项，~40s）
"$G" --path E:\godot\magic -- --camera-test              # 摄像头管线（需摄像头，8s）
```

结果分别写入 `tests/smoke_result.txt` / `e2e_result.txt` / `camera_result.txt`。

**当前状态（2026-10-05 自测）**：冒烟 14/14 ✓、E2E 35/35 ✓、场景运行零错误 ✓。
**摄像头管线**：集成完整（Windows 经 CameraServerExtension/Media Foundation 枚举，已对照插件源码核实触发时序），但**本机无摄像头设备**（PnP/WMI 三重查询确认为空），真实识别链路需在有摄像头的机器上跑 `--camera-test` 验证（判据：`results_received > 0`）。

E2E 测试曾抓到两个真实 bug（已修复）：① 姿势切换确认期的指尖"瞬移"污染轨迹 → 已加 12% 瞬移保护；② 握拳判定用四指平均值，伸食指的手会被误判为拳 → 改为逐指判断。

## 工程结构

```
addons/GDMP/            GDMP v0.6 插件（已裁剪至仅 Windows x86_64）
addons/CameraServerExtension/  Windows 摄像头枚举（Media Foundation 后端）
models/hand_landmarker.task   MediaPipe 手部关键点模型（本地打包，7.8MB）
shaders/                摄像头 YUV→RGB 转换着色器
scenes/main.tscn        主场景（场景树由代码构建）
scripts/
  hand_tracker.gd       摄像头 → GDMP → 归一化关键点（数据流最上游）
  pose_classifier.gd    关键点几何 → 拳/掌/画符（5 帧去抖）
  gesture_fsm.gd        施法状态机（GDD §3.2）+ 法力 + 掌心火弹快速施法
  dollar_recognizer.gd  $1 手写符文识别（圆形/直线度几何修正）
  one_euro_filter.gd    关键点平滑
  skeleton_renderer.gd  手部骨架绘制
  trail_renderer.gd     画符拖尾特效
  ward_ring.gd          中央法阵（法力环 + HP 环）
  spells/spell_manager.gd  五法术分发与命中判定（靶/敌人统一接口）
  game/enemy.gd         蚀影敌人（爬向法阵、可冰冻）
  game/enemy_spawner.gd 难度曲线生成器
  game/mini_game.gd     守卫法阵游戏状态（HP/得分/结算/重开）
  targets/target_dummy.gd  练习水晶靶（e2e 模式）
  smoke_test.gd         核心算法冒烟测试
tests/e2e_test.gd       端到端仿真测试（合成手部数据走真实管线）
tests/robust_test.gd    符文抗噪基准
tests/game_test.gd      迷你游戏逻辑测试
```

## 已知事项

- GDMP 在 headless 模式下有「extension class 重复注册」报错噪音，不影响运行（GDMP 已知问题）。
- `--import` 在 headless 下可能以段错误结束（发生在缓存写入之后的收尾阶段），缓存实际已生成；若脚本报「类未注册」错，重跑一次 import 即可。
- Windows 下 GDMP 不支持 GPU delegate，已固定使用 CPU（识别单帧约 5-15ms）。
- 灵敏度/阈值调参入口：`pose_classifier.gd` 顶部常量、`dollar_recognizer.gd` 的 CAST 阈值在 `gesture_fsm.gd`。
- headless 模式视口为 64×64，主循环已内置回退到设计分辨率 1280×960（`main.gd`）。
- CameraServerExtension 的 feed 对象不能标注 `CameraFeed` 类型（上转型后 get_formats/set_format 失效，插件已知问题），`hand_tracker.gd` 中 `_feed` 保持无类型。
