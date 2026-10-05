class_name E2ETest
extends Node
## 端到端仿真测试：合成手部关键点 → main 真实 _process 管线 → 法术/靶/HUD 断言。
## 相位机为「状态驱动 + 墙钟时间」，不依赖帧率（headless 帧率不锁 60fps）。
## 运行: godot --headless --path . -- --e2e-test
## 结果: tests/e2e_result.txt


const FIRE_ANCHOR := Vector2(0.25, 0.28)   # 靶0
const BOLT_ANCHOR := Vector2(0.5, 0.5)     # 场中心，链最近3个
const ICE_ANCHOR := Vector2(0.75, 0.28)    # 靶1
const BLADE_ANCHOR := Vector2(0.22, 0.68)  # 靶2
const WRIST := Vector2(0.5, 0.74)

var main: Node2D
var phase := 0
var stage := 0
var stage_t := 0.0        # 当前阶段累计墙钟时间
var stage_i := 0          # 轨迹游标
var wait_left := 0.0
var results: Array = []
var pass_count := 0
var fail_count := 0
var done := false
var broken_before := 0
var fizzles_before := 0
var casts_before := 0


func _process(delta: float) -> void:
	if done:
		return
	if wait_left > 0.0:
		wait_left -= delta
		return
	stage_t += delta
	match phase:
		0: _rune_phase("fireball", FIRE_ANCHOR, _circle_path(Vector2(0.5, 0.40), 0.12, 40))
		1: _rune_phase("lightning", BOLT_ANCHOR, _zigzag_path(Vector2(0.3, 0.3), Vector2(0.7, 0.55), 45))
		2: _respawn_phase()
		3: _rune_phase("ice_field", ICE_ANCHOR, _triangle_path(Vector2(0.5, 0.30), 0.28, 42))
		4: _rune_phase("wind_blade", BLADE_ANCHOR, _slash_path(Vector2(0.35, 0.6), Vector2(0.65, 0.35), 20))
		5: _rune_phase("garbage", Vector2(0.5, 0.5), _circle_path(Vector2(0.5, 0.55), 0.012, 30))
		6: _cancel_phase()
		7: _timeout_phase()
		_:
			_finish()


func _next_stage() -> void:
	stage += 1
	stage_t = 0.0
	stage_i = 0


func _advance() -> void:
	phase += 1
	stage = 0
	stage_t = 0.0
	stage_i = 0


# ---------- 通用法术相位 ----------
# S0 拳→聚气  S1 静指→画符  S2 走轨迹  S3 张掌→冷却  S4(风刃)等弹道

func _rune_phase(rune_id: String, anchor: Vector2, pts: Array) -> void:
	if stage == 0:
		anchor_debug = anchor
	match stage:
		0:
			_feed(_make_fist_at(anchor))
			if main.fsm.state == GestureFSM.State.CHARGE:
				_check("%s: 握拳进入聚气" % rune_id, true)
				_next_stage()
			elif stage_t > 3.0:
				_check("%s: 握拳进入聚气" % rune_id, false)
				_next_stage()
		1:
			_feed(_make_drawing_at(pts[0]))
			if main.fsm.state == GestureFSM.State.DRAWING:
				_check("%s: 伸指进入画符" % rune_id, true)
				_next_stage()
			elif stage_t > 2.0:
				_check("%s: 伸指进入画符" % rune_id, false)
				_next_stage()
		2:
			var idx: int = mini(stage_i, pts.size() - 1)
			_feed(_make_drawing_at(pts[idx]))
			stage_i += 1
			if stage_i >= pts.size():
				_check("%s: 拖尾随轨迹更新" % rune_id, main.trail.points.size() >= 8)
				broken_before = 4 - _alive_count()
				fizzles_before = main.fsm.fizzle_count
				casts_before = main.fsm.cast_count
				_next_stage()
		3:
			_feed(_make_palm_at(anchor))
			if main.fsm.state == GestureFSM.State.COOLDOWN or stage_t > 2.5:
				_assert_cast(rune_id)
				if rune_id == "wind_blade":
					_next_stage()
				else:
					_advance()
		4:  # 仅风刃：等待弹道飞行
			_feed(_make_palm_at(anchor))
			if 4 - _alive_count() - broken_before >= 1 or stage_t > 2.0:
				_check("风刃: 弹道命中目标", 4 - _alive_count() - broken_before >= 1)
				_advance()


