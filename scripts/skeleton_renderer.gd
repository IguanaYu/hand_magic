class_name SkeletonRenderer
extends Node2D
## 在画面上绘制手部骨架与关键点（GDD §M0：骨架渲染）。
## 坐标：归一化 → 窗口空间（由 main 注入 view_size）。


const HAND_CONNECTIONS: PackedInt32Array = [
	0, 1, 1, 2, 2, 3, 3, 4,
	0, 5, 5, 6, 6, 7, 7, 8,
	5, 9, 9, 10, 10, 11, 11, 12,
	9, 13, 13, 14, 14, 15, 15, 16,
	13, 17,
	0, 17, 17, 18, 18, 19, 19, 20,
]

var view_size := Vector2(1280, 960)
var hands: Array = []
var state_color := Color(0.6, 0.85, 1.0, 0.55)
var show_skeleton := true


func set_hands(new_hands: Array) -> void:
	hands = new_hands
	queue_redraw()


func _draw() -> void:
	if not show_skeleton:
		return
	for hand in hands:
		var points: Array = hand.get("points", [])
		if points.size() < 21:
			continue
		var screen_pts: Array[Vector2] = []
		for p in points:
			screen_pts.append(Vector2(p.x * view_size.x, p.y * view_size.y))
		# 连线
		for i in range(0, HAND_CONNECTIONS.size(), 2):
			var a := screen_pts[HAND_CONNECTIONS[i]]
			var b := screen_pts[HAND_CONNECTIONS[i + 1]]
			draw_line(a, b, state_color * Color(1, 1, 1, 0.5), 3.0)
		# 关键点
		for p in screen_pts:
			draw_circle(p, 4.0, state_color)
		# 掌心锚点：高亮圆环
		var palm: Vector2 = hand.get("palm", Vector2(0.5, 0.5))
		var palm_screen := Vector2(palm.x * view_size.x, palm.y * view_size.y)
		draw_arc(palm_screen, 14.0, 0, TAU, 32, state_color, 2.5)
		# 食指尖：星标
		var tip: Vector2 = screen_pts[8]
		draw_arc(tip, 9.0, 0, TAU, 24, Color(1, 0.85, 0.3, 0.9), 2.0)
		var label: String = hand.get("label", "")
		if not label.is_empty():
			draw_string(ThemeDB.fallback_font, palm_screen + Vector2(18, -14), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, state_color)
