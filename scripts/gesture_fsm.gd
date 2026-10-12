class_name GestureFSM
extends Node
## 施法状态机（GDD §3.2）：
## IDLE →(食指伸出/握拳×5帧)→ CHARGE →(指尖动起来)→ DRAWING →(握拳确认/停笔兜底/张掌)→ CAST/FIZZLE
## 任意状态：张掌保持 500ms → IDLE；画符超时 2.5s → 视为收笔直接识别；丢手 0.6s → IDLE。
## 画符中对姿势抖动宽容：短暂握拳（<FIST_CONFIRM_S）当伪影忽略，无姿势掉线不中断画符。
## 收笔主路径=握拳确认（姿势信号经全点平滑+多数表决+滞回后可靠），
## 兜底=速度判定（不握拳直接画完停住也能出招）：速度掉到本次画符峰值 25% 以下
## 并保持 STROKE_STOP_MS 即判定收笔，绝对低速兜底低于正常挥动一个数量级。


signal state_changed(state_name: String)
signal charge_started
signal drawing_updated(points: Array)
signal cast_performed(spell_id: String, anchor: Vector2, score: float)
signal fizzle(reason: String)
signal mana_changed(mana: float)
signal quick_shot_performed(anchor: Vector2)

enum State { IDLE, CHARGE, DRAWING, COOLDOWN }

const RUNE_TO_SPELL := {
	"circle": "fireball",
	"zigzag": "lightning",
	"triangle": "ice_field",
	"slash": "wind_blade",
}
const SPELL_COST := {
	"fireball": 25.0,
	"lightning": 12.0,
	"ice_field": 20.0,
	"wind_blade": 5.0,
}
const SPELL_NAME := {
	"fireball": "火球术",
	"lightning": "链电术",
	"ice_field": "冰霜领域",
	"wind_blade": "风刃",
}
const COOLDOWN_TIME := 0.8
const QUICK_COST := 8.0   # 掌心火弹法力（M0.5 快速施法）
const QUICK_COOLDOWN := 0.5
const DRAW_TIMEOUT := 2.5
const FIST_CONFIRM_S := 0.12    # 画符中握拳保持此时长 = 确认收笔施放（主路径）
const STROKE_START_SPEED := 0.2    # 起笔：指尖速度（归一化/秒）超过即开始画符
const STROKE_START_DISP := 0.015   # 起笔兜底：测速窗内位移超过即开始（慢速小幅也认）
const STROKE_STOP_S := 0.30        # 收笔：低速保持时长（秒）
const STROKE_STOP_FRACTION := 0.25 # 收笔：速度低于峰值速度此比例
const STROKE_STOP_SPEED := 0.12    # 收笔绝对兜底：正常挥动 0.5~2.0/s，手抖远低于此
const SPEED_WINDOW_MS := 150       # 指尖测速滑窗
const CAST_THRESHOLD := 0.80
const AMBIGUOUS_THRESHOLD := 0.70
const MANA_MAX := 100.0
const MANA_REGEN_CHARGE := 8.0
const MANA_REGEN_IDLE := 2.0

var state: int = State.IDLE
var mana := MANA_MAX
var trajectory: Array[Vector2] = []  # 归一化坐标（已镜像）
var trajectory_start_ms := -1
var recognizer := DollarRecognizer.new()
var last_result: Dictionary = {}
var last_fizzle_reason := ""
var last_trajectory: Array = []  # 最近一次 release/fizzle 的轨迹快照（调试/测试用）
var cast_trajectory: Array = []  # 最近一次成功施放的轨迹快照（调试/测试用）
var cast_count := 0
var fizzle_count := 0
var current_anchor := Vector2(0.5, 0.5)  # 掌心锚点，施放位置（GDD §3.1 第③层）

var _palm_hold_ms := 0
var _no_hand_ms := 0.0
var _fist_ms := 0.0
var _cooldown_left := 0.0
var _samples: Array = []      # 指尖测速滑窗 [t_ms, Vector2]
var _stop_ms := 0.0
var _peak_speed := 0.0        # 本次画符的峰值指尖速度（收笔按比例判定）
var _charge_by_fist := false  # 经握拳进入聚气（掌心火弹仍走拳→掌老路径）


func reset() -> void:
	state = State.IDLE
	trajectory.clear()
	trajectory_start_ms = -1
	_palm_hold_ms = 0
	_no_hand_ms = 0.0
	_fist_ms = 0.0
	_cooldown_left = 0.0
	_samples.clear()
	_stop_ms = 0.0
	_peak_speed = 0.0
	state_changed.emit("IDLE")


