class_name GestureFSM
extends Node
## 施法状态机（GDD §3.2）：
## IDLE ──捏合(拇指尖碰食指尖)──▶ DRAWING ──松开捏合0.12s/张掌/超时2.5s──▶ CAST/FIZZLE → COOLDOWN
## IDLE/COOLDOWN ──握拳──▶ CHARGE(仅剩掌心火弹路径) ──张掌──▶ quick_shot
## 捏合=落笔的显式声明（Vision Pro/Quest 空中绘画的行业标准方案）：旧"指尖动起来就起笔"
## 的速度阈值对放松手完全不设防，误起笔频发；起笔权交还玩家后误触发在结构上消失。
## 松开=抬笔：画符中非捏合持续 PINCH_RELEASE_CONFIRM_S 才收笔，短暂松劲闪断被吞掉且
## 不采样（松开瞬间食指卷动会污染轨迹尾部）；张掌保留为立即收笔；握拳也走松开确认
## ——旧的握拳收笔肌肉记忆仍然可用。
## 起笔预滚：捏合检测有去抖滞后（5/7 帧表决），玩家捏上的瞬间手就开始动，
## IDLE/CHARGE 期间滚动缓存最近 PREROLL_MS 的食指尖，起笔时先播种进轨迹防切头。
## 采样以原始姿势为准：稳定姿势离开捏合要攒 3 票（~100ms），握拳收笔时卷动的
## 指尖会在滞后期被持续采样，给符文拖出向下一笔——原始姿势一旦离开捏合（防拳
## guard 的食指比值最先失效）即刻停采。
## latch：施放/失败后仍捏着不松不自动重画，松开一次后恢复（起笔只认上升沿）；
## 带 PINCH_LATCH_S 自愈过期——识别若卡死在'捏合'（真机事故：稳定姿势冻结 24s），
## 封锁最多持续 2s，之后恢复可见行为（轨迹/超时施放）而非永久静默。
## 再装填（break-before-make）：收笔后必须先观察到拇指食指明确分开（原始捏距
## 连续超退出阈值 PINCH_REARM_S）才允许下一次捏合起笔。拳→张掌的展开过程会路过
## "距离小+食指伸出"的假捏合窗口（表决误判 PINCH → 误起笔），而拳内距离从未拉开
## → 再装填不满足 → 假捏合被拦截；完全张开后重新装填，正常节奏无感（冷却期内
## 张掌的手早已完成装填）。
## 任意状态：张掌保持 500ms → IDLE；丢手 0.6s → IDLE。


signal state_changed(state_name: String)
signal charge_started
signal drawing_updated(points: Array)
signal cast_performed(spell_id: String, anchor: Vector2, score: float)
signal fizzle(reason: String)
signal mana_changed(mana: float)
signal quick_shot_performed(anchor: Vector2)

enum State { IDLE, CHARGE, DRAWING, COOLDOWN }

## 扩展手势总开关（2026-10 调研落地，docs/research-gesture-survey-2026-10.md）。
## 打开后两件事生效：
## ① PoseClassifier 开始识别三个新静态手形：比耶 VICTORY / 点赞 THUMB_UP / 我爱你
##    ILOVEYOU（main._ready 把本开关同步给分类器的 extended_poses；FSM 本身不消费
##    这些姿势，照旧当 NONE——游戏性绑定留到启用阶段再设计）。
## ② S 波 wave 符文替换三角成为冰霜领域唯一符文（启用即替换语义，调研方案 A）：
##    识别器先移除全部三角模板（含玩家录制）再注册 wave；RUNE_TO_SPELL 里的
##    triangle 条目从 effective_rune_map 剔除，符文样本存取（RuneSamples.rune_of）
##    也随之把 ice_field 反查成 wave。注意：玩家旧录的三角样本按 spell_id 存档，
##    启用后会以 wave 名注入但形状是三角，只会拉低识别分（fizzle）不会误施放，
##    启用前建议清一次冰霜样本。
## 正式版启用时改 true（或运行期直接赋值）；默认 false = 现役行为零变化。
## 做成 static var 而非 const：单测需要临时翻转以覆盖扩展路径，测完还原。
static var extended_gestures := false

const RUNE_TO_SPELL := {
	"circle": "fireball",
	"zigzag": "lightning",
	"triangle": "ice_field",
	"slash": "wind_blade",
}


## 当前生效的符文映射：默认返回 RUNE_TO_SPELL 原表；扩展开启时 wave 替换 triangle。
## 符文样本存取、录制面板等所有"spell_id ↔ 符文名"逻辑都应走这里而非直查常量表。
static func effective_rune_map() -> Dictionary:
	if not extended_gestures:
		return RUNE_TO_SPELL
	var out := RUNE_TO_SPELL.duplicate()
	out.erase("triangle")
	out["wave"] = "ice_field"
	return out
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
const PINCH_RELEASE_CONFIRM_S := 0.12  # 画符中松开捏合持续此时长 = 确认收笔施放
const PINCH_REARM_S := 0.10            # 起笔再装填：收笔后拇指食指明确分开（原始捏距
                                       # >退出阈值）持续此时长，才允许下一次捏合起笔
