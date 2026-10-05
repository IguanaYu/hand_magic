# M1.3 实施文档：手势整合

> 前置：M1.2 完成。产出：真手势驱动施法/瞄准/护盾，法力系统接入，本机无摄像头也可全程鼠标游玩。

## 目标

把 M0 手势管线接进 3D 战场：手势锚点/鼠标位置统一为"瞄准点"，FSM 的 cast/quick_shot/fizzle 信号路由到 SpellCaster3D；新增"空闲张掌=护盾"；法力消耗与回复接入。

## 任务分解

### 1. main.gd 手势层上 3D（结构改造）
- [ ] 3D 模式下场景树：`Battlefield3D`（3D 世界）+ `CanvasLayer(ui)`（DebugHud / 准星 / 红闪 / 浮层）+ `CanvasLayer(gesture)`（SkeletonRenderer + TrailRenderer，2D 绘制叠在 3D 上）
- [ ] 保留 M0 鼠标兜底逻辑（按住=聚气/画符、松开=施放），`_on_cast(spell_id, anchor, score)` 路由改为 `spell_caster.cast(spell_id, anchor * view_size)`
- [ ] 键盘 1-5 调试施法保留（瞄准=鼠标位）
- [ ] `_gui_dump()` 扩展 3D 状态（player_hp/wave/score/enemies 数），供 OS 级注入测试

### 2. 瞄准统一
- [ ] 手势模式：施放锚点 = 掌心位置（归一化）；画符期间准星跟随食指尖——**所见即所打**
- [ ] 鼠标模式：准星=鼠标位（现状）
- [ ] SpellCaster3D 不区分来源，只收屏幕坐标

### 3. 护盾 `scripts/battle3d/shield_3d.gd`（新建）
- [ ] **触发**：FSM 处于 IDLE 且姿势=PALM 持续 ≥0.3s（去抖防误触）；鼠标兜底=按住右键
- [ ] **视觉**：玩家前方 1.2m 半球 `SphereMesh`（半透明青蓝，法力流动 shader 可后补）+ 张掌期间微微呼吸缩放
- [ ] **判定**：EnemyBullet3D 每帧检查与半球相交（正面 ±60°）→ 销毁子弹+火花粒子；护盾期间移速罚无（玩家本来不动）
- [ ] **代价**：开启耗 5 + 每秒耗 12 法力；法力空自动破盾（碎裂音画）+ 1s 冷却
- [ ] **手势冲突处理**：FSM 进入 CHARGE/DRAWING（握拳）瞬间强制关盾——盾与施法互斥，状态机不抢

### 4. 法力接入
- [ ] `fsm.mana_changed` → HUD 蓝条（底部 HP 条旁）
- [ ] 法术消耗表（fsm 内已有常量，对齐主计划 §3）：火球 25 / 链电 20 / 冰域 30 / 风刃 15 / 掌心火弹 8
- [ ] 蓝不足时 cast → fizzle（已有逻辑），HUD 提示"法力不足"

### 5. 2D 手势渲染适配
- [ ] SkeletonRenderer/TrailRenderer 在 CanvasLayer 下按 view_size 归一化绘制（M0 逻辑原样，只换父节点）
- [ ] 无摄像头提示语更新："鼠标兜底：按住画符施法，右键护盾，1-5 直放法术"

## 验收标准
1. 有摄像头机器：握拳→画◯→张掌，火球在掌心对应的世界位置爆炸（暂无摄像头则以鼠标路径验证同一代码路径）
2. 右键/张掌护盾挡下枪兵弹雨，法力持续下降，空蓝破盾
3. 五法术消耗与主计划表一致；蓝不足 fizzle 有提示
4. F1 HUD 在 3D 模式正常显示（延迟/姿势/法力/得分）
5. `--e2e-test`（合成手部数据走真实管线）依旧全绿——手势层未破坏

## 风险与回退
- **张掌护盾与施放张掌冲突**（FSM 的 PALM 既是施放确认又是护盾）：靠状态区分——FSM 非 IDLE 时的张掌=施放，IDLE 持续张掌=护盾；若实测误触发多，改为"握拳→张掌保持 0.5s 后"才起盾
- **3D 模式下 CanvasLayer 事件穿透**：准星用 `_draw` 自绘不走 Control，避免抢鼠标事件；HUD Control 设 `mouse_filter=IGNORE`
