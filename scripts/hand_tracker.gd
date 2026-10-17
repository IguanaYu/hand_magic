class_name HandTracker
extends Node
## 摄像头 → 识别器 → 归一化关键点（GDD §10.2 数据流最上游）。
## 统一兼容 RGB / YCbCr / 分离 YUV 摄像头格式（SubViewport 读回方案）。
##
## 识别后端三种（--tracker=local|remote|rpicam）：
##   local : GDMP HandLandmarker 本机推理（Windows 开发机）
##   remote: 本机起 WebSocket 服务端，把帧发给局域网识别服务器
##           （PC 上 tools/tracker_service.gd 无头跑 GDMP），回传关键点。
##   rpicam: 同 remote 的识别链路，但帧源改用 rpicam-vid 的本机 MJPEG TCP 流
##           （Linux 默认）。Pi 上 Godot 的 V4L2 摄像头后端颜色错乱，不能走
##           CameraFeed；rpicam 走 ISP 硬件管线色彩正确，PIP 与识别共用一帧。
## 默认：Windows=local，其他平台=rpicam。
## 基类不含任何 MediaPipe / CameraServerExtension 符号——Pi 上
## hand_tracker_local.gd 只要不被 load 就能正常解析（识别器一律运行时按需加载）。


signal hands_updated(hands: Array)
signal tracker_message(msg: String)

const MAX_HANDS := 2  # 默认；可用 --max-hands=N 覆盖（Pi 4 等弱机建议 1，游戏逻辑只消费第一只手）
const TRACKER_PORT := 9870  # remote 模式 WS 服务端端口（--tracker-port= 可覆盖）

var latency_ms := 0.0  # 摄像头帧事件 → 识别回调 的端到端延迟（EMA）
var flip_h := true  # 前置摄像头镜像显示（自拍视角）

# 诊断计数（--camera-test 用）
var frames_sent := 0
var frames_dropped := 0  # 上一帧还没识别完就到来的摄像头帧（弱机上主动丢弃，防止排队延迟膨胀）
var results_received := 0
var hands_frames := 0

var _feed  # 注意：不能标注 CameraFeed 类型——CameraFeedExtension 上转型后 get_formats/set_format 失效（插件已知问题）
var _camera_extension  # Windows: CameraServerExtension（Media Foundation 后端）；动态创建，Linux 无此类
var _cam_texture_rect: TextureRect
var _viewport: SubViewport
var _recognizer: Node  # duck-typed：configure/start/stop/on_tracker_frame
var _recognizer_mode := ""
var _recognizer_provides_frames := false  # true=识别器自己产帧(rpicam)，跳过 CameraFeed 链路
var _source_tex: ImageTexture  # rpicam 模式的动态帧纹理
var _frame_t0 := 0
var _filters := {}  # hand_label -> Array[OneEuroFilter]（21 点逐点）
var _mirror_warned := false
var _last_frame_ms := 0     # 最近一次摄像头帧事件时刻（停帧看门狗用）
var _stall_warned := false
var _stall_retried := false


func setup(viewport: SubViewport, texture_rect: TextureRect) -> void:
	_viewport = viewport
	_cam_texture_rect = texture_rect
	_init_recognizer()
	if not _recognizer_provides_frames:
		_start_camera()


# ---------- 帧源入口②：识别器产帧（rpicam）----------
# 与 _on_frame_changed（CameraFeed 路径）等价：节流 → 预览 → CAMPROBE → 交给识别器
func _inject_frame(image: Image) -> void:
	if _recognizer == null or image == null or image.is_empty():
		return
	_last_frame_ms = Time.get_ticks_msec()  # 帧事件时间戳（与 _on_frame_changed 同语义）
	if frames_sent - results_received >= 1:
		frames_dropped += 1
		return
	_frame_t0 = Time.get_ticks_msec()
	_display_source_frame(image)
	if frames_sent == 1 or frames_sent == 10 or frames_sent == 40:
		var px := image.get_pixelv(Vector2i(16, 16))
		print("CAMPROBE frame#%d img=%dx%d vp_size=%s px(16,16)=%s" % [
			frames_sent, image.get_width(), image.get_height(), _viewport.size, px])
	if _recognizer.on_tracker_frame(image, Time.get_ticks_msec()):
		frames_sent += 1