const PREROLL_MS := 200                # 起笔预滚缓冲：补偿姿势去抖（5/7 帧表决）的检测滞后
const PINCH_LATCH_S := 2.0             # latch 自愈过期：覆盖冷却 0.8s 后仍不误触发，且识别
                                       # 卡死在'捏合'时封锁最多 2s（静默不可接受）
const SAMPLE_MIN_DIST := 0.004         # 采样最小间距：滤静止堆点
const SAMPLE_TELEPORT := 0.12          # 单帧跳变超过此值必为姿势切换伪影，丢弃
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
var current_anchor := Vector2(0.5, 0.5)  # 掌心锚点：掌心火弹出手位置；画符施放改用 _rune_center()

var _palm_hold_ms := 0
var _no_hand_ms := 0.0
var _cooldown_left := 0.0
var _preroll: Array = []      # 起笔预滚环 [t_ms, Vector2]（非 DRAWING 且有手时滚动记录食指尖）
var _open_ms := 0.0           # 画符中非捏合（松开）持续时长
var _draw_time := 0.0         # 本次画符累计时长（超时用；累积 delta 而非墙钟，测试可快进）
var _pinch_latch := false     # 施放后仍捏着不松 → 不自动重画
var _latch_t := 0.0           # latch 已持续时长（自愈过期用）
var _pinch_armed := true      # 起笔再装填锁存：收笔后须先明确分开拇指食指才回 true。
                              # 必须锁存：装填若随实时捏距清零，捏合期间计时永远归零
                              # → 起笔被永久封锁；只在下一次收笔时卸下
var _sep_ms := 0.0            # 未装填时拇指食指分开（原始捏距>退出阈值）累计时长
var _rune_map: Dictionary = effective_rune_map()  # 施放查表用；随扩展开关联动 wave/triangle
var loadout: SpellLoadout = null  # 玩家装备配置（main 注入）；null = 全装备（旧测试/调用方兼容）


func _init() -> void:
	if extended_gestures:
		recognizer.register_extended_runes()


func reset() -> void:
	state = State.IDLE
	trajectory.clear()
	trajectory_start_ms = -1
	_palm_hold_ms = 0
	_no_hand_ms = 0.0
	_cooldown_left = 0.0
	_preroll.clear()
	_open_ms = 0.0
	_draw_time = 0.0
	_pinch_latch = false
	_latch_t = 0.0
	_pinch_armed = true  # 重置=丢手/张掌取消，手必然分开过，直接装填
	_sep_ms = 0.0
	state_changed.emit("IDLE")


## 每帧驱动。pose: PoseClassifier.Pose；hand_present: 是否检测到手；
## index_tip / anchor: 归一化坐标（已镜像、已平滑）
## raw_pose / raw_pinch_dist: 同帧分类器的原始判定与捏距（可选，缺省 -1/-1.0 =
## 调用方无手部数据，采样与再装填退回旧行为——鼠标兜底/旧测试即此路径）
func update(pose: int, hand_present: bool, index_tip: Vector2, anchor: Vector2, delta: float, raw_pose := -1, raw_pinch_dist := -1.0) -> void:
	current_anchor = anchor
	if not hand_present:
		_no_hand_ms += delta
		if _no_hand_ms > 0.6 and state != State.IDLE:
			reset()
	else:
		_no_hand_ms = 0.0
		# 预滚：非画符状态滚动缓存食指尖，起笔播种用（画符中不需要）
		if state != State.DRAWING:
			_push_preroll(index_tip)
	# 再装填（break-before-make）：收笔卸下装填，观察到拇指食指明确分开（原始捏距
	# 连续超退出阈值 PINCH_REARM_S）后重新装填。拳→张掌的展开过程会路过"距离小+
	# 食指伸出"的假捏合窗口（表决误判 PINCH → 误起笔），而拳内距离从未拉开 →
	# 假捏合被拦截；完全张开后重新装填，冷却期内张掌的手早已完成，正常节奏无感。
	# 无原始捏距（无手数据/鼠标兜底）视作已分开，闸门不生效
	if raw_pinch_dist < 0.0:
		_pinch_armed = true
	elif not _pinch_armed:
		if raw_pinch_dist > PoseClassifier.PINCH_EXIT_RATIO:
			_sep_ms += delta
			if _sep_ms >= PINCH_REARM_S:
				_pinch_armed = true
		else:
			_sep_ms = 0.0
	# latch 只在观察到"确实松开了"后解除，施放后捏着不放不会自动重画；
	# 自愈过期兜底：识别若冻结在'捏合'，封锁最多 PINCH_LATCH_S 后自动解除
	if pose != PoseClassifier.Pose.PINCH:
		_pinch_latch = false
	if _pinch_latch:
		_latch_t += delta
		if _latch_t >= PINCH_LATCH_S:
			_pinch_latch = false
			_latch_t = 0.0
	else:
		_latch_t = 0.0

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
			if pose == PoseClassifier.Pose.PINCH:
				if not _pinch_latch and _pinch_armed:
					_enter_drawing(index_tip)
			elif pose == PoseClassifier.Pose.FIST:
				_enter_charge()
		State.CHARGE:
			if pose == PoseClassifier.Pose.PINCH and _pinch_armed:
				_enter_drawing(index_tip)
			elif pose == PoseClassifier.Pose.PALM:
				_quick_shot()
		State.DRAWING:
			_update_drawing(pose, index_tip, delta, raw_pose)
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
	# 装备闸：与画符路径同规则
	if loadout != null and not loadout.is_equipped("quick_shot"):
		_fizzle("未装备该法术")
		return
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
	# 预滚播种：从当前指尖往回收集时间连续的预滚轨迹，补偿捏合去抖（5/7 帧表决）
	# 的起笔切头。间隙超过瞬移阈值即断开——张掌/握拳期的陈旧指尖位置不连进符文
	var prev := p
	var i := _preroll.size() - 1
	while i >= 0:
		var q: Vector2 = _preroll[i][1]
		if (prev - q).length() >= SAMPLE_TELEPORT:
			break
		trajectory.push_front(q)
		prev = q
		i -= 1
	trajectory_start_ms = Time.get_ticks_msec()
	_open_ms = 0.0
	_draw_time = 0.0
	drawing_updated.emit(_trajectory_public())
	state_changed.emit("DRAWING")