func _assert_cast(rune_id: String) -> void:
	match rune_id:
		"fireball":
			_check("火球: spell_manager收到施放", main.spell_manager.cast_total == 1)
			_check("火球: 施放计数+1", main.fsm.cast_count == casts_before + 1)
			_check("火球: 法力扣减", main.fsm.mana < 100.0 and main.fsm.mana >= 70.0)
			var broken := 4 - _alive_count() - broken_before
			_check("火球: 砸碎锚点靶0 (碎%d)" % broken, broken == 1)
			if broken != 1:
				_debug_fireball(anchor_debug)
			_check("火球: circle识别得分≥0.8", float(main.fsm.last_result.get("score", 0.0)) >= 0.8)
		"lightning":
			_check("链电: 施放计数+1", main.fsm.cast_count == casts_before + 1)
			_check("链电: 链住3个靶", 4 - _alive_count() - broken_before == 3)
		"ice_field":
			var t1: TargetDummy = _targets()[1]
			_check("冰域: 施放计数+1", main.fsm.cast_count == casts_before + 1)
			_check("冰域: 靶1被冰冻未击碎", t1.frozen and t1.alive)
			_check("冰域: 全场无击碎", _alive_count() == 4)
		"wind_blade":
			_check("风刃: 施放计数+1", main.fsm.cast_count == casts_before + 1)
		"garbage":
			_check("FIZZLE: 垃圾轨迹失败计数+1", main.fsm.fizzle_count > fizzles_before)
			_check("FIZZLE: 失败不施放", main.fsm.cast_count == casts_before)
	# 调试：施放结果全文
	results.append("  dbg[%s]: cast=%d/%d fizz=%d(%s) last=%s trail=%d mana=%.0f traj=%d" % [
		rune_id, main.fsm.cast_count, main.spell_manager.cast_total, main.fsm.fizzle_count,
		main.fsm.last_fizzle_reason, str(main.fsm.last_result), main.trail.points.size(),
		main.fsm.mana, main.fsm.last_trajectory.size()])
	if main.fsm.cast_trajectory.size() > 0:
		var ct: Array = main.fsm.cast_trajectory
		var sample: Array = []
		for k in range(0, ct.size(), maxi(1, ct.size() / 8)):
			sample.append("(%.3f,%.3f)" % [ct[k].x, ct[k].y])
		var refire: Dictionary = main.fsm.recognizer.recognize(ct)
		results.append("  cast_traj: n=%d 采样=%s →重识别=%s(%.3f)" % [ct.size(), " ".join(sample), refire.name, refire.score])


var anchor_debug := Vector2.ZERO


func _debug_fireball(anchor_norm: Vector2) -> void:
	# miss 时转储关键坐标，便于定位
	var t0: TargetDummy = _targets()[0]
	var anc: Vector2 = main.spell_manager.to_screen(anchor_norm)
	var anchor_used: Vector2 = main.spell_manager.to_screen(main.fsm.current_anchor)
	results.append("  debug: view=%s t0=%s anchor=%s fsm_anchor=%s radius=%.0f" % [
		main.spell_manager.view_size, t0.global_position, anc, anchor_used,
		minf(main.spell_manager.view_size.x, main.spell_manager.view_size.y) * 0.15])


# ---------- 其他相位 ----------

func _respawn_phase() -> void:
	if stage == 0:
		wait_left = 3.2
		_feed(_make_palm_at(Vector2(0.5, 0.9)))
		_next_stage()
	else:
		_check("重生: 练习靶全部复活", _alive_count() == 4)
		_advance()


func _cancel_phase() -> void:
	match stage:
		0:
			_feed(_make_fist_at(Vector2(0.5, 0.5)))
			if main.fsm.state == GestureFSM.State.CHARGE:
				_check("取消: 先进入聚气", true)
				_next_stage()
			elif stage_t > 3.0:
				_check("取消: 先进入聚气", false)
				_next_stage()
		1:
			_feed(_make_palm_at(Vector2(0.5, 0.5)))
			if main.fsm.state == GestureFSM.State.IDLE:
				_check("取消: 张掌保持500ms回到待机", true)
				_advance()
			elif stage_t > 2.0:
				_check("取消: 张掌保持500ms回到待机", false)
				_advance()


func _timeout_phase() -> void:
	var pts := _circle_path(Vector2(0.5, 0.40), 0.10, 60)
	match stage:
		0:
			_feed(_make_fist_at(Vector2(0.5, 0.5)))
			if main.fsm.state == GestureFSM.State.CHARGE:
				fizzles_before = main.fsm.fizzle_count
				_next_stage()
			elif stage_t > 3.0:
				_next_stage()
		1:
			_feed(_make_drawing_at(pts[0]))
			if main.fsm.state == GestureFSM.State.DRAWING:
				_next_stage()
			elif stage_t > 2.0:
				_next_stage()
		2:
			var t := stage_t
			var p := Vector2(0.5 + 0.015 * cos(t * 2.0), 0.40 + 0.015 * sin(t * 2.0))
			_feed(_make_drawing_at(p))
			if main.fsm.fizzle_count > fizzles_before or stage_t > 4.0:
				_check("超时: 2.5s自动FIZZLE", main.fsm.fizzle_count > fizzles_before)
				_check("超时: 失败不施放", main.fsm.cast_count == casts_before)
				_advance()


# ---------- 收尾 + 性能基准 ----------

