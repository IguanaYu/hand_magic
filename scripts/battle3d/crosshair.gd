class_name Crosshair
extends Control
## M1.2 准星：跟随鼠标，射线命中敌人时变红。自绘不拦截鼠标。


var on_enemy := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var p := get_viewport().get_mouse_position()
	var col := Color(1.0, 0.35, 0.3, 0.95) if on_enemy else Color(1, 1, 1, 0.85)
	draw_arc(p, 7.0, 0, TAU, 24, col, 2.0)
	draw_line(p - Vector2(14, 0), p - Vector2(4, 0), col, 2.0)
	draw_line(p + Vector2(4, 0), p + Vector2(14, 0), col, 2.0)
	draw_line(p - Vector2(0, 14), p - Vector2(0, 4), col, 2.0)
	draw_line(p + Vector2(0, 4), p + Vector2(0, 14), col, 2.0)
