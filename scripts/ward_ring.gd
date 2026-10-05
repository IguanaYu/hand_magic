class_name WardRing
extends Node2D
## 中央守护法阵（GDD §5.1：玩家 HP 载体，M0 为装饰 + 法力显示）。


var mana_ratio := 1.0
var hp_ratio := 1.0  # 法阵完整度（M0.5 游戏模式）
var view_size := Vector2(1280, 960)
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var center := view_size * 0.5
	var radius := minf(view_size.x, view_size.y) * 0.12
	# 外环颜色随 HP 从青转红
	var ring_col := Color(0.35, 0.8, 0.9, 0.7).lerp(Color(1.0, 0.3, 0.25, 0.85), 1.0 - hp_ratio)
	draw_arc(center, radius, 0, TAU, 96, ring_col, 3.0)
	# HP 弧（内圈，随受伤缩短）
	if hp_ratio > 0.01:
		draw_arc(center, radius * 0.7, -PI / 2, -PI / 2 + TAU * hp_ratio, 64,
			Color(ring_col, 0.95), 4.0)
	# 旋转虚线内环（呼吸感）
	var rot := _time * 0.6
	for i in range(12):
		var a0 := rot + TAU * i / 12.0
		draw_arc(center, radius * 0.82, a0, a0 + TAU / 18.0, 8, Color(0.95, 0.7, 0.25, 0.5), 2.0)
	# 反向旋转外刻环
	for i in range(24):
		var a1 := -rot * 0.4 + TAU * i / 24.0
		var dir := Vector2(cos(a1), sin(a1))
		draw_line(center + dir * (radius + 6), center + dir * (radius + 12), Color(0.35, 0.8, 0.9, 0.45), 2.0)
	# 法力弧（GDD：法力=法阵外环亮度/长度）
	if mana_ratio > 0.01:
		draw_arc(center, radius + 22, -PI / 2, -PI / 2 + TAU * mana_ratio, 96,
			Color(0.4, 0.95, 1.0, 0.85), 4.0)