func _update_drawing(pose: int, index_tip: Vector2, delta: float, raw_pose := -1) -> void:
	# 画符超时（GDD：轨迹窗口 2.5s）——超时视为收笔，直接拿现有轨迹进识别
	_draw_time += delta
	if _draw_time > DRAW_TIMEOUT:
		_release()
		return

	if pose == PoseClassifier.Pose.PINCH:
		_open_ms = 0.0
		# 采样以原始姿势为准：稳定姿势离开捏合要攒 3 票（~100ms 滞后），握拳收笔
		# 时卷动的指尖在滞后期仍会被采进轨迹，拖出向下一笔。原始判定离开捏合即刻
		# 停采（防拳 guard 的食指比值最先失效，是卷指最早的几何信号）
		if raw_pose == -1 or raw_pose == PoseClassifier.Pose.PINCH:
			_push_tip(index_tip)
		return
	if pose == PoseClassifier.Pose.PALM:
		_release()  # 张掌 = 立即收笔（保留旧即时路径）
		return
	# 非捏合（松开捏合/握拳/画符姿过渡帧）：暂停采样——松开瞬间食指会卷动，
	# 采进来的点是污染。短暂闪断 <PINCH_RELEASE_CONFIRM_S 当伪影吞掉；
	# 持续松开 = 抬笔收笔（握拳收笔的旧肌肉记忆由此继续可用）
	_open_ms += delta
	if _open_ms >= PINCH_RELEASE_CONFIRM_S:
		_release()


## 画符采样：间距过小不记（滤滤波残余抖动+静止堆点）；
## 单帧跳变过大必为伪影（如张掌确认期指尖跳到掌心），丢弃
func _push_tip(tip: Vector2) -> void:
	if trajectory.size() > 0:
		var d := (tip - trajectory[trajectory.size() - 1]).length()
		if d < SAMPLE_MIN_DIST or d >= SAMPLE_TELEPORT:
			return
	trajectory.append(tip)
	drawing_updated.emit(_trajectory_public())


## 起笔预滚环：保留最近 PREROLL_MS 的食指尖位置（每帧原始记录，播种时再过滤）
func _push_preroll(tip: Vector2) -> void:
	var now := Time.get_ticks_msec()
	_preroll.append([now, tip])
	while _preroll.size() > 0 and now - int(_preroll[0][0]) > PREROLL_MS:
		_preroll.pop_front()


## 画符轨迹的包围盒中心（0~1 归一化）：弹道从"画的图形"中心出，
## 而不是手的位置——画在哪，法术落在哪。轨迹异常时回退掌心锚点。
func _rune_center() -> Vector2:
	if trajectory.is_empty():
		return current_anchor
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for p in trajectory:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	return (min_v + max_v) * 0.5


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
	var spell_id: String = _rune_map.get(str(last_result.name), "")
	if spell_id.is_empty():
		_fizzle("未知符文")
		return
	# 装备闸：玩家在配置面板（C）勾掉的法术不可施放，不扣法力
	if loadout != null and not loadout.is_equipped(spell_id):
		_fizzle("未装备该法术")
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
	cast_performed.emit(spell_id, _rune_center(), last_result.score)
	state = State.COOLDOWN
	_cooldown_left = COOLDOWN_TIME
	trajectory.clear()
	_pinch_latch = true
	_pinch_armed = false  # 收笔即卸下装填：下一次起笔前须先明确分开拇指食指
	_sep_ms = 0.0
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
	_pinch_latch = true
	_pinch_armed = false  # 同 _release：收笔后先分开再起笔
	_sep_ms = 0.0
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


## latch 是否仍在封锁起笔（HUD 提示"先松开捏合"用）
func latch_active() -> bool:
	return _pinch_latch


## 起笔再装填是否完成（HUD 提示"先张开手再捏合"用；无原始捏距时恒为 true）
func pinch_armed() -> bool:
	return _pinch_armed
