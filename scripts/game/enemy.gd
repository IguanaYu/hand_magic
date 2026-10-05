class_name GameEnemy
extends Node2D
## 蚀影（GDD §5.2 杂兵）：从屏幕边缘爬向中央法阵，触碰扣血自爆。


signal reached_ward(pos: Vector2)
signal killed(pos: Vector2)

var alive := true
var speed := 50.0
var radius := 24.0
var frozen_t := 0.0
var ward_center := Vector2(640, 480)
var ward_radius := 80.0

var _t := 0.0
var _burst: CPUParticles2D


func _ready() -> void:
	_burst = CPUParticles2D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 18
	_burst.lifetime = 0.5
	_burst.explosiveness = 1.0
	_burst.direction = Vector2.UP
	_burst.spread = 180.0
	_burst.initial_velocity_min = 80.0
	_burst.initial_velocity_max = 240.0
	_burst.gravity = Vector2(0, 300)
	_burst.scale_amount_min = 2.0
	_burst.scale_amount_max = 4.5
	_burst.color = Color(0.85, 0.3, 0.55, 0.95)
	add_child(_burst)


func _process(delta: float) -> void:
	if not alive:
		return
	_t += delta
	if frozen_t > 0.0:
		frozen_t -= delta
	var factor := 0.45 if frozen_t > 0.0 else 1.0
	var to_center: Vector2 = ward_center - global_position
	if to_center.length() < ward_radius + radius * 0.5:
		reached_ward.emit(global_position)
		_explode(false)
		return
	global_position += to_center.normalized() * speed * factor * delta
	queue_redraw()


func hit() -> bool:
	if not alive:
		return false
	_explode(true)
	return true


func _explode(scored: bool) -> void:
	alive = false
	_burst.restart()
	if scored:
		killed.emit(global_position)
	# 粒子播完再消失
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(queue_free)


func _draw() -> void:
	if not alive:
		return
	var pts := PackedVector2Array()
	for i in range(10):
		var a := TAU * i / 10.0
		var r: float = radius * (1.0 + 0.12 * sin(_t * 3.0 + i * 1.7))
		pts.append(Vector2(cos(a), sin(a)) * r)
	var body := Color(0.22, 0.09, 0.32, 0.88)
	var edge := Color(0.85, 0.25, 0.35, 0.9)
	if frozen_t > 0.0:
		body = Color(0.35, 0.55, 0.9, 0.85)
		edge = Color(0.7, 0.9, 1.0, 0.9)
	draw_colored_polygon(pts, body)
	draw_polyline(pts, edge, 2.5)
	draw_circle(Vector2.ZERO, radius * 0.3, Color(1.0, 0.35, 0.25, 0.95))
	draw_circle(Vector2(-radius * 0.25, -radius * 0.15), 3.5, Color(1, 0.9, 0.8))
	draw_circle(Vector2(radius * 0.25, -radius * 0.15), 3.5, Color(1, 0.9, 0.8))
