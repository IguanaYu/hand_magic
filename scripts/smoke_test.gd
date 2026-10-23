class_name SmokeTest
extends RefCounted
## M0 核心算法冒烟测试：$1 识别器 + 姿势分类器（合成数据）。
## 运行: godot --headless --path . -- --smoke-test
## 期望: 全部 PASS（合成轨迹识别率 100%）。


const POSE_NAMES := ["NONE", "FIST", "PALM", "DRAWING", "PINCH", "VICTORY", "THUMB_UP", "ILOVEYOU"]


static func run() -> int:
	var pass_count := 0
	var fail_count := 0
	var rec := DollarRecognizer.new()

	var cases: Array = []
	cases.append(["circle", _make_circle(Vector2(0.4, 0.4), 0.15)])
	cases.append(["circle", _make_circle(Vector2(0.6, 0.55), 0.25)])
	cases.append(["circle", _make_circle(Vector2(0.5, 0.5), 0.08)])
	cases.append(["zigzag", _make_poly([Vector2(0.2, 0.2), Vector2(0.8, 0.2), Vector2(0.25, 0.8), Vector2(0.8, 0.8)])])
	cases.append(["zigzag", _make_poly([Vector2(0.3, 0.3), Vector2(0.7, 0.3), Vector2(0.3, 0.7), Vector2(0.7, 0.7)])])
	cases.append(["zigzag", _make_poly([Vector2(0.15, 0.25), Vector2(0.85, 0.25), Vector2(0.2, 0.75), Vector2(0.85, 0.75)])])
	cases.append(["triangle", _make_poly([Vector2(0.5, 0.15), Vector2(0.85, 0.8), Vector2(0.15, 0.8), Vector2(0.5, 0.15)])])
	cases.append(["triangle", _make_poly([Vector2(0.2, 0.7), Vector2(0.8, 0.7), Vector2(0.5, 0.2), Vector2(0.2, 0.7)])])
	cases.append(["slash", _make_poly([Vector2(0.2, 0.8), Vector2(0.8, 0.2)])])
	cases.append(["slash", _make_poly([Vector2(0.2, 0.2), Vector2(0.8, 0.8)])])

	for case in cases:
		var expected: String = case[0]
		var pts: Array = case[1]
		var result := rec.recognize(pts)
		var ok: bool = result.name == expected and result.score >= 0.8
		if ok:
			pass_count += 1
		else:
			fail_count += 1
		print("%s recognize: expect=%s got=%s score=%.3f" % ["[PASS]" if ok else "[FAIL]", expected, result.name, result.score])

	var pc := PoseClassifier.new()
	pc.confirm_frames = 1
	var pose_cases: Array = [
		["FIST", _make_fist()],
		["PALM", _make_palm()],
		["DRAWING", _make_drawing()],
		["PINCH", _make_pinch()],
	]
	for pcase in pose_cases:
		var expected_pose: String = pcase[0]
		var lms: Array = pcase[1]
		var got: int = pc.classify(lms)
		var got_name: String = POSE_NAMES[got]
		var ok2: bool = got_name == expected_pose
		if ok2:
			pass_count += 1
		else:
			fail_count += 1
		print("%s pose: expect=%s got=%s" % ["[PASS]" if ok2 else "[FAIL]", expected_pose, got_name])

	# 捏合 guard：握拳且拇指尖蹭到食指尖（收在掌心内）必须判 FIST，不判 PINCH
	var pcg := PoseClassifier.new()
	pcg.confirm_frames = 1
	var guard_ok: bool = pcg.classify(_make_fist_touch()) == PoseClassifier.Pose.FIST
	if guard_ok:
		pass_count += 1
	else:
		fail_count += 1
	print("%s pinch-guard: 拳内拇指蹭指尖不误判捏合（got=%s）" % [
		"[PASS]" if guard_ok else "[FAIL]", POSE_NAMES[pcg.stable_pose()]])

	# 捏合滞回：进入后捏距在进入/退出阈值之间维持 PINCH，拉开到退出阈值外才切换
	var pc4 := PoseClassifier.new()
	pc4.confirm_frames = 1
	var enter_ok: bool = pc4.classify(_make_pinch_dist(0.10)) == PoseClassifier.Pose.PINCH
	var hold_ok: bool = pc4.classify(_make_pinch_dist(0.45)) == PoseClassifier.Pose.PINCH
	var exit_got: int = pc4.classify(_make_pinch_dist(0.90))
	var hyst_ok: bool = enter_ok and hold_ok and exit_got != PoseClassifier.Pose.PINCH
	if hyst_ok:
		pass_count += 1
	else:
		fail_count += 1
	print("%s pinch-hyst: 捏合进入/半开维持/拉开退出（enter=%s hold=%s exit=%s）" % [
		"[PASS]" if hyst_ok else "[FAIL]", enter_ok, hold_ok, POSE_NAMES[exit_got]])

	# 捏合快速退出：松开后 3 票即离开捏合（5 票全一致在手运动时凑不齐 → 卡'捏合'24s 真机事故）
	var pc6 := PoseClassifier.new()  # 默认 confirm_frames=5
	for i in range(6):
		pc6.classify(_make_pinch())
	var pinch_entered: bool = pc6.stable_pose() == PoseClassifier.Pose.PINCH
	for i in range(3):
		pc6.classify(_make_palm())
	var pinch_left: bool = pc6.stable_pose() != PoseClassifier.Pose.PINCH
	var fastexit_ok: bool = pinch_entered and pinch_left
	if fastexit_ok:
		pass_count += 1
	else:
		fail_count += 1
	print("%s pinch-fastexit: 进入5票/离开3票（entered=%s left=%s）" % [
		"[PASS]" if fastexit_ok else "[FAIL]", pinch_entered, pinch_left])

	# 多数表决防抖：交替闪烁不切换（旧"全一致"方案会卡死，新方案两姿态各≤4票<5）
	var pc2 := PoseClassifier.new()
	for i in range(20):
		pc2.classify(_make_fist() if i % 2 == 0 else _make_drawing())
	var flicker_ok: bool = pc2.stable_pose() == PoseClassifier.Pose.NONE
	if flicker_ok:
		pass_count += 1
	else:
		fail_count += 1
	print("%s debounce: 交替闪烁20帧稳定姿势不切换（got=%s）" % [
		"[PASS]" if flicker_ok else "[FAIL]", POSE_NAMES[pc2.stable_pose()]])

	# 捏合/张掌交替闪烁同样不切换（画符中松劲闪断不吞姿势）
	var pc5 := PoseClassifier.new()
	for i in range(20):
		pc5.classify(_make_pinch() if i % 2 == 0 else _make_palm())
	var flicker2_ok: bool = pc5.stable_pose() == PoseClassifier.Pose.NONE
	if flicker2_ok:
		pass_count += 1
	else:
		fail_count += 1
	print("%s debounce: 捏合/张掌交替闪烁不切换（got=%s）" % [
		"[PASS]" if flicker2_ok else "[FAIL]", POSE_NAMES[pc5.stable_pose()]])

	# 多数表决防抖：持续喂同一姿势攒够票数要能切换（拳→掌，顺带覆盖滞回退出路径）
	var fist_turn: bool = false
	for i in range(6):
		if pc2.classify(_make_fist()) == PoseClassifier.Pose.FIST:
			fist_turn = true
	var palm_turn: bool = false
	for i in range(6):
		if pc2.classify(_make_palm()) == PoseClassifier.Pose.PALM:
			palm_turn = true
	var switch_ok: bool = fist_turn and palm_turn
	if switch_ok:
		pass_count += 1
	else:
		fail_count += 1
	print("%s debounce: 持续喂拳→掌各6帧均切换（拳=%s 掌=%s）" % [
		"[PASS]" if switch_ok else "[FAIL]", fist_turn, palm_turn])

	# ---------- 符文样本存取 + 用户模板 ----------
	var rs_ok := _test_rune_samples(pass_count)
	pass_count += rs_ok[0]
	fail_count += rs_ok[1]
	var rt_ok := _test_user_templates(pass_count)
	pass_count += rt_ok[0]
	fail_count += rt_ok[1]

	# FSM 捏合交互单测：主路径/预滚/闪断/静止不收笔/超时/latch/快弹
	var fsm_ok := _test_fsm()
	pass_count += fsm_ok[0]
	fail_count += fsm_ok[1]

	# 扩展手势（2026-10 调研落地）：默认关闭=旧行为锚，开启=新手形/新符文可用
	var ext_ok := _test_extended()
	pass_count += ext_ok[0]
	fail_count += ext_ok[1]

	# 法术装备：数据/持久化单测 + 三处施法闸
	var lo_ok := _test_loadout()
	pass_count += lo_ok[0]
	fail_count += lo_ok[1]

	print("-------- 结果: %d PASS / %d FAIL --------" % [pass_count, fail_count])
	# GDMP 卸载死锁导致 stdout 缓冲可能丢失：结果同步写入文件
	var f := FileAccess.open("res://tests/smoke_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("%d PASS / %d FAIL\n" % [pass_count, fail_count])
	return 1 if fail_count > 0 else 0


static func _make_circle(center: Vector2, r: float) -> Array:
	var pts: Array = []
	for i in range(40):
		var t := TAU * i / 39.0
		pts.append(center + Vector2(cos(t - PI / 2.0), sin(t - PI / 2.0)) * r)
	return pts


static func _make_poly(vertices: Array) -> Array:
	var pts: Array = []
	for i in range(vertices.size() - 1):
		var a: Vector2 = vertices[i]
		var b: Vector2 = vertices[i + 1]
		var steps := maxi(8, int((b - a).length() / 0.02))
		for s in range(steps):
			pts.append(a.lerp(b, float(s) / float(steps)))
	pts.append(vertices[vertices.size() - 1])
	return pts


static func _base_hand() -> Array:
	var lms: Array = []
	for i in range(21):
		lms.append(Vector2(0.5, 0.5))
	lms[0] = Vector2(0.5, 0.7)
	lms[5] = Vector2(0.44, 0.6)
	lms[9] = Vector2(0.5, 0.59)
	lms[13] = Vector2(0.56, 0.6)
	lms[17] = Vector2(0.6, 0.62)
	return lms


static func _make_fist() -> Array:
	var lms := _base_hand()
	lms[8] = Vector2(0.46, 0.63)
	lms[12] = Vector2(0.5, 0.63)
	lms[16] = Vector2(0.55, 0.64)
	lms[20] = Vector2(0.59, 0.66)
	return lms


static func _make_palm() -> Array:
	var lms := _base_hand()
	lms[8] = Vector2(0.44, 0.38)
	lms[12] = Vector2(0.5, 0.34)
	lms[16] = Vector2(0.57, 0.36)
	lms[20] = Vector2(0.63, 0.42)
	return lms


static func _make_drawing() -> Array:
	var lms := _base_hand()
	lms[8] = Vector2(0.49, 0.3)
	lms[12] = Vector2(0.53, 0.6)
	lms[16] = Vector2(0.58, 0.62)
	lms[20] = Vector2(0.62, 0.65)
	return lms


static func _make_pinch() -> Array:
	# 捏合：拇指尖与食指尖相碰（落笔姿势），其余三指收拢。拇指链 1-2-3-4 给全
	var lms := _base_hand()
	lms[1] = Vector2(0.40, 0.62)
	lms[2] = Vector2(0.38, 0.54)
	lms[3] = Vector2(0.42, 0.47)
	lms[5] = Vector2(0.44, 0.60)
	lms[6] = Vector2(0.46, 0.52)
	lms[7] = Vector2(0.465, 0.47)
	lms[8] = Vector2(0.47, 0.42)  # 食指尖=拇指尖，捏距 0
	lms[4] = Vector2(0.47, 0.42)
	lms[12] = Vector2(0.53, 0.62)
	lms[16] = Vector2(0.57, 0.64)
	lms[20] = Vector2(0.61, 0.66)
	return lms


static func _make_pinch_dist(d: float) -> Array:
	# 捏距可控的捏合手：食指尖与拇指尖沿 x 拉开 d×掌长（滞回测试用）
	var lms := _make_pinch()
	lms[8] = lms[4] + Vector2(d * 0.11, 0.0)
	lms[7] = (lms[6] + lms[8]) * 0.5
	return lms


static func _make_fist_touch() -> Array:
	# 握拳但拇指尖蹭到食指尖（都收在掌心内）：捏合 guard 必须排除
	var lms := _make_fist()
	lms[1] = Vector2(0.38, 0.64)
	lms[2] = Vector2(0.40, 0.62)
	lms[3] = Vector2(0.44, 0.62)
	lms[4] = lms[8]
	return lms


## FSM 捏合交互单测（delta=1/30s 定步进，帧数即时间，确定性断言）
static func _test_fsm() -> Array:
	var p := 0
	var f := 0
	var dt := 1.0 / 30.0
	var anchor := Vector2(0.5, 0.5)

	# --- 主路径：预滚攒 6 帧移动轨迹 → 捏合起笔（播种）→ 捏合画圆 → 松开 0.12s 收笔 ---
	var counters := {"casts": 0, "fizzles": 0, "reason": ""}
	var fsm := GestureFSM.new()
	# 注意：GDScript lambda 按值捕获局部变量，计数器必须用引用类型容器
	fsm.cast_performed.connect(func(_s, _a, _sc): counters.casts += 1)
	fsm.fizzle.connect(func(r): counters.fizzles += 1; counters.reason = r)
	var circle := _make_circle(Vector2(0.5, 0.5), 0.15)
	for i in range(6):
		fsm.update(PoseClassifier.Pose.NONE, true, circle[0].lerp(circle[1], i / 5.0), anchor, dt)
	fsm.update(PoseClassifier.Pose.PINCH, true, circle[0], anchor, dt)
	var start_ok: bool = fsm.state == GestureFSM.State.DRAWING and fsm.trajectory.size() >= 4
	for i in range(1, circle.size()):
		fsm.update(PoseClassifier.Pose.PINCH, true, circle[i], anchor, dt)
	var n_drawn: int = fsm.trajectory.size()
	for i in range(3):  # 3 帧 = 0.1s < 0.12s：还没到确认时长
		fsm.update(PoseClassifier.Pose.DRAWING, true, circle[circle.size() - 1], anchor, dt)
	var hold_ok: bool = fsm.state == GestureFSM.State.DRAWING and fsm.trajectory.size() == n_drawn and counters.casts == 0
	fsm.update(PoseClassifier.Pose.DRAWING, true, circle[circle.size() - 1], anchor, dt)  # 第 4 帧 0.132s ≥ 0.12s
	var main_ok: bool = start_ok and hold_ok and counters.casts == 1 and counters.fizzles == 0
	if main_ok:
		p += 1
	else:
		f += 1
	print("%s fsm.pinch: 起笔含预滚(%d点)=%s 松开中不采样=%s 收笔施放=%d次失败=%d" % [
		"[PASS]" if main_ok else "[FAIL]", n_drawn, start_ok, hold_ok, counters.casts, counters.fizzles])

	# --- latch：施放后捏着不松，冷却结束回 IDLE 也不自动重画；松开一次后恢复 ---
	for i in range(35):  # 1.17s > 0.8s 冷却：中途转 IDLE，latch 挡住重画
		fsm.update(PoseClassifier.Pose.PINCH, true, circle[0], anchor, dt)
	var latch_ok: bool = fsm.state == GestureFSM.State.IDLE
	fsm.update(PoseClassifier.Pose.PINCH, true, circle[0], anchor, dt)
	latch_ok = latch_ok and fsm.state == GestureFSM.State.IDLE
	fsm.update(PoseClassifier.Pose.NONE, true, circle[0], anchor, dt)  # 松开一次
	fsm.update(PoseClassifier.Pose.PINCH, true, circle[0], anchor, dt)
	latch_ok = latch_ok and fsm.state == GestureFSM.State.DRAWING
	if latch_ok:
		p += 1
	else:
		f += 1
	print("%s fsm.latch: 施放后捏着不自动重画，松开一次恢复" % ["[PASS]" if latch_ok else "[FAIL]"])

	# --- 闪断：画符中 2 帧非捏合（0.067s < 0.12s）不中断不收笔，继续画完照常施放 ---
	var counters2 := {"casts": 0}
	var fsm2 := GestureFSM.new()
	fsm2.cast_performed.connect(func(_s, _a, _sc): counters2.casts += 1)
	var pts2 := _make_circle(Vector2(0.35, 0.5), 0.12)
	fsm2.update(PoseClassifier.Pose.PINCH, true, pts2[0], anchor, dt)
	for i in range(1, 20):
		fsm2.update(PoseClassifier.Pose.PINCH, true, pts2[i], anchor, dt)
	fsm2.update(PoseClassifier.Pose.FIST, true, pts2[19], anchor, dt)   # 闪断帧1
	fsm2.update(PoseClassifier.Pose.NONE, true, pts2[19], anchor, dt)   # 闪断帧2
	var flash_ok: bool = fsm2.state == GestureFSM.State.DRAWING and counters2.casts == 0
	for i in range(20, pts2.size()):
		fsm2.update(PoseClassifier.Pose.PINCH, true, pts2[i], anchor, dt)
	fsm2.update(PoseClassifier.Pose.PALM, true, pts2[pts2.size() - 1], anchor, dt)
	flash_ok = flash_ok and counters2.casts == 1
	if flash_ok:
		p += 1
	else:
		f += 1
	print("%s fsm.flash: 闪断2帧不中断，画完照常施放（cast=%d）" % ["[PASS]" if flash_ok else "[FAIL]", counters2.casts])

	# --- 静止不收笔：旧速度收笔兜底已删，捏着不动 1.3s 不结束（回归锚）---
	var counters3 := {"casts": 0, "fizzles": 0}
	var fsm3 := GestureFSM.new()
	fsm3.cast_performed.connect(func(_s, _a, _sc): counters3.casts += 1)
	fsm3.fizzle.connect(func(_r): counters3.fizzles += 1)
	var pts3 := _make_circle(Vector2(0.65, 0.5), 0.12)
	fsm3.update(PoseClassifier.Pose.PINCH, true, pts3[0], anchor, dt)
	for i in range(1, 15):
		fsm3.update(PoseClassifier.Pose.PINCH, true, pts3[i], anchor, dt)
	for i in range(40):  # 1.33s 静止
		fsm3.update(PoseClassifier.Pose.PINCH, true, pts3[14], anchor, dt)
	var static_ok: bool = fsm3.state == GestureFSM.State.DRAWING and counters3.casts == 0 and counters3.fizzles == 0
	if static_ok:
		p += 1
	else:
		f += 1
	print("%s fsm.static: 捏合静止1.3s不收笔（旧速度收笔已删）" % ["[PASS]" if static_ok else "[FAIL]"])

	# --- 超时收笔：接着静止越过 2.5s → 按现有轨迹收笔进冷却 ---
	for i in range(30):  # 累计 > 2.5s
		fsm3.update(PoseClassifier.Pose.PINCH, true, pts3[14], anchor, dt)
	var timeout_ok: bool = fsm3.state == GestureFSM.State.COOLDOWN
	if timeout_ok:
		p += 1
	else:
		f += 1
	print("%s fsm.timeout: 捏着不动超2.5s超时收笔" % ["[PASS]" if timeout_ok else "[FAIL]"])

	# --- latch 自愈：识别卡死在'捏合'时，封锁 PINCH_LATCH_S 后自动解除（真机事故回归锚）---
	var counters5 := {"fizzles": 0}
	var fsm5 := GestureFSM.new()
	fsm5.fizzle.connect(func(_r): counters5.fizzles += 1)
	for i in range(3):  # 短捏（3 点 < 8）→ fizzle → latch 置位
		fsm5.update(PoseClassifier.Pose.PINCH, true, Vector2(0.4 + i * 0.01, 0.5), anchor, dt)
	fsm5.update(PoseClassifier.Pose.PALM, true, Vector2(0.43, 0.5), anchor, dt)
	var fizzle_set: bool = counters5.fizzles == 1 and fsm5.latch_active()
	for i in range(30):  # 1.0s < 2.0s：仍在封锁（含 0.3s 冷却 + IDLE 阻挡）
		fsm5.update(PoseClassifier.Pose.PINCH, true, Vector2(0.44, 0.5), anchor, dt)
	var still_blocked: bool = fsm5.state == GestureFSM.State.IDLE
	for i in range(45):  # 再 1.5s（累计 2.5s > 2.0s）：自愈解锁，捏合可再进画符
		fsm5.update(PoseClassifier.Pose.PINCH, true, Vector2(0.44, 0.5), anchor, dt)
	var expiry_ok: bool = fizzle_set and still_blocked and fsm5.state == GestureFSM.State.DRAWING
	if expiry_ok:
		p += 1
	else:
		f += 1
	print("%s fsm.latch_expiry: 封锁1s内有效=%s，2s后自愈=%s" % [
		"[PASS]" if expiry_ok else "[FAIL]", still_blocked, fsm5.state == GestureFSM.State.DRAWING])

	# --- 快弹保留：拳→张掌 = 掌心火弹（CHARGE 仅剩的路径）---
	var counters4 := {"quick": 0}
	var fsm4 := GestureFSM.new()
	fsm4.quick_shot_performed.connect(func(_a): counters4.quick += 1)
	fsm4.update(PoseClassifier.Pose.FIST, true, Vector2(0.5, 0.5), anchor, dt)
	fsm4.update(PoseClassifier.Pose.PALM, true, Vector2(0.5, 0.5), anchor, dt)
	var quick_ok: bool = counters4.quick == 1
	if quick_ok:
		p += 1
	else:
		f += 1
	print("%s fsm.quick: 拳→张掌快速火弹保留" % ["[PASS]" if quick_ok else "[FAIL]"])

	# --- 收笔拖尾：握拳收笔时稳定姿势滞后（3 票 ~100ms 仍报 PINCH）、原始判定已离开 →
	# 卷动的指尖不再入轨（真机事故：握拳让指头向下，符文末尾多拖一笔）---
	var counters6 := {"casts": 0}
	var fsm6 := GestureFSM.new()
	fsm6.cast_performed.connect(func(_s, _a, _sc): counters6.casts += 1)
	var pts6 := _make_circle(Vector2(0.35, 0.45), 0.12)
	fsm6.update(PoseClassifier.Pose.PINCH, true, pts6[0], anchor, dt, PoseClassifier.Pose.PINCH, 0.10)
	for i in range(1, pts6.size()):
		fsm6.update(PoseClassifier.Pose.PINCH, true, pts6[i], anchor, dt, PoseClassifier.Pose.PINCH, 0.10)
	var n6: int = fsm6.trajectory.size()
	# 开始握拳：稳定姿势仍在去抖窗口内报 PINCH，原始已判 FIST，指尖向下卷动
	for i in range(3):
		fsm6.update(PoseClassifier.Pose.PINCH, true, Vector2(pts6[39].x, pts6[39].y + 0.03 * (i + 1)), anchor, dt, PoseClassifier.Pose.FIST, 0.40)
	var tail_ok: bool = fsm6.trajectory.size() == n6
	# 稳定姿势离开捏合 → 0.12s 确认收笔 → 施放（轨迹无拖尾仍可识别）
	for i in range(5):
		fsm6.update(PoseClassifier.Pose.FIST, true, Vector2(pts6[39].x, 0.72), anchor, dt, PoseClassifier.Pose.FIST, 0.40)
	tail_ok = tail_ok and counters6.casts == 1
	# 旧行为锚：不提供原始姿势（鼠标兜底/旧调用方）时照旧采样，闸门接线正确性由对比锁定
	var fsm6b := GestureFSM.new()
	fsm6b.update(PoseClassifier.Pose.PINCH, true, pts6[0], anchor, dt)
	for i in range(1, pts6.size()):
		fsm6b.update(PoseClassifier.Pose.PINCH, true, pts6[i], anchor, dt)
	var n6b: int = fsm6b.trajectory.size()
	for i in range(3):
		fsm6b.update(PoseClassifier.Pose.PINCH, true, Vector2(pts6[39].x, pts6[39].y + 0.03 * (i + 1)), anchor, dt)
	tail_ok = tail_ok and fsm6b.trajectory.size() > n6b
	if tail_ok:
		p += 1
	else:
		f += 1
	print("%s fsm.tail: 握拳收笔卷指不入轨(%d→%d)，旧行为锚=%s" % [
		"[PASS]" if tail_ok else "[FAIL]", n6, fsm6.trajectory.size(), fsm6b.trajectory.size() > n6b])

	# --- 再装填：握拳收笔后拇指食指从未明确分开，展开途中表决把瞬态误判成稳定 PINCH
	#（假捏合窗口）也不误起笔；完全张开后恢复（真机事故：拳→张掌莫名开始画符）---
	var counters7 := {"casts": 0}
	var fsm7 := GestureFSM.new()
	fsm7.cast_performed.connect(func(_s, _a, _sc): counters7.casts += 1)
	var pts7 := _make_circle(Vector2(0.65, 0.45), 0.12)
	fsm7.update(PoseClassifier.Pose.PINCH, true, pts7[0], anchor, dt, PoseClassifier.Pose.PINCH, 0.10)
	for i in range(1, pts7.size()):
		fsm7.update(PoseClassifier.Pose.PINCH, true, pts7[i], anchor, dt, PoseClassifier.Pose.PINCH, 0.10)
	for i in range(5):  # 握拳收笔（0.132s ≥ 0.12s）→ 施放，捏距 0.45 从未拉开
		fsm7.update(PoseClassifier.Pose.FIST, true, pts7[39], anchor, dt, PoseClassifier.Pose.FIST, 0.45)
	for i in range(30):  # 1.0s > 0.8s 冷却：握拳保持（模拟收笔后手停在拳上）
		fsm7.update(PoseClassifier.Pose.NONE, true, pts7[0], anchor, dt, PoseClassifier.Pose.NONE, 0.45)
	for i in range(6):  # 展开途中假捏合窗口：稳定姿势被表决误判 PINCH，捏距仍小
		fsm7.update(PoseClassifier.Pose.PINCH, true, pts7[0], anchor, dt, PoseClassifier.Pose.PINCH, 0.30)
	var false_ok: bool = fsm7.state == GestureFSM.State.IDLE and counters7.casts == 1
	for i in range(5):  # 完全张开：捏距 0.8 持续 0.165s > 0.10s → 再装填完成
		fsm7.update(PoseClassifier.Pose.PALM, true, pts7[0], anchor, dt, PoseClassifier.Pose.PALM, 0.80)
	fsm7.update(PoseClassifier.Pose.PINCH, true, pts7[0], anchor, dt, PoseClassifier.Pose.PINCH, 0.10)
	var rearm_ok: bool = false_ok and fsm7.state == GestureFSM.State.DRAWING
	if rearm_ok:
		p += 1
	else:
		f += 1
	print("%s fsm.rearm: 拳→张掌假捏合被拦=%s，张开后起笔恢复=%s" % [
		"[PASS]" if rearm_ok else "[FAIL]", false_ok, fsm7.state == GestureFSM.State.DRAWING])

	return [p, f]


## ---------- 扩展手势合成手工厂（21 关键点，基于 _base_hand 的掌长 0.11） ----------

static func _make_victory() -> Array:
	# 比耶：食指+中指伸直张开，无名指+小指弯（旧管线判 NONE）
	var lms := _base_hand()
	lms[8] = Vector2(0.44, 0.38)
	lms[12] = Vector2(0.52, 0.34)
	lms[16] = Vector2(0.57, 0.62)
	lms[20] = Vector2(0.61, 0.65)
	return lms


static func _make_iloveyou() -> Array:
	# 我爱你：拇指+食指+小指伸，中指+无名指弯（旧管线判 NONE）
	var lms := _base_hand()
	lms[4] = Vector2(0.36, 0.50)
	lms[8] = Vector2(0.44, 0.38)
	lms[12] = Vector2(0.52, 0.60)
	lms[16] = Vector2(0.57, 0.62)
	lms[20] = Vector2(0.64, 0.42)
	return lms


static func _make_thumb_up() -> Array:
	# 点赞：四指全卷（拳形）+ 拇指竖起（拇指尖-小指根距离/掌长 ≈2.5 > 阈值 1.8；
	# 旧管线判 FIST——点赞是从拳分出的拇指伸直亚型）
	var lms := _make_fist()
	lms[1] = Vector2(0.42, 0.64)
	lms[2] = Vector2(0.40, 0.58)
	lms[3] = Vector2(0.39, 0.52)
	lms[4] = Vector2(0.38, 0.46)
	return lms


static func _make_none() -> Array:
	# 只伸中指：进不了拳/掌/画符/捏合，扩展手形也不应吞它 → NONE
	var lms := _base_hand()
	lms[8] = Vector2(0.47, 0.62)
	lms[12] = Vector2(0.51, 0.32)
	lms[16] = Vector2(0.57, 0.62)
	lms[20] = Vector2(0.61, 0.65)
	return lms


static func _make_wave(center: Vector2, size: float) -> Array:
	# 横向正弦 ~1.5 周期（与 dollar_recognizer.register_extended_runes 模板同形）
	var pts: Array = []
	for i in range(48):
		var t := float(i) / 47.0
		pts.append(center + Vector2((t - 0.5) * 2.6 * size, -sin(t * PI * 3.0) * size))
	return pts


## 扩展手势单测：开关关闭=旧行为逐字节等价（锚）；开关打开=新手形/新符文可用。
## GestureFSM.extended_gestures 是 static var，测试内临时翻转、结束还原。
static func _test_extended() -> Array:
	var p := 0
	var f := 0
	var dt := 1.0 / 30.0
	var anchor := Vector2(0.5, 0.5)

	# --- 默认关闭：三个新手形在现役分类器下的旧行为锚 ---
	var pc0 := PoseClassifier.new()
	pc0.confirm_frames = 1
	var v_old: int = pc0.classify(_make_victory())
	var t_old: int = pc0.classify(_make_thumb_up())
	var l_old: int = pc0.classify(_make_iloveyou())
	var anchors_ok: bool = v_old == PoseClassifier.Pose.NONE and t_old == PoseClassifier.Pose.FIST \
		and l_old == PoseClassifier.Pose.NONE
	if anchors_ok:
		p += 1
	else:
		f += 1
	print("%s ext.anchor: 默认下比耶=%s 点赞=%s 我爱你=%s（期望 无/握拳/无）" % [
		"[PASS]" if anchors_ok else "[FAIL]", POSE_NAMES[v_old], POSE_NAMES[t_old], POSE_NAMES[l_old]])

	# --- 默认关闭：识别器无 wave 模板 ---
	var rec0 := DollarRecognizer.new()
	var no_wave_ok: bool = not rec0.template_counts().has("wave") and rec0.template_counts().size() == 4
	if no_wave_ok:
		p += 1
	else:
		f += 1
	print("%s ext.rec_default: 默认识别器无 wave 模板且 4 符文齐" % ["[PASS]" if no_wave_ok else "[FAIL]"])

	# --- 默认关闭 FSM 锚：波形轨迹匹配三角模板 → 施放冰霜（wave↔triangle 混淆对
	#    的实证锚点，$1 交叉分数 0.885——调研 ICMI 2014「圆↔三角混淆」同源结论）---
	var cast_spell := {"id": ""}
	var fsm0 := GestureFSM.new()
	fsm0.cast_performed.connect(func(s, _a, _sc): cast_spell.id = s)
	var wave := _make_wave(Vector2(0.5, 0.5), 0.15)
	for i in range(6):
		fsm0.update(PoseClassifier.Pose.NONE, true, wave[0].lerp(wave[1], i / 5.0), anchor, dt)
	fsm0.update(PoseClassifier.Pose.PINCH, true, wave[0], anchor, dt)
	for i in range(1, wave.size()):
		fsm0.update(PoseClassifier.Pose.PINCH, true, wave[i], anchor, dt)
	for i in range(4):
		fsm0.update(PoseClassifier.Pose.DRAWING, true, wave[wave.size() - 1], anchor, dt)
	var dfl_wave_ok: bool = cast_spell.id == "ice_field"
	if dfl_wave_ok:
		p += 1
	else:
		f += 1
	print("%s ext.fsm_default: 默认下画波形施放=%s（旧行为：经三角模板=冰霜）" % [
		"[PASS]" if dfl_wave_ok else "[FAIL]", cast_spell.id])

	# --- 开启：三个新静态手形正确分类，且不与现有姿势互串 ---
	GestureFSM.extended_gestures = true
	var pcx := PoseClassifier.new()
	pcx.extended_poses = true
	pcx.confirm_frames = 1
	var v_new: int = pcx.classify(_make_victory())
	var t_new: int = pcx.classify(_make_thumb_up())
	var l_new: int = pcx.classify(_make_iloveyou())
	var new_ok: bool = v_new == PoseClassifier.Pose.VICTORY and t_new == PoseClassifier.Pose.THUMB_UP \
		and l_new == PoseClassifier.Pose.ILOVEYOU
	if new_ok:
		p += 1
	else:
		f += 1
	print("%s ext.poses: 开启后比耶=%s 点赞=%s 我爱你=%s" % [
		"[PASS]" if new_ok else "[FAIL]", POSE_NAMES[v_new], POSE_NAMES[t_new], POSE_NAMES[l_new]])

	# 开启后纯拳/拳内蹭指尖仍判 FIST（点赞不吞拳，捏合 guard 不受影响）
	var fist_new: int = pcx.classify(_make_fist())
	var fisttouch_new: int = pcx.classify(_make_fist_touch())
	var fist_ok: bool = fist_new == PoseClassifier.Pose.FIST and fisttouch_new == PoseClassifier.Pose.FIST
	if fist_ok:
		p += 1
	else:
		f += 1
	print("%s ext.fist: 开启后纯拳=%s 拳内蹭指尖=%s（点赞亚型不吞拳）" % [
		"[PASS]" if fist_ok else "[FAIL]", POSE_NAMES[fist_new], POSE_NAMES[fisttouch_new]])

	# 开启后现有四姿势不串位（捏合/张掌/画符/无照旧）
	var pinch_new: int = pcx.classify(_make_pinch())
	var palm_new: int = pcx.classify(_make_palm())
	var draw_new: int = pcx.classify(_make_drawing())
	var none_new: int = pcx.classify(_make_none())
	var old4_ok: bool = pinch_new == PoseClassifier.Pose.PINCH and palm_new == PoseClassifier.Pose.PALM \
		and draw_new == PoseClassifier.Pose.DRAWING and none_new == PoseClassifier.Pose.NONE
	if old4_ok:
		p += 1
	else:
		f += 1
	print("%s ext.old4: 开启后捏合=%s 张掌=%s 画符=%s 无=%s 不串位" % [
		"[PASS]" if old4_ok else "[FAIL]", POSE_NAMES[pinch_new], POSE_NAMES[palm_new], POSE_NAMES[draw_new], POSE_NAMES[none_new]])

	# 表决去抖对新手形照常生效：5 票制下单帧比耶不切换
	var pcd := PoseClassifier.new()
	pcd.extended_poses = true
	for i in range(20):
		pcd.classify(_make_palm() if i % 2 == 0 else _make_victory())
	var flick_ok: bool = pcd.stable_pose() == PoseClassifier.Pose.NONE
	if flick_ok:
		p += 1
	else:
		f += 1
	print("%s ext.debounce: 张掌/比耶交替闪烁20帧不切换（got=%s）" % [
		"[PASS]" if flick_ok else "[FAIL]", POSE_NAMES[pcd.stable_pose()]])

	# --- 开启：识别器 wave 模板 + 三角移除 ---
	var recx := DollarRecognizer.new()
	recx.register_extended_runes()
	var counts: Dictionary = recx.template_counts()
	var counts_ok: bool = not counts.has("triangle") and counts.has("wave") and counts["wave"]["builtin"] == 1 \
		and counts.size() == 4
	if counts_ok:
		p += 1
	else:
		f += 1
	print("%s ext.rec_counts: 注册后三角移除、wave 就位（%d 符文）" % [
		"[PASS]" if counts_ok else "[FAIL]", counts.size()])

	var w1 := recx.recognize(_make_wave(Vector2(0.5, 0.5), 0.15))
	var w2 := recx.recognize(_make_wave(Vector2(0.45, 0.55), 0.10))
	var wave_ok: bool = w1.name == "wave" and w1.score >= 0.9 and w2.name == "wave" and w2.score >= 0.9
	if wave_ok:
		p += 1
	else:
		f += 1
	print("%s ext.wave: 波形识别 %s(%.3f)/%s(%.3f) ≥0.9" % [
		"[PASS]" if wave_ok else "[FAIL]", w1.name, w1.score, w2.name, w2.score])

	# wave↔zigzag 双向不互认（探针实测：分离度 0.95+，本用例盯住回归）
	var z1 := recx.recognize(_make_poly([Vector2(0.2, 0.2), Vector2(0.8, 0.2), Vector2(0.25, 0.8), Vector2(0.8, 0.8)]))
	var z2 := recx.recognize(_make_poly([Vector2(0.3, 0.3), Vector2(0.7, 0.3), Vector2(0.3, 0.7), Vector2(0.7, 0.7)]))
	var sep_ok: bool = z1.name == "zigzag" and z1.score >= 0.9 and z2.name == "zigzag" and z2.score >= 0.9
	if sep_ok:
		p += 1
	else:
		f += 1
	print("%s ext.sep: zigzag 仍判 zigzag %s(%.3f)/%s(%.3f)，不被 wave 抢走" % [
		"[PASS]" if sep_ok else "[FAIL]", z1.name, z1.score, z2.name, z2.score])

	# 波形加抖动 + 旋转 15° 仍判 wave（低帧率/手抖容忍下限）
	var rot := deg_to_rad(15.0)
	var wob: Array = []
	var raw_wave := _make_wave(Vector2(0.5, 0.5), 0.15)
	for i in range(raw_wave.size()):
		wob.append(raw_wave[i].rotated(rot) + Vector2(sin(i * 1.7) * 0.008, cos(i * 2.3) * 0.008))
	var w3 := recx.recognize(wob)
	var wob_ok: bool = w3.name == "wave" and w3.score >= 0.8
	if wob_ok:
		p += 1
	else:
		f += 1
	print("%s ext.wobble: 抖动+旋转15°波形=%s(%.3f) ≥0.8" % ["[PASS]" if wob_ok else "[FAIL]", w3.name, w3.score])

	# 开启后其余符文不串位：圆/斜线照旧
	var c1 := recx.recognize(_make_circle(Vector2(0.4, 0.4), 0.15))
	var s1 := recx.recognize(_make_poly([Vector2(0.2, 0.8), Vector2(0.8, 0.2)]))
	var others_ok: bool = c1.name == "circle" and c1.score >= 0.9 and s1.name == "slash" and s1.score >= 0.9
	if others_ok:
		p += 1
	else:
		f += 1
	print("%s ext.others: 圆=%s(%.3f) 斜线=%s(%.3f) 不受影响" % [
		"[PASS]" if others_ok else "[FAIL]", c1.name, c1.score, s1.name, s1.score])

	# --- 开启 FSM：画波形施放冰霜；画旧三角经 wave 模板同样施放冰霜
	#（肌肉记忆平滑降级而非 fizzle，探针实测交叉分 0.887）---
	var cast2 := {"id": "", "rune": ""}
	var fsmx := GestureFSM.new()  # flag 已开：_init 已注册 wave、移除三角
	fsmx.cast_performed.connect(func(s, _a, sc): cast2.id = s; cast2.rune = str(fsmx.last_result.name))
	for i in range(6):
		fsmx.update(PoseClassifier.Pose.NONE, true, wave[0].lerp(wave[1], i / 5.0), anchor, dt)
	fsmx.update(PoseClassifier.Pose.PINCH, true, wave[0], anchor, dt)
	for i in range(1, wave.size()):
		fsmx.update(PoseClassifier.Pose.PINCH, true, wave[i], anchor, dt)
	for i in range(4):
		fsmx.update(PoseClassifier.Pose.DRAWING, true, wave[wave.size() - 1], anchor, dt)
	var wave_cast_ok: bool = cast2.id == "ice_field" and cast2.rune == "wave"
	if wave_cast_ok:
		p += 1
	else:
		f += 1
	print("%s ext.fsm_wave: 开启后画波形施放=%s 经=%s（期望 ice_field/wave）" % [
		"[PASS]" if wave_cast_ok else "[FAIL]", cast2.id, cast2.rune])

	var cast3 := {"id": ""}
	var fsmx2 := GestureFSM.new()
	fsmx2.cast_performed.connect(func(s, _a, _sc): cast3.id = s)
	var tri := _make_poly([Vector2(0.5, 0.15), Vector2(0.85, 0.8), Vector2(0.15, 0.8), Vector2(0.5, 0.15)])
	for i in range(6):
		fsmx2.update(PoseClassifier.Pose.NONE, true, tri[0].lerp(tri[1], i / 5.0), anchor, dt)
	fsmx2.update(PoseClassifier.Pose.PINCH, true, tri[0], anchor, dt)
	for i in range(1, tri.size()):
		fsmx2.update(PoseClassifier.Pose.PINCH, true, tri[i], anchor, dt)
	for i in range(4):
		fsmx2.update(PoseClassifier.Pose.DRAWING, true, tri[tri.size() - 1], anchor, dt)
	var tri_cast_ok: bool = cast3.id == "ice_field" and str(fsmx2.last_result.name) == "wave"
	if tri_cast_ok:
		p += 1
	else:
		f += 1
	print("%s ext.fsm_tri: 开启后画旧三角=%s 经=%s（肌肉记忆平滑降级，仍冰霜）" % [
		"[PASS]" if tri_cast_ok else "[FAIL]", cast3.id, fsmx2.last_result.name])

	# --- rune_of 反查随开关联动（样本存取/录制面板的共同入口）---
	var rune_ext: String = RuneSamples.rune_of("ice_field")  # 仍处于开启态
	GestureFSM.extended_gestures = false
	var rune_dfl: String = RuneSamples.rune_of("ice_field")
	var rune_ok: bool = rune_ext == "wave" and rune_dfl == "triangle"
	if rune_ok:
		p += 1
	else:
		f += 1
	print("%s ext.rune_of: ice_field 反查 开启=%s 关闭=%s（期望 wave/triangle）" % [
		"[PASS]" if rune_ok else "[FAIL]", rune_ext, rune_dfl])

	return [p, f]


## 法术装备单测：默认全装备/勾选/上限拒绝/存读回环/损坏降级/FSM 施法闸。
## 存档走测试路径（user://test_spell_loadout.json），不碰玩家真实配置。
static func _test_loadout() -> Array:
	var p := 0
	var f := 0
	var dt := 1.0 / 30.0
	var anchor := Vector2(0.5, 0.5)

	# --- 默认全装备（现役玩法零变化的语义锚）+ 勾选/取消 ---
	var lo := SpellLoadout.new()
	lo.save_path = "user://test_spell_loadout.json"
	lo.reset_default()
	var dfl_ok: bool = lo.count() == 5 and lo.is_equipped("fireball") and lo.is_equipped("quick_shot")
	lo.unequip("ice_field")
	var un_ok: bool = lo.count() == 4 and not lo.is_equipped("ice_field")
	var re_ok: bool = lo.equip("ice_field") == "ok" and lo.count() == 5
	# --- 上限拒绝：调小上限验证（池子=5=暂定上限，默认参数触发不了 full）---
	lo.unequip("wind_blade")
	lo.max_equipped = 4
	lo.unequip("lightning")
	var full_ok: bool = lo.count() == 3 and lo.equip("lightning") == "ok" and lo.equip("wind_blade") == "full"
	var unk_ok: bool = lo.equip("bogus") == "unknown"
	var states_ok: bool = dfl_ok and un_ok and re_ok and full_ok and unk_ok
	if states_ok:
		p += 1
	else:
		f += 1
	print("%s loadout.data: 默认5=%s 取消=%s 复勾=%s 超限拒=%s 非法id拒=%s" % [
		"[PASS]" if states_ok else "[FAIL]", dfl_ok, un_ok, re_ok, full_ok, unk_ok])

	# --- 存读回环 ---
	lo.unequip("ice_field")
	var save_ok: bool = lo.save()
	var lo2 := SpellLoadout.new()
	lo2.save_path = lo.save_path
	var load_ok: bool = lo2.load() and lo2.count() == 3 and not lo2.is_equipped("ice_field") \
		and not lo2.is_equipped("wind_blade") and lo2.is_equipped("fireball")
	var persist_ok: bool = save_ok and load_ok
	if persist_ok:
		p += 1
	else:
		f += 1
	print("%s loadout.save: 存档=%s 读档=%s（3 装备，冰域/风刃未勾）" % [
		"[PASS]" if persist_ok else "[FAIL]", save_ok, load_ok])

	# --- 损坏/异常存档静默降级 → 默认全装备 ---
	var fw := FileAccess.open(lo.save_path, FileAccess.WRITE)
	fw.store_string("{{{not json")
	fw.close()
	var lo3 := SpellLoadout.new()
	lo3.save_path = lo.save_path
	var corrupt_ok: bool = not lo3.load() and lo3.count() == 5
	var fw2 := FileAccess.open(lo.save_path, FileAccess.WRITE)
	fw2.store_string(JSON.stringify({"version": 1, "equipped": ["fireball", "bogus"]}))
	fw2.close()
	var lo4 := SpellLoadout.new()
	lo4.save_path = lo.save_path
	var filter_ok: bool = lo4.load() and lo4.count() == 1 and lo4.is_equipped("fireball")
	var fw3 := FileAccess.open(lo.save_path, FileAccess.WRITE)
	fw3.store_string(JSON.stringify({"version": 1, "equipped": []}))
	fw3.close()
	var lo5 := SpellLoadout.new()
	lo5.save_path = lo.save_path
	var empty_ok: bool = not lo5.load() and lo5.count() == 5
	var degrade_ok: bool = corrupt_ok and filter_ok and empty_ok
	if degrade_ok:
		p += 1
	else:
		f += 1
	print("%s loadout.degrade: 损坏降级=%s 未知id剔除=%s 空装备降级=%s" % [
		"[PASS]" if degrade_ok else "[FAIL]", corrupt_ok, filter_ok, empty_ok])

	# --- 施法闸①：未装备的法术画符 fizzle"未装备该法术"，不扣法力 ---
	var lof := SpellLoadout.new()
	lof.unequip("ice_field")
	var c8 := {"casts": 0, "fizzles": 0, "reason": ""}
	var fsm8 := GestureFSM.new()
	fsm8.loadout = lof
	fsm8.cast_performed.connect(func(_s, _a, _sc): c8.casts += 1)
	fsm8.fizzle.connect(func(r): c8.fizzles += 1; c8.reason = r)
	var tri8 := _make_poly([Vector2(0.5, 0.15), Vector2(0.85, 0.8), Vector2(0.15, 0.8), Vector2(0.5, 0.15)])
	for i in range(6):
		fsm8.update(PoseClassifier.Pose.NONE, true, tri8[0].lerp(tri8[1], i / 5.0), anchor, dt)
	fsm8.update(PoseClassifier.Pose.PINCH, true, tri8[0], anchor, dt)
	for i in range(1, tri8.size()):
		fsm8.update(PoseClassifier.Pose.PINCH, true, tri8[i], anchor, dt)
	for i in range(4):
		fsm8.update(PoseClassifier.Pose.DRAWING, true, tri8[tri8.size() - 1], anchor, dt)
	# 反面：装备中的法术照常施放（火球，同一 loadout）——冷却+latch 解除后画圆
	for i in range(12):
		fsm8.update(PoseClassifier.Pose.NONE, true, tri8[0], anchor, dt)
	var circle8 := _make_circle(Vector2(0.5, 0.5), 0.15)
	for i in range(6):
		fsm8.update(PoseClassifier.Pose.NONE, true, circle8[0].lerp(circle8[1], i / 5.0), anchor, dt)
	fsm8.update(PoseClassifier.Pose.PINCH, true, circle8[0], anchor, dt)
	for i in range(1, circle8.size()):
		fsm8.update(PoseClassifier.Pose.PINCH, true, circle8[i], anchor, dt)
	for i in range(4):
		fsm8.update(PoseClassifier.Pose.DRAWING, true, circle8[circle8.size() - 1], anchor, dt)
	var gate_ok: bool = c8.fizzles == 1 and c8.reason == "未装备该法术" and c8.casts == 1 \
		and is_equal_approx(fsm8.mana, GestureFSM.MANA_MAX - GestureFSM.SPELL_COST["fireball"])
	if gate_ok:
		p += 1
	else:
		f += 1
	print("%s loadout.gate: 未装备冰域fizzle(%s)施放=%d次 mana=%.1f（只扣火球25）" % [
		"[PASS]" if gate_ok else "[FAIL]", c8.reason, c8.casts, fsm8.mana])

	# --- 施法闸②：掌心火弹未装备时拳→张掌 fizzle；null 装备=全装备锚 ---
	var loq := SpellLoadout.new()
	loq.unequip("quick_shot")
	var fsm9 := GestureFSM.new()
	fsm9.loadout = loq
	var q9 := {"quick": 0, "fizzles": 0, "reason": ""}
	fsm9.quick_shot_performed.connect(func(_a): q9.quick += 1)
	fsm9.fizzle.connect(func(r): q9.fizzles += 1; q9.reason = r)
	fsm9.update(PoseClassifier.Pose.FIST, true, Vector2(0.5, 0.5), anchor, dt)
	fsm9.update(PoseClassifier.Pose.PALM, true, Vector2(0.5, 0.5), anchor, dt)
	var fsm10 := GestureFSM.new()  # 无 loadout（null 路径，旧调用方兼容锚）
	var q10 := {"quick": 0}
	fsm10.quick_shot_performed.connect(func(_a): q10.quick += 1)
	fsm10.update(PoseClassifier.Pose.FIST, true, Vector2(0.5, 0.5), anchor, dt)
	fsm10.update(PoseClassifier.Pose.PALM, true, Vector2(0.5, 0.5), anchor, dt)
	var qs_ok: bool = q9.fizzles == 1 and q9.reason == "未装备该法术" and q9.quick == 0 and q10.quick == 1
	if qs_ok:
		p += 1
	else:
		f += 1
	print("%s loadout.quick: 未装备掌心火弹fizzle=%s（%s），null=全装备照常=%d次" % [
		"[PASS]" if qs_ok else "[FAIL]", q9.fizzles == 1, q9.reason, q10.quick])

	return [p, f]


## 符文样本存取器单测：校验/上限/存读回环（写测试路径，不碰真实存档）
static func _test_rune_samples(passed: int) -> Array:
	var p := 0
	var f := 0
	var rs := RuneSamples.new()
	rs.save_path = "user://test_rune_samples.json"
	rs.clear_all()

	var short_ok: bool = rs.add("fireball", [Vector2(0.5, 0.5), Vector2(0.51, 0.5)]) == "invalid"
	var circle := _make_circle(Vector2(0.5, 0.5), 0.15)
	var add1_ok: bool = rs.add("fireball", circle) == "ok"
	for i in range(RuneSamples.MAX_PER_SPELL):
		rs.add("fireball", circle)
	var cap_ok: bool = rs.add("fireball", circle) == "full" and rs.count("fireball") == RuneSamples.MAX_PER_SPELL
	var save_ok: bool = rs.save()

	var rs2 := RuneSamples.new()
	rs2.save_path = rs.save_path
	var load_ok: bool = rs2.load() and rs2.count("fireball") == RuneSamples.MAX_PER_SPELL
	var pts_ok := false
	if rs2.count("fireball") > 0:
		var back: Array = rs2.samples["fireball"][0]
		pts_ok = back.size() == circle.size() and back[0].distance_to(circle[0]) < 0.001

	for name_ok in [short_ok, add1_ok, cap_ok, save_ok, load_ok, pts_ok]:
		if name_ok:
			p += 1
		else:
			f += 1
	print("%s samples: 校验=%s 追加=%s 上限=%s 存档=%s 读档=%s 坐标=%s" % [
		"[PASS]" if f == 0 else "[FAIL]", short_ok, add1_ok, cap_ok, save_ok, load_ok, pts_ok])
	rs2.clear_all()
	rs2.save()
	return [p, f]


## 用户模板单测：计数、录制样本参与识别、清理还原
static func _test_user_templates(passed: int) -> Array:
	var p := 0
	var f := 0
	var rec := DollarRecognizer.new()
	var base: Dictionary = rec.template_counts()
	var builtin_ok: bool = base.size() == 4 and base["circle"]["builtin"] == 1 and base["circle"]["user"] == 0

	# 录一个"手抖的圆"样本：比内置圆更接近真人画法，识别应稳定判圆
	var wobbly := _make_circle(Vector2(0.48, 0.52), 0.13)
	for i in range(wobbly.size()):
		wobbly[i] += Vector2(sin(i * 1.7) * 0.01, cos(i * 2.3) * 0.01)
	rec.add_recorded_template("circle", wobbly)
	var counts: Dictionary = rec.template_counts()
	var count_ok: bool = counts["circle"]["user"] == 1 and counts["circle"]["builtin"] == 1
	var got: Dictionary = rec.recognize(wobbly)
	var recog_ok: bool = got.name == "circle" and got.score >= 0.8

	rec.clear_user_templates("circle")
	var after: Dictionary = rec.template_counts()
	var clear_ok: bool = after["circle"]["user"] == 0 and after["circle"]["builtin"] == 1 and after.size() == base.size()

	for name_ok in [builtin_ok, count_ok, recog_ok, clear_ok]:
		if name_ok:
			p += 1
		else:
			f += 1
	print("%s user_template: 计数基线=%s 录后计数=%s 样本识别=%s(%s %.2f) 清理=%s" % [
		"[PASS]" if f == 0 else "[FAIL]", builtin_ok, count_ok, recog_ok, got.name, got.score, clear_ok])
	return [p, f]
