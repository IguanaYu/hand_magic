extends Node
## 远程识别后端：本机起 TCP+WebSocket 服务端，把摄像头帧（WebP）发给局域网里的
## 识别服务器（PC 上 tools/tracker_service.gd），收 JSON 关键点。
## 给 Pi 4 这类装不了 GDMP（glibc 过旧）的机器用；连接方向刻意反过来
## （游戏当服务端、识别机主动外连），避免在用户 PC 上开防火墙入站。
## Godot 4 的 WebSocketPeer 不能自己监听——按官方姿势用 TCPServer 接入后
## accept_stream() 升级成 WS 连接。单客户端模型：同一时刻只服务一个识别机。


var tracker  # HandTracker 基类回引

const MSG_FRAME := 1  # 包类型：视频帧（JPEG）

var _port := 9870
var _tcp := TCPServer.new()
var _client_stream: StreamPeerTCP
var _ws := WebSocketPeer.new()
var _listening := false
var _client_connected := false
var _frame_seq := 0
var _last_result_id := 0


func configure(args: Dictionary) -> void:
	_port = int(args.get("port", HandTracker.TRACKER_PORT))


func start() -> bool:
	var err: int = _tcp.listen(_port)
	if err != OK:
		tracker.tracker_message.emit("WS 服务端启动失败 port=%d err=%d" % [_port, err])
		return false
	_listening = true
	tracker.tracker_message.emit("等待识别服务连接: ws://%s:%d" % [_lan_ip(), _port])
	return true


func on_tracker_frame(image: Image, _ts_ms: int) -> bool:
	# 识别服务没连着就不消耗帧（不占在途名额，连上立刻恢复）
	if not _client_connected:
		return false
	_frame_seq += 1
	var pkt := PackedByteArray()
	pkt.resize(5)
	pkt[0] = MSG_FRAME
	pkt.encode_s32(1, _frame_seq)  # 小端 4 字节帧号
	# JPEG：实测 save_webp_to_buffer 在 4.6 返回空数组，只能用 jpg
	var jpg := image.save_jpg_to_buffer(0.8)
	if jpg.is_empty():
		return false
	pkt.append_array(jpg)
	_ws.put_packet(pkt)
	return true


func _process(_delta: float) -> void:
	if not _listening:
		return
	# 接待新连接（空闲时）
	if _client_stream == null and _tcp.is_connection_available():
		_client_stream = _tcp.take_connection()
		_ws = WebSocketPeer.new()
		_ws.accept_stream(_client_stream)
	if _client_stream == null:
		return
	_ws.poll()
	var state: int = _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _client_connected:
			_client_connected = true
			tracker.tracker_message.emit("识别服务已连接")
		while _ws.get_available_packet_count() > 0:
			_handle_packet(_ws.get_packet())
	elif state == WebSocketPeer.STATE_CLOSED:
		# 断开：丢弃流，回去等下一个客户端连入
		if _client_connected:
			_client_connected = false
			tracker.tracker_message.emit("识别服务断开，等待重连…")
		_client_stream = null
		_ws = WebSocketPeer.new()


func _handle_packet(pkt: PackedByteArray) -> void:
	var j = JSON.parse_string(pkt.get_string_from_utf8())
	if j == null or not j is Dictionary or not j.has("h"):
		return
	# 帧号单调递增保护：识别服务超时补发/迟到的旧包直接丢
	var rid := int(j.get("id", 0))
	if rid <= _last_result_id:
		return
	_last_result_id = rid
	var raw: Array = []
	for h in j["h"]:
		var flat: Array = h.get("p", [])
		var pts: Array[Vector2] = []
		for k in range(flat.size() / 2):
			pts.append(Vector2(float(flat[k * 2]), float(flat[k * 2 + 1])))
		if pts.size() >= 21:
			raw.append({"label": str(h.get("l", "Hand")), "points": pts})
	tracker._deliver_raw_hands(raw)


func _lan_ip() -> String:
	for addr in IP.get_local_addresses():
		var s := str(addr)
		if s.begins_with("192.168.") or s.begins_with("10.") or s.begins_with("172."):
			return s
	return "?"


func stop() -> void:
	_listening = false
	_ws.close()
	_tcp.stop()
