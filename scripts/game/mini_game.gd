class_name MiniGame
extends Node
## 守卫法阵迷你游戏（M0.5）：敌人爬向法阵，手势施法击杀。
## 状态：法阵 HP / 分数 / 存活时间 / 游戏结束与重开。


signal game_over(score: int)
signal state_dirty  # HUD/法阵 需要刷新

const WARD_HP_MAX := 10
const SCORE_PER_KILL := 10

var ward_hp := WARD_HP_MAX
var score := 0
var kills := 0
var elapsed := 0.0
var is_over := false
var best := 0

var spawner: EnemySpawner
var enemy_layer: Node2D
var hud: DebugHud


func setup(p_spawner: EnemySpawner, p_enemy_layer: Node2D, p_hud: DebugHud) -> void:
	spawner = p_spawner
	enemy_layer = p_enemy_layer
	hud = p_hud
	_wire_enemies()


func _process(delta: float) -> void:
	if is_over:
		return
	elapsed += delta


## 新生成的敌人挂接信号（生成器每次 spawn 后调用）
func register_enemy(e: GameEnemy) -> void:
	e.killed.connect(_on_enemy_killed)
	e.reached_ward.connect(_on_reached_ward)


func _wire_enemies() -> void:
	for e in enemy_layer.get_children():
		if e is GameEnemy:
			register_enemy(e)


func _on_enemy_killed(_pos: Vector2) -> void:
	if is_over:
		return
	kills += 1
	score += SCORE_PER_KILL
	state_dirty.emit()


func _on_reached_ward(_pos: Vector2) -> void:
	if is_over:
		return
	ward_hp -= 1
	state_dirty.emit()
	if ward_hp <= 0:
		_game_over()


func _game_over() -> void:
	is_over = true
	spawner.active = false
	best = maxi(best, score)
	game_over.emit(score)
	state_dirty.emit()


func restart() -> void:
	ward_hp = WARD_HP_MAX
	score = 0
	kills = 0
	elapsed = 0.0
	is_over = false
	spawner.reset()
	state_dirty.emit()


func alive_enemies() -> int:
	return spawner._alive_count()