## 把识别器产出的帧显示到预览通道（经 SubViewport，main.gd 的 PIP 无需改动）
func _display_source_frame(image: Image) -> void:
	if _source_tex == null:
		_source_tex = ImageTexture.create_from_image(image)
		_cam_texture_rect.texture = _source_tex
		_cam_texture_rect.material = null
		_cam_texture_rect.flip_h = flip_h
		_viewport.size = Vector2i(image.get_width(), image.get_height())
	else:
		_source_tex.update(image)


# ---------- 识别器装配 ----------

func _init_recognizer() -> void:
	var args := {}
	var mode := "auto"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tracker="):
			mode = arg.substr("--tracker=".length())
		elif arg.begins_with("--max-hands="):
			var n := int(arg.substr("--max-hands=".length()))
			if n >= 1 and n <= MAX_HANDS:
				args["max_hands"] = n
		elif arg.begins_with("--tracker-port="):
			args["port"] = int(arg.substr("--tracker-port=".length()))
		elif arg.begins_with("--rpicam-port="):
			args["rpicam_port"] = int(arg.substr("--rpicam-port=".length()))
	if mode == "auto":
		mode = "local" if OS.get_name() == "Windows" else "rpicam"
	_recognizer_mode = mode
	var script_path: String = {
		"local": "res://scripts/hand_tracker_local.gd",
		"remote": "res://scripts/hand_tracker_remote.gd",
		"rpicam": "res://scripts/hand_tracker_rpicam.gd",
	}.get(mode, "")
	var script: GDScript = load(script_path) if script_path != "" else null
	if script == null:
		tracker_message.emit("识别器脚本缺失: %s" % script_path)
		return
	_recognizer = script.new()
	_recognizer.tracker = self
	_recognizer.configure(args)
	add_child(_recognizer)
	_recognizer_provides_frames = \
			_recognizer.has_method("provides_frames") and _recognizer.provides_frames()
	_recognizer.start()


# ---------- 识别结果统一入口 ----------
# 识别器交付 raw = [{label: String, points: Array[Vector2]（21 点，未镜像归一化坐标）}]
# 本地回调来自 MediaPipe 后台线程——由识别器负责 call_deferred；remote 在主线程直接调用。
func _deliver_raw_hands(raw_hands: Array) -> void:
	results_received += 1
	var dt := float(Time.get_ticks_msec() - _frame_t0)
	latency_ms = dt if latency_ms == 0.0 else latency_ms * 0.8 + dt * 0.2
	var hands: Array = []
	for h in raw_hands:
		var lm: Array[Vector2] = []
		for p in h.get("points", []):
			var x: float = p.x
			if flip_h:
				x = 1.0 - x
			lm.append(Vector2(x, p.y))
		if lm.size() < 21:
			continue
		hands.append(_make_hand(str(h.get("label", "Hand")), lm, Time.get_ticks_msec()))
	if hands.size() > 0:
		hands_frames += 1
	hands_updated.emit(hands)


# ---------- 摄像头链路（两后端共用） ----------

func _start_camera() -> void:
	CameraServer.camera_feed_added.connect(_on_feed_added)
	CameraServer.camera_feeds_updated.connect(_on_feeds_updated)
	CameraServer.monitoring_feeds = true
	_ensure_camera_extension()
	_try_use_first_feed()


func _ensure_camera_extension() -> void:
	if _camera_extension != null:
		return
	if OS.get_name() != "Windows" or not ClassDB.class_exists("CameraServerExtension"):
		return
	# 动态创建：Linux 上没有这个类，静态引用会让整份脚本解析失败
	_camera_extension = ClassDB.instantiate("CameraServerExtension")
	_camera_extension.permission_result.connect(_on_permission_result)
	if not _camera_extension.permission_granted():
		_camera_extension.request_permission()


