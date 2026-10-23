extends SceneTree
## 临时探针：摸清扩展符文注册后各形状的识别分数（写测试断言用），跑完即删。

static func _wave(center: Vector2, size: float) -> Array:
	var pts: Array = []
	for i in range(48):
		var t := float(i) / 47.0
		pts.append(center + Vector2((t - 0.5) * 2.6 * size, -sin(t * PI * 3.0) * size))
	return pts


static func _poly(vertices: Array) -> Array:
	var pts: Array = []
	for i in range(vertices.size() - 1):
		var a: Vector2 = vertices[i]
		var b: Vector2 = vertices[i + 1]
		var steps := maxi(8, int((b - a).length() / 0.02))
		for s in range(steps):
			pts.append(a.lerp(b, float(s) / float(steps)))
	pts.append(vertices[vertices.size() - 1])
	return pts


static func _circle(center: Vector2, r: float) -> Array:
	var pts: Array = []
	for i in range(40):
		var t := TAU * i / 39.0
		pts.append(center + Vector2(cos(t - PI / 2.0), sin(t - PI / 2.0)) * r)
	return pts


func _initialize() -> void:
	var ext := DollarRecognizer.new()
	ext.register_extended_runes()
	var cases := [
		["wave", _wave(Vector2(0.5, 0.5), 0.15)],
		["wave", _wave(Vector2(0.45, 0.55), 0.10)],
		["zigzag", _poly([Vector2(0.2, 0.2), Vector2(0.8, 0.2), Vector2(0.25, 0.8), Vector2(0.8, 0.8)])],
		["zigzag", _poly([Vector2(0.3, 0.3), Vector2(0.7, 0.3), Vector2(0.3, 0.7), Vector2(0.7, 0.7)])],
		["triangle", _poly([Vector2(0.5, 0.15), Vector2(0.85, 0.8), Vector2(0.15, 0.8), Vector2(0.5, 0.15)])],
		["circle", _circle(Vector2(0.4, 0.4), 0.15)],
		["slash", _poly([Vector2(0.2, 0.8), Vector2(0.8, 0.2)])],
	]
	var lines: Array = []
	lines.append("--- EXTENDED recognizer (wave in, triangle out) ---")
	for c in cases:
		var r := ext.recognize(c[1])
		lines.append("expect=%s got=%s score=%.3f" % [c[0], r.name, r.score])
	# 波形加抖动 + 旋转 15°
	var w := _wave(Vector2(0.5, 0.5), 0.15)
	var rot := deg_to_rad(15.0)
	var wobbled: Array = []
	for i in range(w.size()):
		var p: Vector2 = w[i].rotated(rot) + Vector2(sin(i * 1.7) * 0.008, cos(i * 2.3) * 0.008)
		wobbled.append(p)
	var r2 := ext.recognize(wobbled)
	lines.append("wave wobbled+rot15 got=%s score=%.3f" % [r2.name, r2.score])

	var dfl := DollarRecognizer.new()
	lines.append("--- DEFAULT recognizer ---")
	var rw := dfl.recognize(_wave(Vector2(0.5, 0.5), 0.15))
	lines.append("wave got=%s score=%.3f" % [rw.name, rw.score])
	var f := FileAccess.open("res://tests/probe_ext_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
	quit(0)
