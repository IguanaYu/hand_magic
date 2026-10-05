# M1.1 实施文档：敌人入场

> 前置：M1.0 完成。产出：敌人从两侧走来，能停能瞄准。
> **状态：✅ 完成（2026-10-05）**

## 目标

敌人（枪兵/掠夺者）在地面从左右两侧/远处走向玩家，走路动画、朝向、缩放正确；到停距后停下切 idle/attack 姿态。本里程碑敌人还不开枪（M1.2 内容），但状态机骨架一次写全。

## 任务分解

### 1. `scripts/battle3d/enemy_unit_3d.gd`（新建，class_name EnemyUnit3D extends Node3D）

**结构**：
- `_ready()`：按 `unit_key` 实例化对应 GLB 作为子节点；缓存 `AnimationPlayer`
- 世界坐标 = 自身 transform；模型面朝 +Y（素材规范），移动朝向用 `look_at` 后修正

**属性**：
```gdscript
var unit_key := "marine"          # marine / marauder
var hp: float                      # 30 / 100
var speed := 1.6                   # m/s
var stop_dist := 10.0              # 10 / 14
var melee_dist := 3.0
var alive := true
var frozen_t := 0.0                # 冰冻剩余（减速 55%）
signal died(unit)
signal reached_melee(unit)
```

**状态机**（enum State：ADVANCE / HALT / FIRE / MELEE / DIE）：
- `ADVANCE`：朝玩家 XZ 平面直线走（`position += dir * speed * factor * delta`），播 `<key>_move`；每 0.3s 重算朝向
- 进 `stop_dist` → `HALT`（0.4s 举枪过渡，播 idle）→ `FIRE`（播 `<key>_attack` 循环；开火逻辑 M1.2 填）
- 玩家在 `melee_dist` 内 → `MELEE`（M1.2 填伤害）
- `take_damage(dmg)` 接口：扣血、受击闪白（M1.5 打磨，先做数值）；`hp<=0` → `DIE`
- `apply_freeze(sec)` / 减速因子处理

**动画工具**：
- `_play(clip)`：`<key>_move` 映射，带 0.15s 淡入；循环 clip 设 `loop_mode`
- 死亡演出（本里程碑先简版）：tween 旋转+抛物线飞出 0.6s + queue_free；M1.5 加粒子

### 2. 生成器（并入 battlefield_3d.gd 或独立 `enemy_spawner_3d.gd`）
- [ ] 生成点：左右两翼弧线（左侧 x∈[-38,-28]、z∈[-30,-10] 随机；右侧对称）+ 正面远处（z≈-35，少量）
- [ ] 生成节奏（本里程碑测试用）：每 2.5s 一只，交替左右，marine:marauder = 3:1；上限 20 只
- [ ] `enemies: Array[EnemyUnit3D]` 登记管理，死亡信号统一接 battlefield 记分

### 3. HUD 雏形（CanvasLayer，挂在 battlefield 内）
- [ ] 屏幕底部 HP 条（红色，100 上限）+ 敌人计数（本里程碑占位显示）
- [ ] 复用 M0 `DebugHud`（F1 切换）——挂在 CanvasLayer，显示 FPS/手数/法力（手势数据 M1.3 才有，先显示占位）

### 4. 相机小庙检查
- [ ] 确认敌人从两侧走近时**近大远小**透视正确、不被相机裁剪（`near=0.1`）
- [ ] 敌人 look_at 玩家后模型**面向相机**（素材面朝 +Y，look_at 的 -Z 朝向需 +90° 修正；实测为准）

## 验收标准
1. 带窗口跑：枪兵/掠夺者从左右两侧持续入场，走路动画循环流畅、无滑步感（动画是原地跑步机式，位移由引擎驱动，天然对齐）
2. 敌人到停距停下，切 idle 攻击姿态动画正确
3. 任意时刻场上 ≤20 只，死亡后正确移除（先手动 `take_damage(999)` 验证）
4. `--battle3d-test` 骨架：生成→位置递进→停距状态切换，3 项断言通过（headless）

## 风险与回退
- **朝向修正角不对**：写一个 `--anim-probe` 式的小场景肉眼调，常数写进脚本顶部
- **动画播放卡顿**（Forward+ 首次编译着色器）：预热——场景 ready 后先各播 0.1s idle
- **敌人穿模布景**：生成点/路径避开布景坐标（布景散布时留出 |x|<20 的中路走廊，两侧才有障碍）

## 执行记录（2026-10-05）

- `enemy_unit_3d.gd` ✅：ADVANCE→HALT(0.4s)→FIRE/MELEE 状态机、数值表内置、take_damage/apply_freeze、炸飞死亡演出、动画错峰
- 朝向一次到位：模型面朝本地 +Z（Blender +Y→glTF +Z），`rotation.y = atan2(d.x, d.z)`，截图 AI 复核全部面向玩家 ✓
- 生成器并入 battlefield_3d.gd ✅：2.5s 间隔、左右交替、4:1 枪兵掠夺者、20% 正面远处、上限 20
- `battle_hud.gd` ✅：HP/MP 条 + 波次/敌人数/得分自绘 HUD（不拦截鼠标）
- `--battle3d-test` ✅ 8/8：构建/生成/前进/停距/死亡移除/记分/冻结/重开
- 首轮测试两处失败均为测试自身问题（等待时长不足、断言顺序），已修
- 发现与决策：**停距 10/14m > 近战 3m，纯远程敌人永远不会触发近战**——MELEE 分支保留（为后续近战单位如小狗预留），marine/marauder 靠射击压制
- 类缓存教训：新建 class_name 脚本后必须重跑 `--import` 刷新全局类缓存，否则连锁 Parse Error 且测试进程不退出（超时挂起）

## 修正记录（2026-10-05 用户反馈）

**朝向 bug**：首版 `rotation.y = atan2(d.x, d.z)` 把模型屁股对着行进方向。原因：素材规范"面向 +Y"是 Blender 坐标，经 glTF 转换后正面在本地 **-Z**（不是 +Z）。修复：+PI 修正。教训：两段路径（横穿走）让 bug 暴露——朝玩家走时脸/屁股远看难辨，AI 截图复核没抓出来；**朝向类问题要看侧向移动画面**。建筑同理（正面也是 -Z），布景 rot PI 实为正面朝玩家，暂未改（外观对称，无碍）。
