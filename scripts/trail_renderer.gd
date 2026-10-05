class_name TrailRenderer
extends Node2D
## 画符轨迹拖尾（GDD §8.1：拖尾即输入反馈本体）。
## 双层绘制：宽半透明辉光 + 细亮芯线，识别倾向越高颜色越亮。


var view_size := Vector2(1280, 960)
var points: Array = []           # 归一化坐标
var fading := false
var _fade := 1.0


func _process(delta: float) -> void:
	if fading:
		_fade = maxf(0.0, _fade - delta * 2.2)
		if _fade <= 0.0:
			points.clear()
			fading = false
	queue_redraw()


func set_points(norm_points: Array) -> void:
	points = norm_points
	fading = false
	_fade = 1.0


func begin_fade() -> void:
	if points.size() > 0:
		fading = true


func clear() -> void:
	points.clear()
	fading = false
	_fade = 1.0


func _draw() -> void:
	if points.size() < 2:
		return
	var screen: Array[Vector2] = []
	for p in points:
		screen.append(Vector2(p.x * view_size.x, p.y * view_size.y))

	var base := Color(0.4, 0.95, 1.0)
	# 外辉光
	for i in range(screen.size() - 1):
		var t := float(i) / float(screen.size() - 1)
		var w := lerpf(4.0, 14.0, t) * _fade
		draw_line(screen[i], screen[i + 1], Color(base, 0.25 * _fade), w)
	# 芯线
	for i in range(screen.size() - 1):
		var t := float(i) / float(screen.size() - 1)
		var w := lerpf(1.5, 4.5, t) * _fade
		draw_line(screen[i], screen[i + 1], Color(base, 0.95 * _fade), w)
	# 指尖位置光点
	var head: Vector2 = screen[screen.size() - 1]
	if not fading:
		draw_circle(head, 7.0, Color(1, 1, 1, 0.9))
		draw_arc(head, 12.0, 0, TAU, 24, Color(base, 0.8), 2.0)
