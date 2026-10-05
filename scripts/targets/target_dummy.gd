class_name TargetDummy
extends Node2D
## 练习靶（M0 验收辅助）：发光水晶，被法术命中破碎，2.5s 后重生。


signal broken(pos: Vector2)

var radius := 42.0
var alive := true
var frozen := false
var _respawn := 0.0
var _flash := 0.0
var _time := 0.0

var _crystal_pts: PackedVector2Array


func _init() -> void:
	# 六边形水晶轮廓
	for i in range(6):
		var a := TAU * i / 6.0 + PI / 6.0
		_crystal_pts.append(Vector2(cos(a), sin(a)) * 1.0)


func _ready() -> void:
	_add_sparks()


var _sparks: CPUParticles2D


func _add_sparks() -> void:
	_sparks = CPUParticles2D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.amount = 26
	_sparks.lifetime = 0.6
	_sparks.explosiveness = 1.0
	_sparks.direction = Vector2.UP
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 120.0
	_sparks.initial_velocity_max = 320.0
	_sparks.gravity = Vector2(0, 420)
	_sparks.scale_amount_min = 2.0
	_sparks.scale_amount_max = 5.0
	_sparks.color = Color(0.55, 0.95, 1.0, 0.95)
	add_child(_sparks)


func _process(delta: float) -> void:
	_time += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
	if not alive:
		_respawn -= delta
		if _respawn <= 0.0:
			alive = true
			frozen = false
	queue_redraw()


func hit() -> bool:
	if not alive:
		return false
	alive = false
	_respawn = 2.5
	_sparks.restart()
	broken.emit(global_position)
	return true


func draw_target() -> void:
	# 供全局绘制调用（本节点自行绘制时也走这里）
	pass


func _draw() -> void:
	if not alive:
		return
	var col := Color(0.5, 0.9, 1.0, 0.85)
	if frozen:
		col = Color(0.7, 0.85, 1.0, 0.95)
	if _flash > 0.0:
		col = col.lerp(Color.WHITE, _flash)
	var pts := PackedVector2Array()
	for p in _crystal_pts:
		pts.append(p * radius * (1.0 + 0.05 * sin(_time * 2.5)))
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.28))
	draw_polyline(pts, col, 3.0, true)
	draw_arc(Vector2.ZERO, radius * 0.5, 0, TAU, 24, Color(col, 0.6), 2.0)
	# 底部光晕
	draw_circle(Vector2.ZERO, radius * 0.22, Color(1, 1, 1, 0.5))