## 每帧驱动。pose: PoseClassifier.Pose；hand_present: 是否检测到手；
## index_tip / anchor: 归一化坐标（已镜像、已平滑）
func update(pose: int, hand_present: bool, index_tip: Vector2, anchor: Vector2, delta: float) -> void:
	current_anchor = anchor
	if not hand_present:
		_no_hand_ms += delta
		if _no_hand_ms > 0.6 and state != State.IDLE:
			reset()
	else:
		_no_hand_ms = 0.0

	# 法力回复（GDD §4.4：聚气状态 8/s，其余 2/s）
	var regen := MANA_REGEN_IDLE if state != State.CHARGE else MANA_REGEN_CHARGE
	mana = minf(MANA_MAX, mana + regen * delta)
	mana_changed.emit(mana)

	# 张掌保持 500ms = 取消（GDD CANCEL 路径；DRAWING 中张掌立即触发施放，不走这里）
	if pose == PoseClassifier.Pose.PALM and state != State.DRAWING:
		_palm_hold_ms += int(delta * 1000.0)
		if _palm_hold_ms >= 500 and state != State.IDLE:
			_go_idle()
			_palm_hold_ms = 0
			return
	else:
		_palm_hold_ms = 0

	match state:
		State.IDLE:
			if pose == PoseClassifier.Pose.DRAWING:
				_enter_charge(false)
			elif pose == PoseClassifier.Pose.FIST:
				_enter_charge(true)
		State.CHARGE:
			if pose == PoseClassifier.Pose.DRAWING:
				_push_tip(index_tip)
				# 指尖动起来即开始画符：速度快或滑窗内位移大都算起笔
				if _tip_speed() > STROKE_START_SPEED or _window_disp() > STROKE_START_DISP:
					_enter_drawing(index_tip)
			elif pose == PoseClassifier.Pose.PALM and _charge_by_fist:
				_quick_shot()
			else:
				_samples.clear()
		State.DRAWING:
			_update_drawing(pose, index_tip)
		State.COOLDOWN:
			_cooldown_left -= delta
			if _cooldown_left <= 0.0:
				if pose == PoseClassifier.Pose.FIST:
					_enter_charge(true)
				else:
					_go_idle()


func _enter_charge(by_fist: bool) -> void:
	state = State.CHARGE
	_charge_by_fist = by_fist
	trajectory.clear()
	trajectory_start_ms = -1
	_samples.clear()
	_stop_ms = 0.0
	charge_started.emit()
	state_changed.emit("CHARGE")


## 快速施法（M0.5）：聚气中直接张掌 = 掌心火弹（不画符的快速攻击路径）
func _quick_shot() -> void:
	if mana < QUICK_COST:
		_fizzle("法力不足")
		return
	mana -= QUICK_COST
	mana_changed.emit(mana)
	quick_shot_performed.emit(current_anchor)
	state = State.COOLDOWN
	_cooldown_left = QUICK_COOLDOWN
	trajectory.clear()
	trajectory_start_ms = -1
	state_changed.emit("COOLDOWN")


func _enter_drawing(p: Vector2) -> void:
	state = State.DRAWING
	trajectory.clear()
	trajectory.append(p)
	trajectory_start_ms = Time.get_ticks_msec()
	_fist_ms = 0.0
	_stop_ms = 0.0
	_peak_speed = _tip_speed()
	drawing_updated.emit(_trajectory_public())
	state_changed.emit("DRAWING")