func _on_feeds_updated() -> void:
	# 对应 GDMP demo 的时序：feeds 更新事件后才创建扩展实例
	_ensure_camera_extension()
	_try_use_first_feed()


func _try_use_first_feed() -> void:
	if _feed == null and CameraServer.get_feed_count() > 0:
		_use_feed(CameraServer.get_feed(0))


func _on_permission_result(granted: bool) -> void:
	if not granted:
		tracker_message.emit("摄像头权限被拒绝")
		return
	_try_use_first_feed()


# 轮询兜底：某些后端的 feed 注册不发出信号
var _poll_t := 0.0

func _process(delta: float) -> void:
	if _feed == null and not _recognizer_provides_frames:
		_poll_t += delta
		if _poll_t > 0.5:
			_poll_t = 0.0
			_try_use_first_feed()
		return
	# 看门狗①：在途结果回调丢失自愈——MediaPipe 偶发不给回调会让在途节流
	# 永久卡死（frames_sent-results_received 恒为 1，之后所有帧被丢弃，
	# 表现为手消失/无法施法）。超时视作丢失，恢复送帧；迟到的回调多计一次无害。
	var now := Time.get_ticks_msec()
	if frames_sent > results_received and _frame_t0 > 0 and now - _frame_t0 > 3000:
		tracker_message.emit("识别回调丢失，已自动恢复追踪")
		results_received = frames_sent
		_frame_t0 = now
	# 看门狗②：摄像头停帧——先提示；8 秒仍无帧则重激活 feed 一次（Media Foundation 偶发）
	# 仅 CameraFeed 路径（rpicam 帧源无 feed 对象；停帧由 TCP 读侧暴露）
	if _feed != null and _feed.feed_is_active and frames_sent > 0 and _last_frame_ms > 0 and now - _last_frame_ms > 3000:
		if not _stall_warned:
			_stall_warned = true
			tracker_message.emit("摄像头停止出帧，尝试恢复…")
		if now - _last_frame_ms > 8000 and not _stall_retried:
			_stall_retried = true
			_feed.feed_is_active = false
			_feed.feed_is_active = true


func _on_feed_added(_id: int) -> void:
	if _feed == null and CameraServer.get_feed_count() > 0:
		_use_feed(CameraServer.get_feed(0))


func _use_feed(feed) -> void:
	_feed = feed
	# 优先 640x480@30（GDD §10.1：识别精度与带宽平衡）
	var chosen := -1
	var formats = feed.get_formats()
	for i in range(formats.size()):
		var f: Dictionary = formats[i]
		if int(f.get("width", 0)) == 640 and int(f.get("height", 0)) == 480:
			chosen = i
			break
	if chosen == -1 and formats.size() > 0:
		chosen = 0
	if chosen >= 0:
		feed.set_format(chosen, {})
	feed.frame_changed.connect(_on_frame_changed, ConnectFlags.CONNECT_DEFERRED)
	feed.feed_is_active = true
	flip_h = feed.get_position() == CameraFeed.FEED_FRONT
	_setup_camera_texture()
	tracker_message.emit("摄像头: %s" % feed.get_name())


func _setup_camera_texture() -> void:
	match _feed.get_datatype():
		CameraFeed.FEED_RGB:
			var tex := CameraTexture.new()
			tex.camera_feed_id = _feed.get_id()
			tex.which_feed = CameraServer.FEED_RGBA_IMAGE
			_cam_texture_rect.texture = tex
			_cam_texture_rect.material = null
			_fit_viewport(tex)
		CameraFeed.FEED_YCBCR:
			var tex := CameraTexture.new()
			tex.camera_feed_id = _feed.get_id()
			tex.which_feed = CameraServer.FEED_YCBCR_IMAGE
			var mat := ShaderMaterial.new()
			mat.shader = load("res://shaders/yuy2_to_rgb.gdshader")
			mat.set_shader_parameter("texture_yuy2", tex)
			_cam_texture_rect.material = mat
			_fit_viewport(tex)
		CameraFeed.FEED_YCBCR_SEP:
			var tex_y := CameraTexture.new()
			tex_y.camera_feed_id = _feed.get_id()
			tex_y.which_feed = CameraServer.FEED_Y_IMAGE
			var tex_uv := CameraTexture.new()
			tex_uv.camera_feed_id = _feed.get_id()
			tex_uv.which_feed = CameraServer.FEED_CBCR_IMAGE
			var mat := ShaderMaterial.new()
			mat.shader = load("res://shaders/yuv420_to_rgb.gdshader")
			mat.set_shader_parameter("texture_y", tex_y)
			mat.set_shader_parameter("texture_uv", tex_uv)
			_cam_texture_rect.material = mat
			_fit_viewport(tex_y)
		_:
			if not _mirror_warned:
				_mirror_warned = true
				tracker_message.emit("未知摄像头数据格式: %d" % _feed.get_datatype())


