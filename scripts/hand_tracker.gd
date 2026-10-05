class_name HandTracker
extends Node
## 摄像头 → GDMP HandLandmarker → 归一化关键点（GDD §10.2 数据流最上游）。
## 参考 GDMP 官方 demo 的 SubViewport 读回方案，统一兼容 RGB / YCbCr / 分离 YUV 摄像头格式。


signal hands_updated(hands: Array)
signal tracker_message(msg: String)

const MODEL_PATH := "res://models/hand_landmarker.task"
const MAX_HANDS := 2

var latency_ms := 0.0  # 摄像头帧事件 → 识别回调 的端到端延迟（EMA）
var flip_h := true  # 前置摄像头镜像显示（自拍视角）

# 诊断计数（--camera-test 用）
var frames_sent := 0
var results_received := 0
var hands_frames := 0

var _task: MediaPipeHandLandmarker
var _feed  # 注意：不能标注 CameraFeed 类型——CameraFeedExtension 上转型后 get_formats/set_format 失效（插件已知问题）
var _camera_extension  # Windows: CameraServerExtension（Media Foundation 后端）
var _cam_texture_rect: TextureRect
var _viewport: SubViewport
var _last_ts := 0
var _frame_t0 := 0
var _filters := {}  # hand_label -> {palm: OneEuroFilter, tip: OneEuroFilter}
var _mirror_warned := false


func setup(viewport: SubViewport, texture_rect: TextureRect) -> void:
	_viewport = viewport
	_cam_texture_rect = texture_rect
	_init_task()
	_start_camera()


func _init_task() -> void:
	var file := FileAccess.open(MODEL_PATH, FileAccess.READ)
	if file == null:
		tracker_message.emit("模型文件缺失: %s" % MODEL_PATH)
		return
	var base_options := MediaPipeTaskBaseOptions.new()
	base_options.delegate = MediaPipeTaskBaseOptions.DELEGATE_CPU  # Windows 不支持 GPU delegate
	base_options.model_asset_buffer = file.get_buffer(file.get_length())
	_task = MediaPipeHandLandmarker.new()
	# num_hands=2, 置信度 0.5（GDD §3.3 可调）
	var ok: bool = _task.initialize(
		base_options, MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM,
		MAX_HANDS, 0.5, 0.5, 0.5
	)
	if not ok:
		tracker_message.emit("HandLandmarker 初始化失败")
		_task = null
		return
	_task.result_callback.connect(_on_result)
	tracker_message.emit("HandLandmarker 就绪")


func _start_camera() -> void:
	CameraServer.camera_feed_added.connect(_on_feed_added)
	CameraServer.camera_feeds_updated.connect(_on_feeds_updated)
	CameraServer.monitoring_feeds = true
	_ensure_camera_extension()
	_try_use_first_feed()


func _on_feeds_updated() -> void:
	# 对应 GDMP demo 的时序：feeds 更新事件后才创建扩展实例
	_ensure_camera_extension()
	_try_use_first_feed()


func _ensure_camera_extension() -> void:
	if _camera_extension != null:
		return
	if OS.get_name() != "Windows" or not ClassDB.class_exists("CameraServerExtension"):
		return
	_camera_extension = CameraServerExtension.new()
	_camera_extension.permission_result.connect(_on_permission_result)
	if not _camera_extension.permission_granted():
		_camera_extension.request_permission()


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
	if _feed == null:
		_poll_t += delta
		if _poll_t > 0.5:
			_poll_t = 0.0
			_try_use_first_feed()


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
			_viewport.size = tex.get_size()
		CameraFeed.FEED_YCBCR:
			var tex := CameraTexture.new()
			tex.camera_feed_id = _feed.get_id()
			tex.which_feed = CameraServer.FEED_YCBCR_IMAGE
			var mat := ShaderMaterial.new()
			mat.shader = load("res://shaders/yuy2_to_rgb.gdshader")
			mat.set_shader_parameter("texture_yuy2", tex)
			_cam_texture_rect.material = mat
			_viewport.size = tex.get_size()
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
			_viewport.size = tex_y.get_size()
		_:
			if not _mirror_warned:
				_mirror_warned = true
				tracker_message.emit("未知摄像头数据格式: %d" % _feed.get_datatype())


func _on_frame_changed() -> void:
	if _viewport == null or _task == null:
		return
	_frame_t0 = Time.get_ticks_msec()
	await RenderingServer.frame_post_draw
	if _viewport == null:
		return
	var texture := _viewport.get_texture()
	if texture == null:
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		return
	image.convert(Image.FORMAT_RGB8)
	var ts := Time.get_ticks_msec()
	if ts <= _last_ts:
		ts = _last_ts + 1  # MediaPipe 要求时间戳严格递增
	_last_ts = ts
	var mp_image := MediaPipeImage.new()
	mp_image.set_image(image)
	_task.detect_async(mp_image, ts, Rect2(), 0)
	frames_sent += 1


func _on_result(result, _image, _timestamp_ms: int) -> void:
	results_received += 1
	latency_ms = 0.0 if latency_ms == 0.0 else latency_ms * 0.8 + (Time.get_ticks_msec() - _frame_t0) * 0.2
	var hands: Array = []
	if result == null:
		hands_updated.emit(hands)
		return
	var all_landmarks = result.hand_landmarks
	var all_handedness = result.handedness
	for i in range(all_landmarks.size()):
		var lm_set = all_landmarks[i]
		var lm_array: Array[Vector2] = []
		for lm in lm_set.landmarks:
			var x: float = lm.x
			if flip_h:
				x = 1.0 - x
			lm_array.append(Vector2(x, lm.y))
		if lm_array.size() < 21:
			continue
		var label := "Hand%d" % i
		if i < all_handedness.size():
			var cats = all_handedness[i].categories
			if cats.size() > 0:
				label = str(cats[0].category_name)
		hands.append(_make_hand(label, lm_array, Time.get_ticks_msec()))
	if hands.size() > 0:
		hands_frames += 1
	hands_updated.emit(hands)


func diagnostics() -> Dictionary:
	return {
		"camera": _feed.get_name() if _feed != null else "",
		"datatype": _feed.get_datatype() if _feed != null else -1,
		"frames_sent": frames_sent,
		"results_received": results_received,
		"hands_frames": hands_frames,
		"latency_ms": latency_ms,
	}


func _make_hand(label: String, lm: Array[Vector2], now_ms: int) -> Dictionary:
	if not _filters.has(label):
		_filters[label] = {
			"palm": OneEuroFilter.new(1.2, 0.05),
			"tip": OneEuroFilter.new(1.5, 0.08),
		}
	var f: Dictionary = _filters[label]
	# 掌心锚点 = 腕 + 三掌指关节均值（GDD §3.1 第③层）
	var palm_raw: Vector2 = (lm[0] + lm[5] + lm[9] + lm[17]) / 4.0
	return {
		"label": label,
		"points": lm,
		"palm": f.palm.filter(palm_raw, now_ms),
		"palm_raw": palm_raw,
		"index_tip": f.tip.filter(lm[8], now_ms),
	}


func _exit_tree() -> void:
	if _feed != null:
		_feed.feed_is_active = false
