# RuneHand M1 — 第一人称手势施法战场（3D）

> 玩法：站在人族阵地前，星际枪兵/掠夺者从两侧涌来开枪，你用**手势画符施法**守住阵地。
> Godot 4.6.1（Forward+）+ GDMP v0.6 + CarBot 风星际 3D 素材包。
> 设计与里程碑文档：`docs/m1-plan.md` + `docs/m1-0 ~ m1-6`。

## 素材版权说明

- `素材/starcrafts_carbot_kit/` 为**个人同人习作**（Blender 脚本生成的 CarBot《StarCrafts》风格 3D 资产），游戏实际使用的子集在 `assets3d/`
- StarCraft（星际争霸）IP 归 **暴雪娱乐** 所有；CarBot 画风版权归 **Carbot Animations**
- 本仓库仅作**个人学习与开发备份**：素材请勿商用、勿再分发；如需公开传播本项目，请先自行确认授权或替换素材

## 运行

```bash
# Godot 4.6.1 打开项目按 F5，或命令行：
"Godot_v4.6.1-stable_win64.exe" --path E:\godot\magic

# 快速目检（自动截图退出）：
"Godot_v4.6.1-stable_win64.exe" --path E:\godot\magic -- --shot3d
```

## 操作

| 输入 | 动作 |
|---|---|
| 握拳 → 画符 → 张掌 | 施法（◯火球 / Z链电 / △冰域 / ╱风刃） |
| 握拳 → 直接张掌 | 掌心火弹（自动瞄准最近敌人） |
| **空闲持续张掌 ≥0.3s** | 魔法护盾（挡正面子弹，耗蓝 12/s，空蓝破碎） |
| 鼠标左键按住 | 无摄像头兜底：按住=聚气/画符，松开=施放 |
| 鼠标右键按住 | 护盾兜底 |
| 键盘 1-5 | 调试直放法术（瞄准=鼠标位置） |
| R / F1 / ESC | 重开 / 调试 HUD / 退出 |

瞄准 = 手掌/鼠标位置 → 相机射线 → 辅助命中球（远距离更宽松）+ 地面落点。

## 敌人与法术（初版数值，调平入口 `wave_table.gd` + 各脚本常量）

- 枪兵 HP30：3 连发×4 伤（70% 命中，失准弹擦屏）；掠夺者 HP100：单发 12 伤
- 火球 40 伤 AoE r2.5m / 链电 25×3 / 冰域冻 3s+10 / 风刃 18+击退 / 掌心火弹 8
- 波次：第 N 波 3+2N 枪兵，第 3 波起混掠夺者；清波 +50 分回 30 蓝；无尽记分，最佳成绩持久化

## 测试

```bash
G="Godot_v4.6.1-stable_win64_console.exe"
"$G" --headless --path E:\godot\magic -- --anim-probe        # GLB 动画资产（marine/marauder×3段）
"$G" --headless --path E:\godot\magic -- --battle3d-test     # 3D 战场 20 项断言
"$G" --headless --path E:\godot\magic -- --smoke-test        # M0 冒烟 14 项
"$G" --headless --path E:\godot\magic -- --e2e-test          # M0 端到端 35 项
"$G" --headless --path E:\godot\magic -- --game-test         # 旧守卫法阵 9 项（--ward 进入游戏）
```

**当前状态（2026-10-05）**：battle3d 20/20 ✓、smoke 14/14 ✓、e2e 35/35 ✓、game 9/9 ✓、anim-probe PASS ✓、带窗口零脚本错误。

## 工程结构（M1 新增）

```
assets3d/units|buildings|env/   星际 CarBot GLB（单件自带动画；素材/ 已 .gdignore）
scripts/battle3d/
  battlefield_3d.gd   战场：场景搭建/波次/玩家HP/子弹/HUD/护盾/受击反馈
  enemy_unit_3d.gd    敌人：状态机 ADVANCE→HALT→FIRE/MELEE/DIE + 动画 + 演出壳
  enemy_bullet_3d.gd  曳光弹
  spell_caster_3d.gd  瞄准射线 + 五法术 3D 特效与判定
  shield_3d.gd        魔法护盾
  wave_table.gd       波次数值表（调平衡只改这里）
  battle_hud.gd       HP/MP/波次/得分自绘 HUD
  crosshair.gd        准星（命中敌人变红）
  damage_label.gd     伤害飘字
scripts/（M0 手势管线，未改动）
```

## 已知事项

- 本机无摄像头：鼠标兜底完整可玩；真实手势链路需有摄像头的机器验证（`--camera-test`）
- 新增 `class_name` 脚本后必须重跑 `--import`（刷新全局类缓存），否则 Parse Error 连锁
- GDMP headless 报 extension class 重复注册属已知噪音；`--import` 可能段错误收尾（缓存已生成）
- e2e 的识别耗时微基准对机器负载敏感（后台跑 Blender 时可能 FAIL，负载空闲即恢复）
- 旧模式：`--ward`=守卫法阵（M0.5）、`--practice`/`--e2e-test`=练习靶