## CameraTexture.get_size() 在部分后端返回 (2,2)/(0,0) 占位值——退化时回退采集默认尺寸
func _fit_viewport(tex: CameraTexture) -> void:
	var s: Vector2 = tex.get_size()
	if s.x < 32.0 or s.y < 32.0:
		s = Vector2(640, 480)
	_viewport.size = Vector2i(int(s.x), int(s.y))


func _on_frame_changed() -> void:
	_last_frame_ms = Time.get_ticks_msec()  # 帧事件时间戳（停帧看门狗基准）
	if _viewport == null or _recognizer == null:
		return
	# 在途节流：最多 1 帧识别在跑（快机上无感，弱机上把排队延迟钉在单次识别时长内）
	if frames_sent - results_received >= 1:
		frames_dropped += 1
		return
	_frame_t0 = Time.get_ticks_msec()
	await RenderingServer.frame_post_draw
	if _viewport == null or _recognizer == null:
		return
	var texture := _viewport.get_texture()
	if texture == null:
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		return
	image.convert(Image.FORMAT_RGB8)
	if frames_sent == 1 or frames_sent == 10 or frames_sent == 40:
		var px := image.get_pixelv(Vector2i(16, 16))
		print("CAMPROBE frame#%d img=%dx%d vp_size=%s px(16,16)=%s" % [
			frames_sent, image.get_width(), image.get_height(), _viewport.size, px])
	if _recognizer.on_tracker_frame(image, Time.get_ticks_msec()):
		frames_sent += 1


func diagnostics() -> Dictionary:
	return {
		"camera": _feed.get_name() if _feed != null else ("rpicam(MJPEG)" if _recognizer_provides_frames else ""),
		"datatype": _feed.get_datatype() if _feed != null else (-2 if _recognizer_provides_frames else -1),
		"tracker": _recognizer_mode,
		"frames_sent": frames_sent,
		"frames_dropped": frames_dropped,
		"results_received": results_received,
		"hands_frames": hands_frames,
		"latency_ms": latency_ms,
	}


func _make_hand(label: String, lm: Array[Vector2], now_ms: int) -> Dictionary:
	if not _filters.has(label):
		var fs: Array = []
		for i in range(21):
			fs.append(OneEuroFilter.new(1.5, 0.08))
		_filters[label] = fs
	var fs: Array = _filters[label]
	# 全 21 点逐点 One Euro 平滑：分类与渲染统一吃平滑数据
	# （原始坐标的帧间抖动是姿势误判的主源，只滤 2 个点不够）
	var pts: Array[Vector2] = []
	for i in range(lm.size()):
		if i < fs.size():
			pts.append(fs[i].filter(lm[i], now_ms))
		else:
			pts.append(lm[i])
	# 掌心锚点 = 腕 + 三掌指关节均值（GDD §3.1 第③层），同样取平滑后
	return {
		"label": label,
		"points": pts,
		"points_raw": lm,
		"palm": (pts[0] + pts[5] + pts[9] + pts[17]) / 4.0,
		"palm_raw": (lm[0] + lm[5] + lm[9] + lm[17]) / 4.0,
		"index_tip": pts[8],
	}


func _exit_tree() -> void:
	if _recognizer != null:
		_recognizer.stop()
		_recognizer.queue_free()
	if _feed != null:
		_feed.feed_is_active = false
