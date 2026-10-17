extends Node
## 本地识别后端：GDMP HandLandmarker 本机推理（Windows 开发机）。
## 本文件含 MediaPipe 符号——只能由 HandTracker 在 local 模式下运行时 load()，
## 任何脚本都不要静态引用它，否则 Linux（无 GDMP）上会连锁解析失败。


var tracker  # HandTracker 基类回引；不标类型，避免循环依赖

const MODEL_PATH := "res://models/hand_landmarker.task"

var _task: MediaPipeHandLandmarker
var _max_hands := 2
var _last_ts := 0


func configure(args: Dictionary) -> void:
	_max_hands = int(args.get("max_hands", 2))


func start() -> bool:
	var file := FileAccess.open(MODEL_PATH, FileAccess.READ)
	if file == null:
		tracker.tracker_message.emit("模型文件缺失: %s" % MODEL_PATH)
		return false
	var base_options := MediaPipeTaskBaseOptions.new()
	base_options.delegate = MediaPipeTaskBaseOptions.DELEGATE_CPU  # Windows 不支持 GPU delegate
	base_options.model_asset_buffer = file.get_buffer(file.get_length())
	_task = MediaPipeHandLandmarker.new()
	# num_hands（GDD §3.3 可调，Pi 4 建议 --max-hands=1）, 置信度 0.5
	var ok: bool = _task.initialize(
		base_options, MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM,
		_max_hands, 0.5, 0.5, 0.5)
	if not ok:
		tracker.tracker_message.emit("HandLandmarker 初始化失败")
		_task = null
		return false
	_task.result_callback.connect(_on_result)
	tracker.tracker_message.emit("HandLandmarker 就绪（本机推理）")
	return true


func on_tracker_frame(image: Image, ts_ms: int) -> bool:
	if _task == null:
		return false
	var ts := ts_ms
	if ts <= _last_ts:
		ts = _last_ts + 1  # MediaPipe 要求时间戳严格递增
	_last_ts = ts
	var mp_image := MediaPipeImage.new()
	mp_image.set_image(image)
	_task.detect_async(mp_image, ts, Rect2(), 0)
	return true


## MediaPipe 在后台线程回调本函数——跨线程只能 call_deferred 回主线程
func _on_result(result, _image, _timestamp_ms: int) -> void:
	var raw: Array = []
	if result != null:
		var all_landmarks = result.hand_landmarks
		var all_handedness = result.handedness
		for i in range(all_landmarks.size()):
			var lm_set = all_landmarks[i]
			var pts: Array[Vector2] = []
			for lm in lm_set.landmarks:
				pts.append(Vector2(lm.x, lm.y))
			if pts.size() < 21:
				continue
			var label := "Hand%d" % i
			if i < all_handedness.size():
				var cats = all_handedness[i].categories
				if cats.size() > 0:
					label = str(cats[0].category_name)
			raw.append({"label": label, "points": pts})
	tracker._deliver_raw_hands.call_deferred(raw)


func stop() -> void:
	# GDMP 任务无显式 close，置空交给引用回收
	_task = null
