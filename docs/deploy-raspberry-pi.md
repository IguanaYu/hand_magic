# RuneHand 树莓派部署指南（Pi 4 / 4GB）

2026-10-05 评估并准备好部署包。核心结论：**项目零改动可跑在 64 位树莓派上**。
Linux ARM64 的 GDMP 库随项目携带在 `deploy/rpi/libGDMP.linux.so`，由 `run_pi.sh`
在树莓派上首次运行时自动就位到 `addons/GDMP/libs/arm64/`（其动态依赖仅 glibc /
libstdc++ / libGLESv2 / libEGL，Pi OS 桌面版全部自带）。

> ⚠️ **Windows 开发机注意**：arm64 库以 `deploy/rpi/libGDMP.linux.so.bin` 的
> 扩展名随项目携带。**不要**在 Windows 上把它改名回 `.so` 放进项目——实测
> 项目树里存在 `*.so` 时（无论在 addons/ 还是 deploy/，无论是否被 gdextension
> 引用），带场景运行的 GDScript 性能掉 2~3 倍（E2E 识别基准 8.9ms → 17~27ms，
> 疑似杀软对未签名 ARM64 ELF 的重复深扫）。`run_pi.sh` 在树莓派上会自动把
> `.bin` 还原成就位路径；在 Windows 上想恢复性能，删掉项目内所有真实 `.so`
> 即可。另一劳永逸的办法：给项目目录加 Windows Defender 排除项。

## 1. 前提检查（Pi 上执行）

```bash
uname -m                # 必须输出 aarch64；armv7l 说明是 32 位系统，需重刷 64 位
cat /proc/device-tree/model   # 确认机型
```

## 2. 装系统依赖

```bash
sudo apt update
sudo apt install -y fonts-noto-cjk v4l-utils libcamerify
```

- `fonts-noto-cjk`：HUD 中文提示需要（否则显示方块）。
- `v4l-utils`：提供 `v4l2-ctl`，启动器用它自动识别摄像头类型。
- `libcamerify`：**CSI 排线摄像头必需**（见第 5 节）。

## 3. 装 Godot 4.6.1 ARM64

从 GitHub `godotengine/godot-builds` 的 `4.6.1-stable` release 下载
`Godot_v4.6.1-stable_linux.arm64.zip`，解压出可执行文件，放到**项目根目录**：

```bash
unzip Godot_v4.6.1-stable_linux.arm64.zip   # 得到 Godot_v4.6.1-stable_linux.arm64
mv Godot_v4.6.1-stable_linux.arm64 /path/to/magic/
chmod +x /path/to/magic/Godot_v4.6.1-stable_linux.arm64
```

## 4. 拷贝项目并首次导入

把整个 `E:\godot\magic` 目录拷到 Pi（scp / U 盘 / git 均可，约 110MB，含
`deploy/rpi/` 里的 arm64 库），然后在项目根目录：

```bash
chmod +x run_pi.sh
./run_pi.sh import     # 首次必跑：自动把 arm64 库就位到 addons/ 并生成导入缓存
```

## 5. 摄像头（本项目用 CSI 排线摄像头）

CSI 摄像头在 Bookworm 上走 libcamera 栈，Godot 的普通 V4L2 后端**打不开**它，
`run_pi.sh` 会自动检测并用 `libcamerify` 代理（把 V4L2 调用转给 libcamera）。

前置一次性设置：

```bash
sudo raspi-config   # Interface Options → Camera → 开启，然后重启
./run_pi.sh camcheck   # 应输出：CSI 排线摄像头（libcamera: ...）→ 用 libcamerify 启动
```

自动识别错了可手动指定：`./run_pi.sh game --csi` 或 `--usb`。

若 `camcheck` 说"没找到摄像头"：
`rpicam-hello --list-cameras` 看 libcamera 能否枚举；不行就查排线是否插反
（金属面朝 USB 口一侧）、raspi-config 是否已开启 Camera。

libcamerify 偶发格式协商问题（camera_result.txt 里 `datatype=-1` 或画面异常）时，
先跑 `libcamerify rpicam-hello --list-cameras` 确认代理本身工作，再回来重试；
仍不行可临时换 USB 摄像头对比定位。

## 6. 测试与运行

```bash
./run_pi.sh smoke      # 逻辑冒烟（无摄像头也跑），看 tests/*.txt 全 PASS
./run_pi.sh camera     # 摄像头链路 8 秒，看 tests/camera_result.txt
./run_pi.sh game       # 正式玩
```

`camera_result.txt` 判读：

- `results_received > 0` 且 `verdict=PASS`：识别链路通。
- `latency_ms`：端到端延迟（EMA）。M0 目标 ≤150ms；Pi 4 预计 80~150ms。
- `frames_dropped / frames_sent`：在途节流丢弃比例。Pi 4 上 50%~70% 属正常
  （30fps 采集 vs ~10fps 推理），丢弃是为了把延迟钉死而不是排队堆积。

## 7. 故障排查

| 症状 | 处理 |
| --- | --- |
| 窗口起不来 / 黑屏 | Bookworm 默认 Wayland，加 `--display-driver x11` 重试（走 XWayland） |
| 中文变方块 | `sudo apt install fonts-noto-cjk` 后重启游戏 |
| 延迟明显高于 150ms | 确认启动参数带 `--max-hands=1`；改善光照（暗光下检测更慢）；`vcgencmd measure_temp` 看是否过热降频（>80°C 加散热） |
| 找不到摄像头 | `v4l2-ctl --list-devices` 确认设备节点；CSI 摄像头见第 5 节 |
| `libGDMP.linux.so` 加载失败 | 系统是 32 位（`uname -m` 不是 aarch64） |

## 8. 性能说明（Pi 4）

- 推理是 CPU（4×A72），识别端瓶颈在 hand_landmarker；游戏逻辑本身很轻
  （$1 识别器仅施放时执行 ~8ms）。
- 启动器默认 `--max-hands=1`：游戏逻辑只消费第一只手（`main.gd _latest_hands[0]`），
  单手模式省掉第二只手的 landmark 推理开销。想测双手：`./run_pi.sh game --max-hands=2`。
- 摄像头 640x480@30 采集即可，MediaPipe 内部会缩到 256x256，无需降采集分辨率。
