class_name DollarRecognizer
extends RefCounted
## $1 Unistroke Recognizer（GDD §3.4），Wobbrock & Li 2007。
## 输入归一化坐标轨迹，返回 {name, score}。
## 圆形符文额外叠加几何特征（闭合度+圆度），弥补 $1 对闭合曲线的不稳定。


const N_POINTS := 64
const SQUARE := 250.0
const HALF_DIAGONAL := 0.5 * sqrt(2.0 * SQUARE * SQUARE)
const ANGLE_RANGE := deg_to_rad(45.0)
const ANGLE_PRECISION := deg_to_rad(2.0)
const GSS_PHI := 0.5 * (-1.0 + sqrt(5.0))

var templates: Array[Dictionary] = []  # [{name: String, points: Array[Vector2]}]


func _init() -> void:
	add_polyline_template("slash", [Vector2(0.15, 0.85), Vector2(0.85, 0.15)])
	add_polyline_template("zigzag", [
		Vector2(0.1, 0.2), Vector2(0.9, 0.2), Vector2(0.1, 0.8), Vector2(0.9, 0.8)
	])
	add_polyline_template("triangle", [
		Vector2(0.5, 0.1), Vector2(0.9, 0.9), Vector2(0.1, 0.9), Vector2(0.5, 0.1)
	])
	add_polyline_template("circle", _circle_points())


func add_polyline_template(p_name: String, pts: Array) -> void:
	var densified := _densify(pts)
	templates.append({
		"name": p_name,
		"points": _normalize_for_matching(densified),
	})


func _circle_points() -> Array:
	var pts: Array = []
	for i in range(33):
		var t := TAU * i / 32.0
		pts.append(Vector2(0.5 + 0.4 * cos(t - PI / 2.0), 0.5 + 0.4 * sin(t - PI / 2.0)))
	return pts


func _densify(pts: Array) -> Array[Vector2]:
	# 折线按长度均匀插值，保证模板点密度一致
	var out: Array[Vector2] = []
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var steps := maxi(2, int(ceil((b - a).length() / 0.03)))
		for s in range(steps):
			out.append(a.lerp(b, float(s) / float(steps)))
	out.append(pts[pts.size() - 1])
	return out


## 主入口：points 为归一化坐标（0~1）的原始轨迹
func recognize(points: Array) -> Dictionary:
	if points.size() < 8:
		return {"name": "", "score": 0.0, "reason": "轨迹太短"}
	var path_length := _path_length(points)
	if path_length < 0.08:
		return {"name": "", "score": 0.0, "reason": "轨迹太短"}
	var circle_like := _circle_likeness(points)
	var straight_like := _straight_likeness(points)

	# 直线度前置判定：$1 对直线模板的贪心匹配天然不稳定（退化形状），
	# 一笔直挥（直线度≥阈值）直接判 slash，与圆形前置判定同理
	if straight_like >= 0.0:
		return {"name": "slash", "score": straight_like}

	var candidate := _normalize_for_matching(points)
	var best_name := ""
	var best_d := INF
	for t in templates:
		if t.name == "circle" and circle_like < 0.25:
			continue  # 明显不是闭合曲线时不参与匹配
		var d := _distance_at_best_angle(candidate, t.points, -ANGLE_RANGE, ANGLE_RANGE, ANGLE_PRECISION)
		if d < best_d:
			best_d = d
			best_name = t.name

	var score := 1.0 - best_d / HALF_DIAGONAL
	# 圆形几何覆盖：闭合度+圆度都极高时才强制判圆（三角/矩形等闭合图形圆度只有 ~0.77）
	if circle_like > 0.85 and best_name != "circle":
		best_name = "circle"
		score = maxf(score, circle_like)
	elif best_name == "circle":
		score = maxf(score, 0.8 * circle_like + 0.2 * score)
	return {"name": best_name, "score": clampf(score, 0.0, 1.0)}


## 直线度判定：路径够长（≥0.15）、首尾够开（弦长≥0.12）、够直（最大垂偏 <8% 路径长）。
## 判据用路径长而非弦长做分母：抖动会虚增路径长度，弦长/路径比对高密度采样不友好。
## 返回 slash 得分（0.85~1.0），不满足返回 -1（不适用）
func _straight_likeness(points: Array) -> float:
	var path_len := _path_length(points)
	if path_len < 0.15:
		return -1.0
	var first: Vector2 = points[0]
	var last: Vector2 = points[points.size() - 1]
	var chord := (last - first).length()
	if chord < 0.12:
		return -1.0
	var dir := (last - first) / maxf(chord, 1e-9)
	var max_dev := 0.0
	for p in points:
		var dev: float = absf((p - first).cross(dir))
		max_dev = maxf(max_dev, dev)
	var dev_ratio := max_dev / path_len
	if dev_ratio >= 0.08:
		return -1.0
	return maxf(0.85, 1.0 - dev_ratio * 2.0)


