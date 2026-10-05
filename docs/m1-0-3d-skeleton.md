# M1.0 实施文档：3D 骨架

> 前置：无（M1 起点）。产出：能跑的 3D 场景 + 会播动画的敌人模型。

## 目标

把项目从 2D 画面切到真 3D 战场：Forward+ 渲染、地面/天空/光照、玩家相机站位、城堡布景落位，marine/marauder GLB 在场景里正确显示并能播 idle/move/attack 动画。

## 任务分解

### 1. 素材落地
- [ ] 新建 `assets3d/units/`、`assets3d/buildings/`、`assets3d/env/`
- [ ] 拷贝：`单件GLB/marine.glb`、`marauder.glb` → `assets3d/units/`
- [ ] 拷贝：`b_command_center.glb`、`b_bunker.glb`、`b_missile_turret.glb` → `assets3d/buildings/`
- [ ] 拷贝：`e_rock.glb`、`e_tree.glb`、`e_mineral.glb`、`e_bush.glb` → `assets3d/env/`
- [ ] `素材/.gdignore`（空文件）——防止 Godot 导入整个素材包（115+ 文件、5.6MB GLB）
- [ ] 首次 `--import` 生成 `.godot` 缓存（headless import 已知可能段错误收尾，缓存实际已生成，属正常）

### 2. 渲染器切换
- [ ] `project.godot`：`config/features` 去掉 `"GL Compatibility"`；`[rendering]` 段 `renderer/rendering_method="forward_plus"`
- [ ] 确认 window/size 保持 1280×960（M0 基线）

### 3. 战场场景 `scripts/battle3d/battlefield_3d.gd`（新建，Node3D）
- [ ] **WorldFormat 常量**：`GROUND_SIZE = 160`（XZ 平面）、玩家位 `(0, 1.65, 8)`（站城堡前）、看向 `-Z` 纵深
- [ ] **地面**：`CSGBox3D` 或 `MeshInstance3D(PlaneMesh)` 120×120m，草绿色（`Color(0.36, 0.52, 0.30)`），粗糙度 1；远处渐暗可用第二个深色大平面垫底
- [ ] **天空**：`Environment`（ProceduralSkyMaterial，地面色偏草绿、天空淡蓝）+ `WorldEnvironment`；环境光能量 0.9，`glow_enabled=true`（Forward+ 泛光，为法术自发光做准备）
- [ ] **光照**：`DirectionalLight3D` 斜 45°（暖白 1.2 能量，`shadow_enabled=true`），加一盏低能量 OmniLight3D 补背光
- [ ] **相机**：`Camera3D` 玩家位 `(0, 1.65, 8)`、`-Z` 朝向、FOV 70、`current=true`
- [ ] **城堡布景**：指挥中心 (0, 0, 22) 转身背对战场、地堡 (-6, 0, 16) 与 (6, 0, 16)、导弹塔 (±12, 0, 18)；尺寸按素材包规范（建筑高 1.0-1.7）放大 2.5 倍让画面成立
- [ ] **环境点缀**：岩石/树/矿场散布战场两侧（伪随机固定种子，避免每局变样），不挡中路
- [ ] **画幅适配**：`@onready` 处理视口小于 100 时回退设计分辨率（沿用 main.gd 的 headless 兜底逻辑）

### 4. 动画验证脚本 `tests/anim_probe.gd`（新建，`--anim-probe` 触发）
- [ ] 实例化 marine/marauder 放 (0,0,0) 与 (2,0,0)，各挂 AnimationPlayer 依次播 idle → move → attack，各 2 秒
- [ ] 断言：`AnimationPlayer.has_animation("marine_move")` 为真、动画列表非空、播放中 `is_playing()` 为真
- [ ] 结果写 `tests/anim_probe_result.txt`（PASS/FAIL + 动画清单）

### 5. main.gd 接线（最小改动）
- [ ] 默认模式改为构建 3D 战场：`battlefield = preload("res://scripts/battle3d/battlefield_3d.gd").new()`，加入场景树
- [ ] 旧守卫法阵挂 `--ward` 参数、旧练习靶挂 `--practice`（原 `--e2e-test` 内部走练习靶不动）
- [ ] 手势层（skeleton/trail/hud）暂不挂到 3D 模式（M1.3 再接），本里程碑只验 3D 画面

## 验收标准
1. `--anim-probe` headless 跑通：marine/marauder 各 3 段动画存在且能播放（结果文件 PASS）
2. 带窗口运行：地面/天空/光影/城堡/环境件可见，相机站位正确（截图目检）
3. `--smoke-test`、`--e2e-test`、`--game-test`（旧套件）全绿——旧模式未被破坏
4. `.godot` 导入缓存中能找到 `marine.glb.import`，且 `素材/` 下零 `.import`

## 风险与回退
- **Forward+ 下 GLB 材质异常**（如自发光过曝）：调 `Environment` tonemap/tone_mapping 为 Filmic 或降能量；最坏切回 GL Compatibility（代码无 Forward+ 硬依赖，只损失泛光）
- **headless import 段错误**（已知 GDMP 噪音）：重跑一次 import；不影响缓存
- **动画名对不上**：已预检 GLB JSON 确认 `marine_idle/move/attack` 存在；若 Godot 导入后名字带路径前缀，用 `get_animation_list()` 打印实际名再适配
