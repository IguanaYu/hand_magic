# RuneHand（符文之手）项目说明

手势施法波次生存游戏：摄像头识别手势，空中画符放法术。Godot 4.6.1 + MediaPipe（GDMP）。

## 新会话先看这里

- **真人待办**：`docs/todo-manual-test.md` —— 用户要手动测试的清单（法术装备面板/图鉴/扩展手势）。
  用户问"有啥需要我做的"时，答案基本在这个文件；测完或过期就更新/归档它。
- 运行/操作/测试命令：`README_M1.md`（3D 战场，主入口）；`README_M0.md`（旧 2D）。
- 设计文档：`docs/gdd-runehand-v0.1.md`；全部文档索引在 `README_M1.md` 的"文档索引"节。

## 项目速览

- 手势管线：`scripts/pose_classifier.gd`（姿势）→ `gesture_fsm.gd`（状态机+开关）→ `dollar_recognizer.gd`（$1 符文）。
  现役姿势：捏合画符 / 握拳聚气 / 张掌取消·护盾·火弹。
- 法术 5 个（数据源 `scripts/battle3d/spell_codex.gd`）：火球◯ / 链电Z / 冰霜△ / 风刃╱ / 掌心火弹。
- **扩展手势已实现未启用**：开关 `gesture_fsm.gd` 顶部 `static var extended_gestures`（默认 false）。
  启用 = 比耶/点赞/我爱你进分类器 + S 波替换三角成冰霜符文；启用前先清冰霜录制样本；详见 GDD §3.3.1。
- **法术装备栏（暂定 5 槽）**：C 键面板勾选，未装备三处施法全拦，存档 `user://spell_loadout.json`。
- 面板互斥三件套：H 图鉴（两页）/ G 录制 / C 配置，任一打开即暂停冻结战场。

## 约定

- 测试全套（改代码后必跑）：`--smoke-test --e2e-test --robust-test --game-test --battle3d-test --mario-test`，
  当前基线 smoke59 / e2e35 / game9 / battle3d60 / mario34 / robust PASS。测试会刷新 `tests/*_result.txt`、
  `pose_log.txt` 和 `.import`（仓库惯例，随提交入库）。
- 新增 `class_name` 脚本后先跑一次 `--headless --editor --quit` 刷新全局类缓存，否则 Parse Error 连锁。
- 树莓派部署：`docs/deploy-raspberry-pi.md`；远程识别：`docs/plan-pi-remote-tracker.md`。
- commit message 用中文长文说明动机（看 git log 风格），改完即跑测试即推送。