func _circle_likeness(points: Array) -> float:
	var resampled := _resample(points, 64)
	var closure := (resampled[0] - resampled[resampled.size() - 1]).length() / maxf(_path_length(resampled), 1e-9)
	var centroid := Vector2.ZERO
	for p in resampled:
		centroid += p
	centroid /= float(resampled.size())
	var r_mean := 0.0
	for p in resampled:
		r_mean += (p - centroid).length()
	r_mean /= float(resampled.size())
	if r_mean < 0.005:
		return 0.0
	var r_var := 0.0
	for p in resampled:
		r_var += pow((p - centroid).length() - r_mean, 2.0)
	r_var = sqrt(r_var / float(resampled.size()))
	var roundness := 1.0 - clampf(r_var / (0.5 * r_mean), 0.0, 1.0)
	var closure_score := 1.0 - clampf(closure / 0.25, 0.0, 1.0)
	return clampf(0.5 * roundness + 0.5 * closure_score, 0.0, 1.0)


# ---------------- $1 标准步骤 ----------------

func _resample(points: Array, n: int) -> Array[Vector2]:
	var src: Array[Vector2] = []
	src.assign(points)
	var i := 0
	var total := _path_length(src)
	if total <= 0.0:
		return src
	var interval := total / float(n - 1)
	var acc := 0.0
	var result: Array[Vector2] = [src[0]]
	while i < src.size() - 1:
		var d := (src[i + 1] - src[i]).length()
		# result.size() < n 防御 + 插入后 i+=1（q 成为新起点）：
		# 无 i+=1 时下一轮会重复比较"已消耗段"，浮点边界上无限生成重复点
		if acc + d >= interval and result.size() < n:
			var t := (interval - acc) / d
			var q := src[i] + (src[i + 1] - src[i]) * t
			result.append(q)
			src.insert(i + 1, q)
			acc = 0.0
			i += 1
		else:
			acc += d
			i += 1
	# 收尾补点
	while result.size() < n:
		result.append(src[src.size() - 1])
	result.resize(n)
	return result


func _indicative_angle(points: Array[Vector2]) -> float:
	var centroid := Vector2.ZERO
	for p in points:
		centroid += p
	centroid /= float(points.size())
	return atan2(centroid.y - points[0].y, centroid.x - points[0].x)


func _rotate_by(points: Array[Vector2], radians: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cos_v := cos(radians)
	var sin_v := sin(radians)
	for p in points:
		out.append(Vector2(
			p.x * cos_v - p.y * sin_v,
			p.x * sin_v + p.y * cos_v
		))
	return out


func _scale_to_square(points: Array[Vector2]) -> Array[Vector2]:
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for p in points:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	var size := Vector2(max_v.x - min_v.x, max_v.y - min_v.y)
	size.x = maxf(size.x, 1e-6)
	size.y = maxf(size.y, 1e-6)
	var out: Array[Vector2] = []
	for p in points:
		out.append(Vector2(
			(p.x - min_v.x) / size.x * SQUARE,
			(p.y - min_v.y) / size.y * SQUARE
		))
	return out


func _translate_to_origin(points: Array[Vector2]) -> Array[Vector2]:
	var centroid := Vector2.ZERO
	for p in points:
		centroid += p
	centroid /= float(points.size())
	var out: Array[Vector2] = []
	for p in points:
		out.append(p - centroid)
	return out


func _normalize_for_matching(points: Array) -> Array[Vector2]:
	var pts := _resample(points, N_POINTS)
	var rad := _indicative_angle(pts)
	pts = _rotate_by(pts, -rad)
	pts = _scale_to_square(pts)
	return _translate_to_origin(pts)


func _path_distance_greedy(a: Array[Vector2], b: Array[Vector2]) -> float:
	# $1 原始贪心匹配（非 Protractor 版本）
	var d := 0.0
	for i in range(a.size()):
		var matched := INF
		for j in range(b.size()):
			var dist := (a[i] - b[j]).length()
			if dist < matched:
				matched = dist
		d += matched
	return d / float(a.size())


func _distance_at_best_angle(points: Array[Vector2], template: Array[Vector2], a0: float, b0: float, threshold: float) -> float:
	var x1 := GSS_PHI * a0 + (1.0 - GSS_PHI) * b0
	var f1 := _distance_at_angle(points, template, x1)
	var x2 := (1.0 - GSS_PHI) * a0 + GSS_PHI * b0
	var f2 := _distance_at_angle(points, template, x2)
	var a := a0
	var b := b0
	while absf(b - a) > threshold:
		if f1 < f2:
			b = x2
			x2 = x1
			f2 = f1
			x1 = GSS_PHI * a + (1.0 - GSS_PHI) * b
			f1 = _distance_at_angle(points, template, x1)
		else:
			a = x1
			x1 = x2
			f1 = f2
			x2 = (1.0 - GSS_PHI) * a + GSS_PHI * b
			f2 = _distance_at_angle(points, template, x2)
	return minf(f1, f2)


func _distance_at_angle(points: Array[Vector2], template: Array[Vector2], theta: float) -> float:
	var rotated := _rotate_by(points, theta)
	return _path_distance_greedy(rotated, template)


func _path_length(points: Array) -> float:
	var d := 0.0
	for i in range(points.size() - 1):
		d += (points[i + 1] - points[i]).length()
	return d
