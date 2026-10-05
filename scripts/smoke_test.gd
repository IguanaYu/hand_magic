class_name SmokeTest
extends RefCounted
## M0 核心算法冒烟测试：$1 识别器 + 姿势分类器（合成数据）。
## 运行: godot --headless --path . -- --smoke-test
## 期望: 全部 PASS（合成轨迹识别率 100%）。


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
	]
	for pcase in pose_cases:
		var expected_pose: String = pcase[0]
		var lms: Array = pcase[1]
		var got: int = pc.classify(lms)
		var got_name: String = ["NONE", "FIST", "PALM", "DRAWING"][got]
		var ok2: bool = got_name == expected_pose
		if ok2:
			pass_count += 1
		else:
			fail_count += 1
		print("%s pose: expect=%s got=%s" % ["[PASS]" if ok2 else "[FAIL]", expected_pose, got_name])

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
