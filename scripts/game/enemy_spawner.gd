class_name EnemySpawner
extends Node2D
## 敌人生成器：间隔随时间收紧（2.5s → 0.8s），速度渐增，含存活上限。


signal enemy_spawned(e: GameEnemy)

var enemy_layer: Node2D
var view_size := Vector2(1280, 960)
var ward_center := Vector2(640, 480)
var ward_radius := 80.0
var max_alive := 22

var elapsed := 0.0
var active := true
var spawn_interval := 2.5

var _acc := 0.0


func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	spawn_interval = maxf(0.8, 2.5 - elapsed / 60.0)
	_acc += delta
	if _acc >= spawn_interval:
		_acc = 0.0
		if _alive_count() < max_alive:
			spawn()


func spawn() -> GameEnemy:
	var e := GameEnemy.new()
	e.ward_center = ward_center
	e.ward_radius = ward_radius
	e.speed = 42.0 + minf(55.0, elapsed * 0.55)
	e.position = _edge_position()
	enemy_layer.add_child(e)
	enemy_spawned.emit(e)
	return e


func _alive_count() -> int:
	var n := 0
	for e in enemy_layer.get_children():
		if e is GameEnemy and e.alive:
			n += 1
	return n


func _edge_position() -> Vector2:
	var side := randi() % 4
	var m := 50.0
	match side:
		0: return Vector2(randf_range(0, view_size.x), -m)
		1: return Vector2(view_size.x + m, randf_range(0, view_size.y))
		2: return Vector2(randf_range(0, view_size.x), view_size.y + m)
		_: return Vector2(-m, randf_range(0, view_size.y))


func reset() -> void:
	elapsed = 0.0
	_acc = 0.0
	spawn_interval = 2.5
	active = true
	for e in enemy_layer.get_children():
		if e is GameEnemy:
			e.queue_free()
