# M1.2 实施文档：战斗闭环

> 前置：M1.1 完成。产出：敌人会开枪打玩家，玩家（鼠标/键盘兜底）能放法术杀敌，完整的伤害-死亡-记分循环。

## 目标

打通"敌人射击 → 玩家掉血 → 玩家施法 → 敌人死亡 → 记分"。瞄准用鼠标（M1.3 才接手势锚点），键盘 1-5 直放法术做调试通道。

## 任务分解

### 1. `scripts/battle3d/enemy_bullet_3d.gd`（新建，class_name EnemyBullet3D extends Node3D）
- [ ] 视觉：拉伸的 `BoxMesh`/`CylinderMesh` 自发光（枪兵黄色细弹、掠夺者橙色大弹），+ OmniLight3D 低能量（Forward+ 泛光）
- [ ] 运动：世界空间直线飞向目标点（玩家胸口 ± 散布）；失准弹目标点加横向偏移——**擦过相机**的演出感
- [ ] 命中判定：与玩家距离 < 0.8m → `battlefield.player_hit(dmg)`；飞行 4s 超时销毁
- [ ] 接口 `blockable := true`（护盾格挡用，M1.3）

### 2. 敌人开枪（enemy_unit_3d.gd 补 FIRE 状态）
- [ ] 枪兵：`FIRE` 循环 = 攻击动画期间 3 连发（0.12s 间隔），每发 4 伤、命中判定 ~70%（失准弹照飞）；轮间隔 1.8s
- [ ] 掠夺者：单发 12 伤、弹速慢（12 m/s vs 枪兵 30 m/s）、轮间隔 2.6s
- [ ] `MELEE`：3m 内 1.2s 一次猛击 15 伤（动画复用 attack）
- [ ] 枪口位置：模型包围盒上方偏前（`UnitStats` 里配 muzzle_offset），子弹从此出发
- [ ] **冰冻交互**：frozen 期间不开枪、攻速减半

### 3. 玩家受击（battlefield_3d.gd）
- [ ] `player_hp := 100.0`，`player_hit(dmg)`：扣血 + 屏幕红闪（CanvasLayer 全屏 ColorRect tween）+ 相机震屏（位置噪声 0.25s）
- [ ] HP≤0 → 游戏结束（简版：浮层显示得分，R 重开——完整流程 M1.4）

### 4. `scripts/battle3d/spell_caster_3d.gd`（新建，class_name SpellCaster3D extends Node3D）
**瞄准**：
- [ ] `aim_from_screen(screen_pos) -> Dictionary`：`camera.project_ray_origin/normal` → 逐敌射线-球体检测（球心=敌 position+1m 高，r=1.2×模型缩放），命中返回敌人；否则与 y=0 地面平面求交返回落点
- [ ] 准星：鼠标位置画十字（2D CanvasLayer），射线命中敌人时准星变色

**五法术（3D）**：
- [ ] **火球**：SphereMesh 自发光+OmniLight 投射物从屏幕底中 (0,-0.5,7) 飞向瞄准点（18 m/s 抛物线微弧）；命中敌/落地 → AoE：r2.5m 内敌 take_damage(40) + 爆炸特效（CPUParticles3D 一次性 40 粒 + 光闪）
- [ ] **链电**：瞄准点（或命中敌）向最近 3 敌各 25 伤；视觉 = ImmediateMesh 折线（每段 6 段随机抖动）白蓝色，0.2s 消失；段间命中闪光
- [ ] **冰域**：地面落点扩张冰环（TorusMesh 半透明 + CPUParticles3D 冰晶），r6m 敌 apply_freeze(3)（掠夺者 2s）+10 伤
- [ ] **风刃**：玩家前方 60° 扇形 r8m 内敌 18 伤 + 击退（沿玩家→敌方向推 3m，打断 FIRE 回 ADVANCE 0.5s 硬直）；视觉 = 白青弧面网格扫过 0.3s
- [ ] **掌心火弹**：自动瞄最近敌，8 伤小火球
- [ ] 伤害飘字：敌人头顶 3D 位置投影到屏幕，Label 上浮淡出（ObjectPool 简化为数组管理）

**接入**：
- [ ] `cast(spell_id, screen_pos)` 统一入口；键盘 1-5 调试直放（瞄准=当前鼠标位）
- [ ] 本里程碑不接法力消耗（M1.3 接 FSM 后统一）

### 5. 死亡与记分（battlefield_3d.gd）
- [ ] EnemyUnit3D DIE：tween 炸飞（随机方向 2-4m + 旋转 720° + 缩放压扁 0.6）+ CPUParticles3D 爆散 12 粒；0.6s 后 queue_free
- [ ] `score += 10/30`，击杀数 +1；HUD 显示

## 验收标准
1. 带窗口：敌人到停距开枪，曳光弹朝相机飞；被命中红闪+掉血；失准弹从视野边缘擦过
2. 鼠标点哪火球炸哪；Z 闪电链 3 个；冰环冻住敌人（变慢+停火）；风刃把近身敌人推走
3. 敌人血量归零炸飞演出+记分正确（HUD 数字对）
4. 玩家 HP 打空出游戏结束浮层
5. `--battle3d-test` 新增断言全过：子弹命中扣血 / 火球 AoE 伤害 / 链电选 3 目标 / 死亡记分 / 游戏结束触发

## 风险与回退
- **性能**（Forward+ 每弹一盏灯）：子弹光改为共享材质自发光+无灯，泛光靠 bloom 阈值；仍卡则子弹纯发光条
- **射线球检测手感差**（敌人小远难命中）：命中球半径按距离放大（近 1.0m/远 1.5m），即"辅助瞄准"
- **链电/风刃视觉成本**：先用最小可看版本（折线/半透明面），M1.5 统一打磨

## 执行记录（2026-10-05）

- `enemy_bullet_3d.gd` ✅：曳光弹（枪兵黄色细弹/掠夺者橙色大弹）、失准弹横向偏移擦屏、接近胸口判定
- 敌人开火 ✅：FIRE 状态连发逻辑（枪兵 3 连发/掠夺者单发）、冰冻停火、MELEE 猛击、stun_t 硬直、knockback() 击退
- 玩家受击 ✅：红闪 tween + 相机震屏 + 游戏结束浮层（简版，完整流程 M1.4）
- `spell_caster_3d.gd` ✅：射线球检测（辅助瞄准半径随距离 0.8→1.6m）、五法术 3D 化（火球投射物+双球爆炸 / 链电 ImmediateMesh 折线从天而降 / 冰域地面盘 / 风刃扇面三角带 / 掌心火弹单体）
- `damage_label.gd` 飘字 ✅、`crosshair.gd` 准星（命中敌人变红）✅、键盘 1-5 调试施法 ✅
- `--battle3d-test` ✅ 15/15：新增子弹命中/开火产生曳光弹/火球 AoE 范围判定/链电恰 3 目标/冰域冻结/风刃击退(5→8m)/游戏结束与重开
- 截图 AI 复核 ✅：火球可见、准星正常、无渲染异常
- 回归：smoke 14/14、game 9/9、e2e 35/35（性能项复测通过，确认此前为 Blender 负载抖动）
- 踩坑：①新增 class_name 后必须 `--import` 刷新类缓存；②截图分支 lambda 变量名写错（battlefield→battle3d）导致解析失败窗口空挂——错误在窗口模式下不打印到管道，注意 headless 先验
