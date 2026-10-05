# M1.4 实施文档：波次流程

> 前置：M1.3 完成。产出：完整的波次推进、胜负结算、重开循环，游戏"一局"成立。

## 目标

把"持续刷怪沙盒"变成"波次制游戏"：波次表驱动、波间喘息、游戏结束/重开、HUD 成型。

## 任务分解

### 1. `scripts/battle3d/wave_table.gd`（新建，class_name WaveTable）
- [ ] `static func wave(n) -> Dictionary`：
  - `marines = 3 + 2*n`
  - `marauders = 0 if n < 3 else ceili(float(n - 2) / 2.0)`（第3波1只、第5波2只…）
  - `spawn_interval = max(0.8, 2.6 - n * 0.15)`（生成渐密）
  - `intermission = 5.0`（波间）
- [ ] 数值集中此处，调平衡只改这个文件

### 2. 波次状态机（battlefield_3d.gd）
- [ ] enum：`INTERMISSION`（倒计时+横幅"第 N 波来袭"）→ `SPAWNING`（按表放怪）→ `CLEARING`（等清场）→ 下一波
- [ ] 波开始横幅（CanvasLayer 大字 2s 淡出）；清完波提示"波次肃清 +50 分"
- [ ] 全灭判定：`enemies.is_empty() and spawn_queue.is_empty()`
- [ ] 波间回蓝：法力回复 ×2 倍率（fsm 暴露 rate 乘数或 battlefield 直接加）

### 3. 游戏结束与重开
- [ ] HP=0 → `GAME_OVER`：慢动作 0.5s（`Engine.time_scale=0.3` 一秒后恢复）+ 浮层（得分/波次/击杀/最佳，R 重开）
- [ ] `restart()`：清场（enemies/bullets/fx 全 free）、重置 fsm+spell_caster+wave 状态
- [ ] 最佳成绩持久化 `user://best_score.cfg`（ConfigFile）

### 4. HUD 成型（CanvasLayer）
- [ ] 底部左：HP 条（红）+ 数值；HP 条受击时抖动
- [ ] 底部左下：法力条（蓝）
- [ ] 顶部中：`第 N 波` + 剩余敌人数 `12/15`
- [ ] 顶部右：得分 / 击杀 / 最佳
- [ ] 波间倒计时大字居中
- [ ] 受击方向指示（可选，超出则砍）：屏幕边缘红色扇形提示子弹来向

### 5. 开局体验
- [ ] 开场 3s：相机从城堡上方缓推到玩家站位（一次性 tween），横幅"守住阵地！"
- [ ] 跳过：任意键

## 验收标准
1. 一局完整体验：开场运镜 → 第 1 波 5 枪兵 → 击杀清场 → 波间 5s 回蓝 → 第 3 波出掠夺者 → … → 死亡结算 → R 重开一切重置
2. 波次构成与数值表一致（第 1 波 5 枪兵 0 掠夺者；第 3 波 9 枪兵 1 掠夺者）
3. 清波 +50 分、击杀分正确累计；最佳成绩跨局保留
4. `--battle3d-test` 波次断言：wave() 表数据 / 全灭进波间 / 死亡进 GAME_OVER / restart 清场

## 风险与回退
- **清场卡死**（敌人卡布景走不到近身）：ADVANCE 路径每 2s 检测进度 <0.2m 则横向绕行；仍卡则 30s 强制传送近身处
- **慢动作影响音频/计时器**：`Engine.time_scale` 只在 game over 用，tween 用 `process_callback=TWEEN_PAUSE_BOUND` 之外的独立模式避免被拉长

## 执行记录（2026-10-05）

- `wave_table.gd` ✅：静态 wave(n) 数值表（3+2N 枪兵 / 第3波起掠夺者 / 间隔渐密 2.6-0.15N 下限0.8 / 波间5s）
- 波次状态机 ✅：INTERMISSION(开场3s"守住阵地！")→SPAWNING(队列洗牌出怪)→CLEARING(全灭+50分回30蓝)循环；横幅大字淡出
- 游戏结束 ✅：含波次/得分/击杀/最佳；best 持久化 user://best_score.cfg；R 重开全重置
- HUD ✅：波间倒计时/第N波、敌人剩余（含未出场队列）、最佳成绩
- 清波回蓝 ✅：wave_cleared 信号 → main 给 fsm.mana +30
- 开场运镜与慢动作未做（低优先，记为后续可选）
- 测试 ✅ battle3d 20/20（新增：波次表数值/开波切换/清场+信号+奖励/重开重置）

## 执行记录补充（M1.5 精选四项，2026-10-05）
