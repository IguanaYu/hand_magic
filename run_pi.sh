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
# 摄像头自动识别：USB(UVC) 直接用；CSI 排线摄像头自动用 libcamerify 包装
# （Bookworm 的 libcamera 栈下，普通 V4L2 打不开 CSI 摄像头）。
# 手动指定：./run_pi.sh game --csi 或 --usb。
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

# ---------- 摄像头采集方式探测 ----------
CAM_WRAP=""      # "libcamerify" = CSI；空 = 直接 V4L2（USB）
CAM_DESC=""

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
    if ! command -v libcamerify >/dev/null 2>&1; then
        echo "检测到 CSI 排线摄像头，但缺少 libcamerify。执行："
        echo "  sudo apt install -y libcamerify"
        exit 1
    fi
    CAM_WRAP="libcamerify"
    return 0
}

detect_cam() {
    detect_uvc && return 0
    detect_csi && return 0
    echo "警告：没找到摄像头。USB 摄像头插上即用；CSI 排线摄像头需在 raspi-config"
    echo "      里开启 Camera 接口并重启。继续以无摄像头模式启动（鼠标兜底）。"
}

MODE="${1:-game}"
shift || true

# 手动覆盖采集方式
for flag in "$@"; do
    case "$flag" in
        --csi) CAM_WRAP="libcamerify"; CAM_DESC="CSI（手动指定）" ;;
        --usb) CAM_WRAP=""; CAM_DESC="USB（手动指定）" ;;
    esac
done

# 需要摄像头的模式才探测
case "$MODE" in
    camera|game) detect_cam ;;
    camcheck)
        detect_cam || true
        echo "采集方式: ${CAM_WRAP:-直接 V4L2}　${CAM_DESC}"
        exit 0
        ;;
esac

run_godot() {
    if [ -n "$CAM_WRAP" ]; then
        echo "摄像头: $CAM_DESC → 用 $CAM_WRAP 启动"
        exec $CAM_WRAP "$GODOT" "$@"
    else
        [ -n "$CAM_DESC" ] && echo "摄像头: $CAM_DESC"
        exec "$GODOT" "$@"
    fi
}

case "$MODE" in
    import) exec "$GODOT" --headless --import --path "$DIR" ;;
    smoke)  exec "$GODOT" --headless --path "$DIR" -- --smoke-test "$@" ;;
    camera) run_godot --path "$DIR" -- --camera-test --max-hands=1 "$@" ;;
    game)   run_godot --path "$DIR" -- --max-hands=1 "$@" ;;
    *) echo "用法: ./run_pi.sh [import|smoke|camcheck|camera|game] [--csi|--usb|其他透传参数]"; exit 1 ;;
esac
