extends SceneTree
## 手势识别服务器（PC 端，无头运行）：主动连接游戏进程（Pi 或本机）的
## WebSocket 服务端，收 WebP 视频帧 → GDMP HandLandmarker 识别 → 回 JSON 关键点。
## 协议（与 scripts/hand_tracker_remote.gd 配对）：
##   上行(二进制): [1B 类型=1][4B 小端帧号][JPEG 图像]
##   下行(JSON):   {"id":帧号, "h":[{"l":"Left","p":[x0,y0,x1,y1,...]}], "ms":推理耗时}
##
## 运行示例（项目根目录，Windows 用 console 版可执行）：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . ^
##     -s tools/tracker_service.gd -- --url=ws://192.168.0.116:9870 --max-hands=1

const MODEL_PATH := "res://models/hand_landmarker.task"
const REPLY_TIMEOUT_MS := 1500  # 超过此时间没等到回调就补发空结果，防止游戏端在途卡死

var _url := "ws://192.168.0.116:9870"
var _max_hands := 1
var _task: MediaPipeHandLandmarker
var _ws := WebSocketPeer.new()
var _frame_id := 0
var _busy := false
var _busy_t0 := 0
var _last_ts := 0
var _frames_in := 0
var _frames_out := 0
var _reported_out := 0
var _report_t := 0.0
var _retry_wait := 0.0
var _was_open := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--url="):
			_url = arg.substr("--url=".length())
		elif arg.begins_with("--max-hands="):
			_max_hands = clampi(int(arg.substr("--max-hands=".length())), 1, 2)
	var file := FileAccess.open(MODEL_PATH, FileAccess.READ)
	if file == null:
		push_error("[service] 模型缺失: %s" % MODEL_PATH)
		quit(1)
		return
	var base_options := MediaPipeTaskBaseOptions.new()
	base_options.delegate = MediaPipeTaskBaseOptions.DELEGATE_CPU
	base_options.model_asset_buffer = file.get_buffer(file.get_length())
	_task = MediaPipeHandLandmarker.new()
	var ok: bool = _task.initialize(
		base_options, MediaPipeVisionTask.RUNNING_MODE_LIVE_STREAM,
		_max_hands, 0.5, 0.5, 0.5)
	if not ok:
		push_error("[service] HandLandmarker 初始化失败")
		quit(1)
		return
	_task.result_callback.connect(_on_result)
	print("[service] 模型就绪 max_hands=%d，目标 %s" % [_max_hands, _url])


func _process(delta: float) -> bool:
	_ws.poll()
	var state: int = _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			print("[service] 已连接 %s" % _url)
		# 只取排队中最新的帧，旧帧丢弃（跟游戏端"在途≤1"节流配套）
		if not _busy and _ws.get_available_packet_count() > 0:
			var pkt: PackedByteArray
			while _ws.get_available_packet_count() > 0:
				pkt = _ws.get_packet()
			if pkt.size() > 5:
				_process_frame(pkt)
			else:
				print("[service] 收到异常短包 %d 字节，忽略" % pkt.size())
	elif _was_open and state == WebSocketPeer.STATE_CLOSED:
		_was_open = false
		_busy = false
		print("[service] 连接断开，1 秒后重试…")
	elif state == WebSocketPeer.STATE_CLOSED:
		_retry_wait -= delta
		if _retry_wait <= 0.0:
			_retry_wait = 1.0
			_ws.close()
			if _ws.connect_to_url(_url) != OK:
				push_warning("[service] connect_to_url 失败")
	# 回调超时兜底：宁可回空结果也不能让游戏端的在途名额卡死
	if _busy and Time.get_ticks_msec() - _busy_t0 > REPLY_TIMEOUT_MS:
		print("[service] 识别回调超时，补发空结果 (frame %d)" % _frame_id)
		_reply([])
	_report(delta)
	return false


func _process_frame(pkt: PackedByteArray) -> void:
	_frames_in += 1
	_frame_id = pkt.decode_s32(1)
	var img := Image.new()
	if img.load_jpg_from_buffer(pkt.slice(5)) != OK:
		print("[service] JPEG 解码失败 (frame %d)，回空结果" % _frame_id)
		_reply([])
		return
	img.convert(Image.FORMAT_RGB8)
	_busy = true
	_busy_t0 = Time.get_ticks_msec()
	_last_ts += 33  # 任意严格递增即可，MediaPipe 只用它排序
	var mp_image := MediaPipeImage.new()
	mp_image.set_image(img)
	_task.detect_async(mp_image, _last_ts, Rect2(), 0)


## MediaPipe 在后台线程回调本函数——必须 call_deferred 回主线程再碰 WebSocket
func _on_result(result, _image, _timestamp_ms: int) -> void:
	_send_result.call_deferred(result)


func _send_result(result) -> void:
	if not _busy:
		return  # 已被超时兜底补发过，迟到结果丢弃（游戏端按帧号去重）
	var hands: Array = []
	if result != null:
		var all_landmarks = result.hand_landmarks
		var all_handedness = result.handedness
		for i in range(all_landmarks.size()):
			var lm_set = all_landmarks[i]
			var pts: Array = []
			for lm in lm_set.landmarks:
				pts.append(snappedf(lm.x, 0.0001))
				pts.append(snappedf(lm.y, 0.0001))
			if pts.size() < 42:
				continue
			var label := "Hand%d" % i
			if i < all_handedness.size():
				var cats = all_handedness[i].categories
				if cats.size() > 0:
					label = str(cats[0].category_name)
			hands.append({"l": label, "p": pts})
	_reply(hands)


func _reply(hands: Array) -> void:
	var infer_ms := Time.get_ticks_msec() - _busy_t0 if _busy else 0
	_busy = false
	_frames_out += 1
	var msg := JSON.stringify({
		"id": _frame_id,
		"h": hands,
		"ms": infer_ms,
	})
	_ws.put_packet(msg.to_utf8_buffer())


func _report(delta: float) -> void:
	_report_t += delta
	if _report_t < 5.0:
		return
	_report_t = 0.0
	var out_fps := float(_frames_out - _reported_out) / 5.0
	_reported_out = _frames_out
	print("[service] 收帧 %d / 回包 %d（近5秒 %.1f fps）%s" % [
		_frames_in, _frames_out, out_fps,
		"…识别中" if _busy else ""])