func _update_drawing(pose: int, index_tip: Vector2) -> void:
	var now := Time.get_ticks_msec()
	# 画符超时（GDD：轨迹窗口 2.5s）——超时视为收笔，直接拿现有轨迹进识别
	if trajectory_start_ms >= 0 and now - trajectory_start_ms > DRAW_TIMEOUT * 1000.0:
		_release()
		return

	if pose == PoseClassifier.Pose.PALM:
		_release()
		return
	if pose == PoseClassifier.Pose.FIST:
		# 握拳 = 确认收笔（主路径）：保持 FIST_CONFIRM_S 即拿现有轨迹识别施放。
		# 零星误判帧在多数表决处已被滤掉，到不了这里；轨迹太短时 _release 内有兜底
		_fist_ms += get_process_delta_time()
		if _fist_ms > FIST_CONFIRM_S:
			_release()
		return
	# DRAWING / NONE 都持续采样——画符姿势在大幅挥动中极易掉线（比值特征
	# 随手朝向翻转），掉线帧里手仍在镜头中，指尖位置依然可信
	_fist_ms = 0.0
	_push_tip(index_tip)
	var speed := _tip_speed()
	# 峰值速度随帧轻微衰减：匀速画时峰值≈当前速度，真减速时阈值随衰减下压，
	# 收笔判定不会拖太久
	_peak_speed = maxf(_peak_speed * pow(0.98, get_process_delta_time() * 60.0), speed)
	var last: Vector2 = trajectory[trajectory.size() - 1] if trajectory.size() > 0 else Vector2(INF, INF)
	# 采样间隔：距离 > 0.004 才记录，避免静止时堆点
	if (index_tip - last).length() > 0.004:
		# 瞬移保护：单帧跳变 >12% 画面必为姿势切换伪影（如张掌确认期指尖跳到掌心），
		# 真实画符动作不可能一帧挪 12% 屏幕
		if (index_tip - last).length() < 0.12:
			trajectory.append(index_tip)
			drawing_updated.emit(_trajectory_public())
	# 收笔：不要求完全停住（人手必抖），速度掉到本次画符峰值的 1/4 以下
	# 并保持 STROKE_STOP_S 即收笔；绝对兜底远低于正常挥动速度
	if trajectory.size() >= 8 and speed < maxf(STROKE_STOP_SPEED, _peak_speed * STROKE_STOP_FRACTION):
		_stop_ms += get_process_delta_time()
		if _stop_ms >= STROKE_STOP_S:
			_release()
	else:
		_stop_ms = 0.0


## 指尖测速滑窗：先裁剪到最近 SPEED_WINDOW_MS，位移过小不记（滤滤波残余抖动）
func _push_tip(tip: Vector2) -> void:
	var now := Time.get_ticks_msec()
	while _samples.size() > 0 and now - int(_samples[0][0]) > SPEED_WINDOW_MS:
		_samples.pop_front()
	if _samples.size() > 0 and (tip - _samples[_samples.size() - 1][1]).length() < 0.002:
		return
	_samples.append([now, tip])


func _tip_speed() -> float:
	if _samples.size() < 2:
		return 0.0
	var dt := maxf(1.0, float(_samples[_samples.size() - 1][0] - _samples[0][0]))
	var dist := float((_samples[_samples.size() - 1][1] - _samples[0][1]).length())
	return dist / (dt / 1000.0)


func _window_disp() -> float:
	if _samples.size() < 2:
		return 0.0
	return float((_samples[_samples.size() - 1][1] - _samples[0][1]).length())


func _release() -> void:
	if trajectory.size() < 8:
		_fizzle("符文不完整")
		return
	last_result = recognizer.recognize(trajectory)
	if last_result.name.is_empty():
		_fizzle(last_result.get("reason", "无法识别符文"))
		return
	if last_result.score < AMBIGUOUS_THRESHOLD:
		_fizzle("符文模糊（%.2f）" % last_result.score)
		return
	if last_result.score < CAST_THRESHOLD:
		# 模糊区间：宽容施放但记一笔（GDD §3.4 模糊提示）
		pass
	var spell_id: String = RUNE_TO_SPELL.get(str(last_result.name), "")
	if spell_id.is_empty():
		_fizzle("未知符文")
		return
	var cost: float = SPELL_COST[spell_id]
	if mana < cost:
		_fizzle("法力不足")
		return
	mana -= cost
	mana_changed.emit(mana)
	cast_count += 1
	last_trajectory = trajectory.duplicate()
	cast_trajectory = trajectory.duplicate()
	cast_performed.emit(spell_id, current_anchor, last_result.score)
	state = State.COOLDOWN
	_cooldown_left = COOLDOWN_TIME
	trajectory.clear()
	state_changed.emit("COOLDOWN")


func _fizzle(reason: String) -> void:
	fizzle_count += 1
	last_fizzle_reason = reason
	last_trajectory = trajectory.duplicate()
	trajectory.clear()
	trajectory_start_ms = -1
	fizzle.emit(reason)
	state = State.COOLDOWN
	_cooldown_left = 0.3  # 失败惩罚极短，鼓励立刻重试（GDD §3.2 宽容设计）
	state_changed.emit("FIZZLE→COOLDOWN")


func _go_idle() -> void:
	trajectory.clear()
	trajectory_start_ms = -1
	state = State.IDLE
	state_changed.emit("IDLE")


func _trajectory_public() -> Array:
	var out: Array = []
	for p in trajectory:
		out.append(p)
	return out


func state_name() -> String:
	match state:
		State.CHARGE: return "聚气"
		State.DRAWING: return "画符"
		State.COOLDOWN: return "冷却"
		_: return "待机"
