# 树莓派远程识别：收尾计划与情况分析

> 2026-10-06 制定。目标：把「Pi 跑游戏 + PC 跑手势识别」架构打磨到**能正式游玩**。
> 背景结论：通信链路已实测打通（78 帧 / 77 回包 / 端到端 72ms，目标 ≤150ms），
> 卡在最后一公里——rpicam 帧源路径的一个脚本错误。

## 〇、现状快照

| 模块 | 状态 | 依据 |
| --- | --- | --- |
| Pi 环境（~/magic、Godot arm64、依赖） | ✅ | import/smoke/枚举全过 |
| 识别服务（PC 端 tracker_service.gd） | ✅ | 模型加载、自动连接、正常回包 |
| 通信链路（WS + JPEG/JSON 协议） | ✅ | camera-test PASS，72ms |
| 摄像头像素（Godot V4L2 路径） | ❌ 确认坏 | camera_shot.png 紫绿错乱（NV21 被当 RGB）|
| rpicam MJPEG 帧源（替代路径） | 🔨 代码完，未验证 | 卡 main.gd:453 |
| 全屏正式游玩 / 稳定性 / 文档 / commit | ⬜ 未开始 | — |

架构与坑都已记入项目记忆（pi-remote-tracker-setup）。

## 一、Phase 1：修通 rpicam 路径（当前唯一阻塞）

### 1.1 定位 main.gd:453 空引用（预计 ≤1 小时）

现象：camera-test + rpicam 后端下，`_process` 每帧刷
`Invalid access to property or key 'state' on Nil`，8 秒定时器从未触发
（说明 `_build_scene`/`_wire_signals` 中途被打断，timer 没建上），
游戏挂到 70s 被 timeout 杀掉。

**排查方法**：ssh 跑 `./run_pi.sh camera`，看完整日志里 **453 之前出现的第一个
SCRIPT ERROR**（第一个才是根因，后面都是雪崩）。

**可能情况与对策**：

| 情况 | 可能性 | 机理 | 对策 |
| --- | --- | --- | --- |
| A. camera-test 分支没初始化 fsm/hud 某引用，rpicam 帧流起来后踩中 | 高 | 以前 V4L2 路径 frames 从来没真流起来（webp 空包 / 1 帧卡死），潜伏空引用从没被喂过数据；rpicam 路径帧真的流动了，把老 bug 暴露 | 在 camera-test 分支补初始化或 _process 加空保护（最小改动） |
| B. _inject_frame 时序早于 preview 组件就绪 | 中 | add_child 顺序导致 rpicam 的 _process 先跑，_cam_texture_rect/_viewport 还是 null | _inject_frame 入口判空；或 setup() 完成标志位 |
| C. 新代码里另有类型/调用错误 | 低 | 453 只是第一个可见症状 | 按日志逐个修 |

### 1.2 验证画面色彩（修通后立刻做）

回传 `tests/camera_shot.png` 检查：非紫绿、能认出真实场景。

- **预期正常**（最可能）：rpicam-jpeg 实拍色彩一直正确，ISP 管线可信；
- 若仍偏色：查 flip_h 镜像逻辑 / JPEG 解码后的 FORMAT 转换。

### 1.3 验证真实识别（需要一只手）

镜头前挥手（或举一张手掌照片），看 `hands_frames > 0`、HUD 延迟数字。
用户不在场时可用打印的手掌图代替。

## 二、Phase 2：正式游玩打磨（约 1 小时，最好用户在场）

### 2.1 全屏 game 实测 `./run_pi.sh game`

| 情况 | 判定 | 对策 |
| --- | --- | --- |
| 1080p 流畅（≥30fps 体感） | 直接可玩 | — |
| 卡顿 | Pi 4 GLES 算力上限 | `--resolution 1280x720`（改 run_pi.sh game 行）或窗口化；识别链路不受影响 |

### 2.2 稳定性 soak（10~15 分钟连续运行）

- 温度：`vcgencmd measure_temp`（>80°C 加散热）；
- 内存：`free -h` 看泄漏趋势；
- **强烈建议直接插网线**：WiFi 当天掉过线，网线一次性消除识别卡顿的最大变数。

### 2.3 负载下的延迟

全屏 3D + 采流 + JPEG 解码并发后，HUD latency 预估 80~120ms，仍应达标（≤150ms）。
超标则：降识别帧率（保持 30fps 采集、隔帧识别）或降窗口分辨率。

## 三、Phase 3：工程收尾（约 1 小时）

1. Windows 回归：smoke（14 PASS 基线）+ 本机实玩一局，确认 local 路径零回归；
2. 重写 `docs/deploy-raspberry-pi.md`：删掉「零改动可跑」的错误结论，补
   glibc 真相、远程架构图、双端启动步骤（PC：run_tracker_server.bat；Pi：./run_pi.sh game）、
   故障排查表（driver not supported / BO 失败 / 黑紫画面 三条新坑）；
3. git commit（建议三笔：① tracker 重构+新识别器 ② rpicam 启动器+文档 ③ 测试探针）；
4. 可选：PC 端识别服务加到任务计划自启；给 run_pi.sh 加 nohup 玩法说明（无键盘退出）。

## 四、风险总表

| 风险 | 概率 | 影响 | 兜底 |
| --- | --- | --- | --- |
| 453 不是小 bug 而是设计问题 | 低 | 中 | 报错形态是典型空引用；真不行可退回 libcamerify 路径（协议已通）牺牲色彩另想办法 |
| rpicam 路径色彩仍不对 | 低 | 中 | ISP 输出已被照片验证；问题只可能在游戏内 flip/格式转换，可定位 |
| 全屏帧率不足 | 中 | 中 | 降分辨率即解，识别链路独立于渲染分辨率 |
| Pi CPU 三线并发（渲染+解码+收发）吃紧 | 中 | 低 | JPEG 硬件编码、解码 ~5ms/帧量级；必要时隔帧识别 |
| WiFi 抖动 | 中 | 低 | 插网线 |
| OV5647 暗光识别差 | 中 | 低 | 补光；长期可换 USB 摄像头（--tracker=remote 路径已留好） |

## 五、总体判断

架构方向已被实测数据支撑（72ms 回路），不存在需要推翻重来的已知风险。
剩余 = 一个空引用级别的 bug（三种情况里最坏的也是小时级）+ 性能调优 + 收尾。
**预计 1~2 个调试会话（合计 3~5 小时）内达到可玩状态。**
