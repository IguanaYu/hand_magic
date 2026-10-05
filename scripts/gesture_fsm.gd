class_name GestureFSM
extends Node
## 施法状态机（GDD §3.2）：
## IDLE →(拳×5帧)→ CHARGE →(食指伸出移动)→ DRAWING →(张掌)→ CAST/FIZZLE
## 任意状态：张掌保持 500ms → IDLE；画符超时 2.5s → FIZZLE；丢手 0.6s → IDLE。


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
var _pause_ms := 0.0
var _cooldown_left := 0.0


func reset() -> void:
	state = State.IDLE
	trajectory.clear()
	trajectory_start_ms = -1
	_palm_hold_ms = 0
	_no_hand_ms = 0.0
	_pause_ms = 0.0
	_cooldown_left = 0.0
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
			if pose == PoseClassifier.Pose.FIST:
				_enter_charge()
		State.CHARGE:
			if pose == PoseClassifier.Pose.DRAWING:
				_enter_drawing(index_tip)
			elif pose == PoseClassifier.Pose.PALM:
				_quick_shot()
		State.DRAWING:
			_update_drawing(pose, index_tip)
		State.COOLDOWN:
			_cooldown_left -= delta
			if _cooldown_left <= 0.0:
				if pose == PoseClassifier.Pose.FIST:
					_enter_charge()
				else:
					_go_idle()


func _enter_charge() -> void:
	state = State.CHARGE
	trajectory.clear()
	trajectory_start_ms = -1
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
	_pause_ms = 0.0
	drawing_updated.emit(_trajectory_public())
	state_changed.emit("DRAWING")


func _update_drawing(pose: int, index_tip: Vector2) -> void:
	var now := Time.get_ticks_msec()
	# 画符超时（GDD：轨迹窗口 2.5s）
	if trajectory_start_ms >= 0 and now - trajectory_start_ms > DRAW_TIMEOUT * 1000.0:
		_fizzle("符文超时消散")
		return

	if pose == PoseClassifier.Pose.DRAWING:
		_pause_ms = 0.0
		var last: Vector2 = trajectory[trajectory.size() - 1] if trajectory.size() > 0 else Vector2(INF, INF)
		# 采样间隔：距离 > 0.004 才记录，避免静止时堆点
		if (index_tip - last).length() > 0.004:
			# 瞬移保护：单帧跳变 >12% 画面必为姿势切换伪影（如张掌确认期指尖跳到掌心），
			# 真实画符动作不可能一帧挪 12% 屏幕
			if (index_tip - last).length() < 0.12:
				trajectory.append(index_tip)
				drawing_updated.emit(_trajectory_public())
	elif pose == PoseClassifier.Pose.PALM:
		_release()
	elif pose == PoseClassifier.Pose.FIST:
		# 拳 = 回到聚气，清空轨迹
		_fizzle("画符中断")
		_enter_charge()
	else:
		# NONE / 抖动：短暂容忍
		_pause_ms += get_process_delta_time()
		if _pause_ms > 0.35:
			_fizzle("手势丢失")


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
