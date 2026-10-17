extends "res://scripts/hand_tracker_remote.gd"
## rpicam 帧源 + 远程识别：树莓派上用官方 rpicam-vid（ISP 硬件管线，色彩正确）
## 走本机 TCP 输出 MJPEG，本节点解码后注入 HandTracker；识别部分复用父类
## （WS 服务端 + JPEG 上行 + JSON 下行）。
## 为什么不用 Godot 的 CameraFeed：Bookworm + libcamerify 下 V4L2 后端上报
## FEED_RGB 但实际给 NV21 字节，画面呈紫绿色错乱（2026-10 实测），识别无效。
## 由 run_pi.sh 启动：
##   rpicam-vid -t 0 --width 640 --height 480 --framerate 30 \
##     --codec mjpeg --inline --listen -o tcp//127.0.0.1:8899 &
##   ./run_pi.sh game   # Linux 默认即 rpicam 模式


func provides_frames() -> bool:
	return true


func configure(args: Dictionary) -> void:
	super.configure(args)
	_stream_port = int(args.get("rpicam_port", 8899))


func start() -> bool:
	# 父类只起 WS 服务端（等识别机连入）；rpicam-vid 由 run_pi.sh 负责拉起
	var ok := super.start()
	if ok:
		tracker.tracker_message.emit("rpicam 帧源: tcp://127.0.0.1:%d" % _stream_port)
	return ok


func _process(delta: float) -> void:
	super._process(delta)
	_poll_stream()


# ---------- MJPEG TCP 流 ----------

var _stream := StreamPeerTCP.new()
var _buf := PackedByteArray()
var _scan_pos := 0  # 增量扫描位置：每字节只看一次（find 原生速度）
var _soi := -1  # 当前帧 JPEG 起始（含 FFD8），-1=还在找帧头
var _stream_port := 8899
var _retry_wait := 0.0
var _last_st := -1


func _poll_stream() -> void:
	var st: int = _stream.get_status()
	if st != _last_st:
		_last_st = st
		print("RPICAM stream status -> ", st)
	if st == StreamPeerTCP.STATUS_NONE or st == StreamPeerTCP.STATUS_ERROR:
		_retry_wait -= get_process_delta_time()
		if _retry_wait > 0.0:
			return
		_retry_wait = 1.0
		_stream.disconnect_from_host()  # 注意：StreamPeerTCP 没有 reset()（4.6 实测）
		_stream.connect_to_host("127.0.0.1", _stream_port)
		_stream.poll()
		return
	if st != StreamPeerTCP.STATUS_CONNECTED:
		_stream.poll()
		return
	_stream.poll()
	var avail := _stream.get_available_bytes()
	if avail <= 0:
		return
	_buf.append_array(_stream.get_data(avail)[1])
	if _buf.size() > 2 * 1024 * 1024:
		_buf.clear()  # 严重失步兜底：丢缓冲重新同步
		_soi = -1
		_scan_pos = 0
	_extract_newest_frame()


func _extract_newest_frame() -> void:
	# 扫描 JPEG 边界：SOI=FFD8（帧开始）EOI=FFD9（帧结束）。
	# JPEG 熵编码段里的 FF 后必跟 00（字节填充），不会出现假边界。
	# 只保留缓冲里"最新"的完整帧，旧帧跳过（与在途≤1节流配套）。
	var newest: PackedByteArray = []
	while true:
		var ff: int = _buf.find(0xFF, _scan_pos)
		if ff < 0 or ff + 1 >= _buf.size():
			_scan_pos = maxi(_buf.size() - 1, 0)
			break
		var second: int = _buf[ff + 1]
		_scan_pos = ff + 1
		if second == 0xD8:
			if _soi < 0:
				_soi = ff
		elif second == 0xD9 and _soi >= 0:
			newest = _buf.slice(_soi, ff + 2)
			_soi = -1
	if newest.is_empty():
		return
	_buf = _buf.slice(maxi(_scan_pos - 1, 0))  # 已扫描部分裁掉，留未定论尾巴
	_scan_pos = 0
	var img := Image.new()
	if img.load_jpg_from_buffer(newest) != OK:
		return
	img.convert(Image.FORMAT_RGB8)
	tracker._inject_frame(img)


func stop() -> void:
	super.stop()
	_stream.disconnect_from_host()
