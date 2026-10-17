class_name SmokeTest
extends RefCounted
## M0 核心算法冒烟测试：$1 识别器 + 姿势分类器（合成数据）。
## 运行: godot --headless --path . -- --smoke-test
## 期望: 全部 PASS（合成轨迹识别率 100%）。


const POSE_NAMES := ["NONE", "FIST", "PALM", "DRAWING", "PINCH"]


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

	# FSM 快速走查：聚气→画圆→施放
	var fsm := GestureFSM.new()
	# 注意：GDScript lambda 按值捕获局部变量，计数器必须用引用类型容器
	var counters := {"casts": 0, "fizzles": 0, "reason": ""}
	fsm.cast_performed.connect(func(_s, _a, _sc): counters.casts += 1)
	fsm.fizzle.connect(func(r): counters.fizzles += 1; counters.reason = r)
	fsm.update(PoseClassifier.Pose.FIST, true, Vector2(0.5, 0.6), Vector2(0.5, 0.6), 0.1)
	var circle_pts := _make_circle(Vector2(0.5, 0.5), 0.15)
	for p in circle_pts:
		fsm.update(PoseClassifier.Pose.DRAWING, true, p, Vector2(0.5, 0.5), 0.03)
	fsm.update(PoseClassifier.Pose.PALM, true, circle_pts[circle_pts.size() - 1], Vector2(0.5, 0.5), 0.1)
	var fsm_ok: bool = counters.casts == 1
	if fsm_ok:
		pass_count += 1
	else:
		fail_count += 1
	print("%s fsm: 拳→画圆→掌 = %d 次施放 %d 次失败(%s)（期望 1/0）" % ["[PASS]" if fsm_ok else "[FAIL]", counters.casts, counters.fizzles, counters.reason])

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