func _finish() -> void:
	done = true
	var rec := DollarRecognizer.new()
	var circle := _circle_path(Vector2(0.5, 0.4), 0.12, 40)
	var t0 := Time.get_ticks_usec()
	for i in range(20):
		rec.recognize(circle)
	var avg_ms := (Time.get_ticks_usec() - t0) / 20.0 / 1000.0
	# 识别仅在施放时执行一次（非每帧），单次 <12ms 不构成帧预算问题
	_check("性能: 识别单次耗时 %.2fms (阈值12ms)" % avg_ms, avg_ms < 12.0)

	var summary := "%d PASS / %d FAIL" % [pass_count, fail_count]
	print("-------- E2E 结果: %s --------" % summary)
	var f := FileAccess.open("res://tests/e2e_result.txt", FileAccess.WRITE)
	if f:
		f.store_string(summary + "\n")
		for r in results:
			f.store_string(r + "\n")
		f.store_string("recognize_avg_ms=%.2f\n" % avg_ms)
		f.flush()
	main.get_tree().quit(1 if fail_count > 0 else 0)


# ---------- 工具 ----------

func _feed(hand: Dictionary) -> void:
	main._on_hands_updated([hand])


func _check(name: String, cond: bool) -> void:
	if cond:
		pass_count += 1
	else:
		fail_count += 1
	results.append("%s %s" % ["[PASS]" if cond else "[FAIL]", name])
	print("%s %s" % ["[PASS]" if cond else "[FAIL]", name])


func _targets() -> Array:
	return main.spell_manager.target_layer.get_children()


func _alive_count() -> int:
	var n := 0
	for t in _targets():
		if t.alive:
			n += 1
	return n


func _circle_path(center: Vector2, r: float, n: int) -> Array:
	var pts: Array = []
	for i in range(n):
		var t := TAU * i / float(n - 1)
		pts.append(center + Vector2(cos(t - PI / 2.0), sin(t - PI / 2.0)) * r)
	return pts


func _zigzag_path(a: Vector2, b: Vector2, n: int) -> Array:
	var verts := [Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(a.x, b.y), Vector2(b.x, b.y)]
	var pts: Array = []
	for i in range(verts.size() - 1):
		var steps := maxi(5, int(n / 3.0))
		for s in range(steps):
			pts.append(verts[i].lerp(verts[i + 1], float(s) / float(steps)))
	pts.append(verts[verts.size() - 1])
	return pts


func _triangle_path(top: Vector2, size: float, n: int) -> Array:
	var verts := [top, top + Vector2(size * 0.6, size), top + Vector2(-size * 0.6, size), top]
	var pts: Array = []
	for i in range(verts.size() - 1):
		var steps := maxi(5, int(n / 3.0))
		for s in range(steps):
			pts.append(verts[i].lerp(verts[i + 1], float(s) / float(steps)))
	pts.append(verts[verts.size() - 1])
	return pts


func _slash_path(a: Vector2, b: Vector2, n: int) -> Array:
	var pts: Array = []
	for i in range(n):
		pts.append(a.lerp(b, float(i) / float(n - 1)))
	return pts


# ---------- 合成手 ----------

func _make_fist_at(palm_pos: Vector2) -> Dictionary:
	var lms := SmokeTest._make_fist()
	_shift_hand(lms, palm_pos)
	return {"label": "Right", "points": lms, "palm": palm_pos, "palm_raw": palm_pos, "index_tip": lms[8]}


func _make_palm_at(palm_pos: Vector2) -> Dictionary:
	var lms := SmokeTest._make_palm()
	_shift_hand(lms, palm_pos)
	return {"label": "Right", "points": lms, "palm": palm_pos, "palm_raw": palm_pos, "index_tip": lms[8]}


func _make_drawing_at(tip: Vector2) -> Dictionary:
	var v := tip - WRIST
	var l := v.length()
	var palm_size := 0.11
	var dir := v / maxf(l, 1e-5)
	var lms: Array = []
	for i in range(21):
		lms.append(WRIST)
	lms[5] = WRIST + Vector2(-0.08, 0.02)
	lms[9] = WRIST + dir * palm_size
	lms[13] = WRIST + Vector2(0.08, 0.03)
	lms[17] = WRIST + Vector2(0.10, 0.06)
	lms[6] = WRIST + dir * (palm_size + (l - palm_size) * 0.33)
	lms[7] = WRIST + dir * (palm_size + (l - palm_size) * 0.66)
	lms[8] = tip
	lms[12] = lms[9] + dir * 0.02
	lms[16] = lms[13] + dir * 0.02
	lms[20] = lms[17] + dir * 0.02
	return {"label": "Right", "points": lms, "palm": (lms[0] + lms[5] + lms[9] + lms[17]) / 4.0, "palm_raw": lms[9], "index_tip": tip}


func _shift_hand(lms: Array, new_palm: Vector2) -> void:
	var cur: Vector2 = (lms[0] + lms[5] + lms[9] + lms[17]) / 4.0
	var off: Vector2 = new_palm - cur
	for i in range(lms.size()):
		lms[i] = lms[i] + off
