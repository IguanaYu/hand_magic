#!/usr/bin/env bash
# RuneHand 树莓派启动器。把整个项目目录和 Godot arm64 可执行文件放在一起，
# 在项目根目录执行：
#   ./run_pi.sh import   # 首次必跑：就位 arm64 库 + 生成资源导入缓存
#   ./run_pi.sh smoke    # 逻辑冒烟测试（无摄像头也能跑）
#   ./run_pi.sh camcheck # 列出摄像头与选择的采集方式
#   ./run_pi.sh camera   # 摄像头链路测试（8 秒，结果落 tests/camera_result.txt）
#   ./run_pi.sh game     # 正式运行（Pi 4 默认 --max-hands=1）
# 额外参数原样透传，如：./run_pi.sh game --max-hands=2
#
# 摄像头采集（按优先级）：
#  1. CSI 排线 + rpicam-vid（默认）：MJPEG 硬件管线 → 本机 TCP → 游戏。
#     Pi 上 Godot 的 V4L2 后端颜色错乱（NV21 被当 RGB），rpicam 是唯一正路；
#     识别走"远程识别服务"（PC 上运行 run_tracker_server.bat）。
#  2. USB(UVC)：直接用 Godot 的 V4L2（--tracker=remote）。
# 3. 识别后端可用 --tracker= 强制指定：local|remote|rpicam。
#
# 注意：arm64 库平时放在 deploy/rpi/ 而不是 addons/ 里——Windows 开发机上
# .gdextension 引用路径下存在该文件会让 GDScript 跑分掉 3 倍（杀软重复扫描），
# 所以只在树莓派上由本脚本就位到 addons/GDMP/libs/arm64/。
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-$DIR/Godot_v4.6.1-stable_linux.arm64}"
if [ ! -x "$GODOT" ]; then
    echo "找不到 Godot：$GODOT"
    echo "把 Godot_v4.6.1-stable_linux.arm64 放到项目根目录并 chmod +x，或 export GODOT=/path/to/godot"
    exit 1
fi
# 首跑就位 arm64 库（幂等）。库里在项目内以 .bin 扩展名携带（Windows 杀软
# 不扫 .bin，但会反复深扫 *.so 拖慢整机），就位时还原成 Godot 要的文件名。
if [ ! -f "$DIR/addons/GDMP/libs/arm64/libGDMP.linux.so" ] && [ -f "$DIR/deploy/rpi/libGDMP.linux.so.bin" ]; then
    mkdir -p "$DIR/addons/GDMP/libs/arm64"
    cp "$DIR/deploy/rpi/libGDMP.linux.so.bin" "$DIR/addons/GDMP/libs/arm64/libGDMP.linux.so"
    echo "已就位 addons/GDMP/libs/arm64/libGDMP.linux.so"
fi

# ---------- rpicam MJPEG 帧源 ----------
RPICAM_PORT=8899
RPICAM_PID=""
start_rpicam() {
    rpicam-vid -t 0 --width 640 --height 480 --framerate 30 \
        --codec mjpeg --inline --listen -o "tcp://127.0.0.1:$RPICAM_PORT" \
        >/tmp/rpicam.log 2>&1 &
    RPICAM_PID=$!
}
stop_rpicam() {
    if [ -n "$RPICAM_PID" ]; then
        kill "$RPICAM_PID" 2>/dev/null || true
        wait "$RPICAM_PID" 2>/dev/null || true
        RPICAM_PID=""
    fi
}
trap stop_rpicam EXIT

# ---------- 摄像头采集方式探测 ----------
CAM_WRAP=""      # "libcamerify" = CSI 走 Godot V4L2（仅 USB 之外的老路径备用）；空 = 直接 V4L2
CAM_DESC=""
TRACKER_ARGS=""  # 追加给游戏的识别参数

detect_uvc() {
    local d
    for d in /dev/video*; do
        [ -e "$d" ] || continue
        if v4l2-ctl -d "$d" -D 2>/dev/null | grep -qi "Driver name.*uvcvideo"; then
            CAM_DESC="USB 摄像头（$d, uvcvideo）"
            return 0
        fi
    done
    return 1
}

detect_csi() {
    # Bookworm 用 rpicam-hello，旧系统用 libcamera-hello
    local tool=""
    command -v rpicam-hello >/dev/null 2>&1 && tool="rpicam-hello"
    [ -z "$tool" ] && command -v libcamera-hello >/dev/null 2>&1 && tool="libcamera-hello"
    [ -z "$tool" ] && return 1
    "$tool" --list-cameras 2>/dev/null | grep -q "Available cameras" || return 1
    CAM_DESC="CSI 排线摄像头（libcamera: $tool）"
    return 0
}

detect_cam() {
    detect_uvc && return 0
    detect_csi && return 1  # 1 = CSI（详见下方分支）
    echo "警告：没找到摄像头。USB 摄像头插上即用；CSI 排线摄像头需在 raspi-config"
    echo "      里开启 Camera 接口并重启。继续以无摄像头模式启动（鼠标兜底）。"
    return 2
}

MODE="${1:-game}"
shift || true

# 手动覆盖采集方式
for flag in "$@"; do
    case "$flag" in
        --csi|--usb) echo "（--csi/--usb 已由 rpicam 自动路径取代，参数忽略）" ;;
    esac
done

# 需要摄像头的模式才探测
case "$MODE" in
    camera|game)
        if command -v rpicam-vid >/dev/null 2>&1 && detect_csi; then
            # 首选：rpicam 硬件管线（色彩正确）
            CAM_DESC="CSI（rpicam MJPEG 硬件管线 tcp://127.0.0.1:$RPICAM_PORT）"
            TRACKER_ARGS="--tracker=rpicam --rpicam-port=$RPICAM_PORT"
            start_rpicam
            echo "摄像头: $CAM_DESC"
        elif detect_cam; then
            TRACKER_ARGS="--tracker=remote"
            echo "摄像头: $CAM_DESC → Godot V4L2（远程识别）"
        else
            TRACKER_ARGS="--tracker=remote"
        fi
        ;;
    camcheck)
        detect_cam || true
        echo "采集方式: ${TRACKER_ARGS:-未定}　${CAM_DESC}"
        command -v rpicam-vid >/dev/null 2>&1 && echo "rpicam-vid 可用（CSI 将走 MJPEG 硬件管线）"
        exit 0
        ;;
esac

run_godot() {
    # Pi 4 实测（2026-10）：Vulkan(Mobile 渲染器)会耗尽 CMA 显存（BO 分配失败卡死主循环），
    # Wayland 下 gl_compatibility 不被支持（报 driver not supported）；
    # X11(XWayland)+gl_compatibility 稳定通过 camera-test。PI_GFX 可整体覆盖。
    # 不用 exec：rpicam-vid 子进程需要在游戏退出后由 trap 清理。
    local gfx="${PI_GFX:---display-driver x11 --rendering-method gl_compatibility}"
    "$GODOT" $gfx "$@"
}

case "$MODE" in
    import) exec "$GODOT" --headless --import --path "$DIR" ;;
    smoke)  exec "$GODOT" --headless --path "$DIR" -- --smoke-test "$@" ;;
    camera) run_godot --resolution 640x480 --path "$DIR" -- --camera-test --max-hands=1 $TRACKER_ARGS "$@"; RC=$?; exit $RC ;;
    game)   run_godot --fullscreen --path "$DIR" -- --max-hands=1 $TRACKER_ARGS "$@"; RC=$?; exit $RC ;;
    *) echo "用法: ./run_pi.sh [import|smoke|camcheck|camera|game] [--max-hands=N 等]"; exit 1 ;;
esac
