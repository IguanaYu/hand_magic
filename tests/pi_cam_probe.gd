extends SceneTree
## Pi 摄像头链路探针：验证 Godot CameraServer 层（Linux V4L2 后端）能否
## 枚举摄像头、激活 feed 并持续收到帧——即 hand_tracker.gd 在 MediaPipe
## 之前消费的同一条通路。
## 用法: libcamerify ./Godot_v4.6.1-stable_linux.arm64 --headless --path . -s tests/pi_cam_probe.gd
## 退出码: 0=收到帧  3=8秒内无feed或12秒内无帧

var _t0 := 0
var _frames := 0
var _first_frame_ms := -1
var _feed = null

func _initialize() -> void:
	CameraServer.monitoring_feeds = true
	_t0 = Time.get_ticks_msec()
	print("PROBE start monitoring_feeds=true")

func _process(_delta: float) -> bool:
	var ms := Time.get_ticks_msec() - _t0
	if _feed == null:
		if CameraServer.get_feed_count() > 0:
			_feed = CameraServer.get_feed(0)
			# Linux V4L2 后端要求：先 set_format 再激活，否则报
			# "CameraFeed format needs to be set before activating"
			var fmts = _feed.get_formats()
			var chosen := -1
			for i in range(fmts.size()):
				var fd: Dictionary = fmts[i]
				if int(fd.get("width", 0)) == 640 and int(fd.get("height", 0)) == 480:
					chosen = i
					break
			if chosen == -1 and fmts.size() > 0:
				chosen = 0
			if chosen >= 0:
				_feed.set_format(chosen, {})
			_feed.feed_is_active = true
			_feed.frame_changed.connect(_on_frame)
			print("PROBE feed name=", _feed.get_name(),
				" datatype=", _feed.get_datatype(),
				" position=", _feed.get_position(),
				" chosen=", chosen,
				" formats=", str(fmts).substr(0, 500))
		elif ms > 8000:
			print("PROBE RESULT verdict=FAIL no_feed=1 feeds=", CameraServer.get_feed_count())
			quit(3)
			return true
		return false
	if _first_frame_ms >= 0 and ms - _first_frame_ms > 10000:
		var span := float(ms - _first_frame_ms) / 1000.0
		print("PROBE RESULT verdict=", ("PASS" if _frames > 30 else "FAIL"),
			" frames=", _frames, " span_s=%.1f" % span,
			" fps=%.1f" % (_frames / span))
		quit(0 if _frames > 30 else 3)
		return true
	if _first_frame_ms < 0 and ms > 20000:
		print("PROBE RESULT verdict=FAIL frames=0 (feed 有了但从未收到帧)")
		quit(3)
		return true
	return false

func _on_frame() -> void:
	if _first_frame_ms < 0:
		_first_frame_ms = Time.get_ticks_msec() - _t0
	_frames += 1
