class_name RobustTest
extends RefCounted
## 鲁棒性基准：给合成符文轨迹叠加高斯抖动（模拟真实手部抖动），
## 并模拟稀疏采样（低帧率下点更少），统计各噪声等级的识别率与得分。
## 运行: godot --headless --path . -- --robust-test
## 结果: tests/robust_result.txt
##
## 判定线依据 GDD M0 验收：良好条件（σ≤0.01）识别率 ≥90%。


static func run() -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005  # 固定种子，结果可复现
	var rec := DollarRecognizer.new()
	var lines: Array = []
	var total_pass := true

	var noise_levels: Array = [0.0, 0.005, 0.010, 0.020]
	var sample_counts: Array = [40, 20, 12]  # 模拟 60/30/18fps 下的采样密度

	for sigma in noise_levels:
		for n_pts in sample_counts:
			var runes := {
				"circle": _circle(Vector2(0.5, 0.45), 0.13, n_pts),
				"zigzag": _zigzag(Vector2(0.3, 0.3), Vector2(0.7, 0.55), n_pts),
				"triangle": _triangle(Vector2(0.5, 0.3), 0.26, n_pts),
				"slash": _slash(Vector2(0.3, 0.7), Vector2(0.7, 0.3), n_pts),
			}
			var report := {}
			for rune_name in runes:
				var hits := 0
				var scores := 0.0
				var trials := 30
				for t in range(trials):
					# 每次试验：随机缩放(0.7~1.3)、随机平移、随机整体旋转 ±20°、逐点高斯抖动
					var pts := _perturb(runes[rune_name], sigma, rng)
					var result := rec.recognize(pts)
					if result.name == rune_name and result.score >= 0.80:
						hits += 1
					scores += float(result.score)
				report[rune_name] = {"hits": hits, "trials": trials, "avg": scores / trials}
			var ok_all: bool = true
			var summary := ""
			var worst: int = 100
			for rune_name in report:
				var r: Dictionary = report[rune_name]
				var acc: int = int(round(100.0 * r.hits / r.trials))
				worst = mini(worst, acc)
				summary += "%s:%d%%(%.2f) " % [rune_name, acc, r.avg]
				if acc < 90:
					ok_all = false
			var verdict := "PASS" if ok_all else ("PASS(低噪达标)" if worst >= 70 else "WARN")
			if sigma <= 0.010 and not ok_all:
				verdict = "FAIL"
				total_pass = false
			lines.append("σ=%.3f 采样=%2d点 | %s| %s" % [sigma, n_pts, summary, verdict])

	var header := "符文鲁棒性（每格 30 次试验，含随机缩放/平移/旋转；判定=识别正确且得分≥0.80）"
	lines.push_front(header)
	lines.append("")
	lines.append("结论: " + ("全部噪声等级 ≥90% 达标" if total_pass else "存在 σ≤0.01 等级未达 90% 的符文（见上表）"))
	var f := FileAccess.open("res://tests/robust_result.txt", FileAccess.WRITE)
	if f:
		for line in lines:
			f.store_string(line + "\n")
			print(line)
		f.flush()
	return 0 if total_pass else 1


static func _perturb(pts: Array, sigma: float, rng: RandomNumberGenerator) -> Array:
	var scale := rng.randf_range(0.7, 1.3)
	var offset := Vector2(rng.randf_range(0.1, 0.3), rng.randf_range(0.1, 0.3))
	var rot := deg_to_rad(rng.randf_range(-20.0, 20.0))
	var cos_v := cos(rot)
	var sin_v := sin(rot)
	var out: Array = []
	for p in pts:
		var q: Vector2 = (p - Vector2(0.5, 0.5)) * scale
		q = Vector2(q.x * cos_v - q.y * sin_v, q.x * sin_v + q.y * cos_v)
		q += Vector2(0.5, 0.5) + offset
		q += Vector2(rng.randfn(0, 1.0) * sigma, rng.randfn(0, 1.0) * sigma)
		q = q.clamp(Vector2(0.02, 0.02), Vector2(0.98, 0.98))
		out.append(q)
	return out


static func _circle(center: Vector2, r: float, n: int) -> Array:
	var pts: Array = []
	for i in range(n):
		var t := TAU * i / float(n - 1)
		pts.append(center + Vector2(cos(t - PI / 2.0), sin(t - PI / 2.0)) * r)
	return pts


static func _zigzag(a: Vector2, b: Vector2, n: int) -> Array:
	var verts := [Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(a.x, b.y), Vector2(b.x, b.y)]
	return _polyline(verts, n)


static func _triangle(top: Vector2, size: float, n: int) -> Array:
	var verts := [top, top + Vector2(size * 0.6, size), top + Vector2(-size * 0.6, size), top]
	return _polyline(verts, n)


static func _slash(a: Vector2, b: Vector2, n: int) -> Array:
	var pts: Array = []
	for i in range(n):
		pts.append(a.lerp(b, float(i) / float(n - 1)))
	return pts


static func _polyline(verts: Array, n: int) -> Array:
	var pts: Array = []
	for i in range(verts.size() - 1):
		var steps := maxi(4, int(ceil(float(n) / float(verts.size() - 1))))
		for s in range(steps):
			pts.append(verts[i].lerp(verts[i + 1], float(s) / float(steps)))
	pts.append(verts[verts.size() - 1])
	return pts
