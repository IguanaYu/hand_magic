class_name EnemyUnit3D
extends Node3D
## M1.1 战场敌人：GLB 模型 + AnimationPlayer + 状态机。
## ADVANCE 走向玩家 → HALT 举枪过渡 → FIRE 开火(M1.2) → 近身 MELEE(M1.2)。
## 死亡 = 简版炸飞演出（M1.5 打磨）。素材面朝本地 +Z（Blender +Y → glTF +Z）。

signal died(unit: EnemyUnit3D)
signal reached_melee(unit: EnemyUnit3D)

enum State { ADVANCE, HALT, FIRE, MELEE, DIE }

const UNIT_STATS := {
	"marine": {"hp": 30.0, "speed": 1.6, "stop_dist": 10.0, "score": 10,
		"fire_interval": 1.8, "burst": 3, "burst_gap": 0.12, "dmg": 4.0,
		"bullet_speed": 30.0, "hit_chance": 0.7, "miss_offset": 2.5},
	"marauder": {"hp": 100.0, "speed": 1.1, "stop_dist": 14.0, "score": 30,
		"fire_interval": 2.6, "burst": 1, "burst_gap": 0.0, "dmg": 12.0,
		"bullet_speed": 12.0, "hit_chance": 0.9, "miss_offset": 2.0},
}
const MELEE_DIST := 3.0
const MELEE_DMG := 15.0
const MELEE_INTERVAL := 1.2
const UNIT_SCALE := 1.4
const FROZEN_FACTOR := 0.45

var unit_key := "marine"
var hp: float = 30.0
var max_hp: float = 30.0
var speed := 1.6
var stop_dist := 10.0
var score_value := 10
var alive := true
var frozen_t := 0.0
var stun_t := 0.0
var state: State = State.ADVANCE
var battlefield = null
## 两段路径（M1 调试版）：先横穿到中间集结点，再朝玩家推进
var has_waypoint := false
var waypoint := Vector3.ZERO

var player_pos := Vector3(0.0, 0.0, 8.0)

var _ap: AnimationPlayer
var _halt_t := 0.0
var _face_acc := 0.0
var _fire_cd := 1.0
var _burst_left := 0
var _burst_t := 0.0
var _melee_cd := 0.0
var _stats: Dictionary = {}


func setup(p_key: String, p_player_pos: Vector3) -> void:
	unit_key = p_key
	player_pos = p_player_pos


func _ready() -> void:
	_stats = UNIT_STATS.get(unit_key, UNIT_STATS["marine"])
	max_hp = _stats["hp"]
	hp = max_hp
	speed = _stats["speed"]
	stop_dist = _stats["stop_dist"]
	score_value = _stats["score"]
	var ps: PackedScene = load("res://assets3d/units/%s.glb" % unit_key)
	var model := ps.instantiate()
	model.scale = Vector3.ONE * UNIT_SCALE
	add_child(model)
	_build_shells()
	_ap = _find_anim_player(model)
	if _ap != null:
		for anim_name in _ap.get_animation_list():
			var anim: Animation = _ap.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR
	_play("move")
	_face_player()
	# 同批生成的敌人动画错峰，避免齐步走
	if _ap != null:
		_ap.advance(randf() * 0.6)


func _process(delta: float) -> void:
	if not alive:
		return
	if stun_t > 0.0:
		stun_t -= delta
		return
	if frozen_t > 0.0:
		frozen_t -= delta
	if _freeze_shell != null:
		_freeze_shell.visible = frozen_t > 0.0
	match state:
		State.ADVANCE:
			_advance(delta)
		State.HALT:
			_halt_t -= delta
			if _halt_t <= 0.0:
				state = State.FIRE
				_play("attack")
		State.FIRE:
			_update_fire(delta)
		State.MELEE:
			_update_melee(delta)
	_face_acc += delta
	if _face_acc >= 0.3:
		_face_acc = 0.0
		# 集结段面向行进方向，接敌段面向玩家
		if has_waypoint:
			_face_to(waypoint - global_position)
		else:
			_face_to(player_pos - global_position)


func set_waypoint(p: Vector3) -> void:
	waypoint = p
	has_waypoint = true


func _advance(delta: float) -> void:
	var factor := FROZEN_FACTOR if frozen_t > 0.0 else 1.0
	# 第一段：先走向中间集结点（不理会停距）
	if has_waypoint:
		var to_wp := waypoint - global_position
		to_wp.y = 0.0
		if to_wp.length() <= 1.2:
			has_waypoint = false
		else:
			global_position += to_wp.normalized() * speed * factor * delta
			return
	# 第二段：朝玩家推进
	var to_player := player_pos - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist <= stop_dist:
		state = State.HALT
		_halt_t = 0.4
		_play("idle")
		return
	if dist <= MELEE_DIST:
		state = State.MELEE
		_play("attack")
		reached_melee.emit(self)
		return
	global_position += to_player.normalized() * speed * factor * delta


func _face_to(d: Vector3) -> void:
	d.y = 0.0
	if d.length_squared() > 0.001:
		# 模型正面朝本地 -Z（Blender "面向+Y" 经 glTF 转换 → -Z），故 +PI 修正
		rotation.y = atan2(d.x, d.z) + PI


func _face_player() -> void:
	_face_to(player_pos - global_position)


func take_damage(dmg: float) -> bool:
	if not alive:
		return false
	hp -= dmg
	_flash_hit()
	if hp <= 0.0:
		_die()
		return true
	return false


# ---------- 受击/冻结外观壳（M1.5） ----------

var _hit_shell: MeshInstance3D
var _freeze_shell: MeshInstance3D


func _build_shells() -> void:
	_hit_shell = _make_shell(Color(1, 1, 1, 0.6), 1.03)
	_freeze_shell = _make_shell(Color(0.55, 0.85, 1.0, 0.42), 1.05)


func _make_shell(col: Color, scl: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.05
	sphere.height = 2.1
	mi.mesh = sphere
	mi.position = Vector3.UP * 0.95
	mi.scale = Vector3(0.95, 1.0, 0.95) * scl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	mi.visible = false
	add_child(mi)
	return mi


func _flash_hit() -> void:
	if _hit_shell == null:
		return
	_hit_shell.visible = true
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(func(): _hit_shell.visible = false)


func apply_freeze(sec: float) -> void:
	frozen_t = maxf(frozen_t, sec)
	if state == State.ADVANCE:
		_play("move")


## 风刃击退：沿方向推 dist 米，短暂硬直并打断射击
func knockback(dir_xz: Vector3, dist: float) -> void:
	if not alive:
		return
	stun_t = 0.4
	if state == State.FIRE or state == State.HALT:
		state = State.ADVANCE
		_play("move")
	_fire_cd = maxf(_fire_cd, 0.6)
	var d := dir_xz
	d.y = 0.0
	if d.length_squared() > 0.001:
		d = d.normalized()
		var tw := create_tween()
		tw.tween_property(self, "global_position", global_position + d * dist, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ---------- 开火（M1.2） ----------

func _update_fire(delta: float) -> void:
	if frozen_t > 0.0:
		return  # 冰冻期间停止射击
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_shoot()
			_burst_left -= 1
			_burst_t = float(_stats.get("burst_gap", 0.12))
		return
	_fire_cd -= delta
	if _fire_cd <= 0.0:
		_burst_left = int(_stats.get("burst", 1))
		_burst_t = 0.0
		_fire_cd = float(_stats.get("fire_interval", 1.8))


func _shoot() -> void:
	if battlefield == null:
		return
	var from := global_position + _forward() * 0.8 + Vector3.UP * 1.2
	if battlefield != null:
		battlefield.muzzle_flash(from, unit_key == "marauder")
	var target := player_pos  # 已是胸口高度（PLAYER_POS.y=1.65）
	if randf() > float(_stats.get("hit_chance", 0.7)):
		# 失准弹：横向偏移，擦过相机飞过
		var perp := Vector3.UP.cross(_forward()).normalized()
		target += perp * randf_range(-1.0, 1.0) * float(_stats.get("miss_offset", 2.0)) + Vector3(randf_range(-0.5, 0.5), 0.0, 0.0)
	battlefield.spawn_bullet(from, target, float(_stats.get("dmg", 4.0)), float(_stats.get("bullet_speed", 30.0)), unit_key == "marauder")


func _update_melee(delta: float) -> void:
	_melee_cd -= delta
	if _melee_cd <= 0.0:
		_melee_cd = MELEE_INTERVAL
		if battlefield != null:
			battlefield.player_hit(MELEE_DMG)


func _forward() -> Vector3:
	var d := player_pos - global_position
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.001 else Vector3.FORWARD


func _die() -> void:
	alive = false
	state = State.DIE
	died.emit(self)
	# 死亡粒子（CarBot 风爆散）
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.emitting = false
	burst.amount = 16
	burst.lifetime = 0.55
	burst.explosiveness = 1.0
	burst.direction = Vector3.UP
	burst.spread = 180.0
	burst.initial_velocity_min = 2.0
	burst.initial_velocity_max = 6.0
	burst.gravity = Vector3(0, -9.0, 0)
	burst.scale_amount_min = 1.5
	burst.scale_amount_max = 3.5
	burst.color = Color(0.95, 0.75, 0.25, 0.95)
	var pm := SphereMesh.new()
	pm.radius = 0.06
	pm.height = 0.12
	burst.mesh = pm
	add_child(burst)
	burst.restart()
	# 简版炸飞（M1.5 加粒子/焦痕）
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * -1.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position", global_position + dir * 3.0 + Vector3.UP * 1.5, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation:y", rotation.y + TAU, 0.55)
	tw.tween_property(self, "scale", scale * 0.4, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


func _play(clip: String) -> void:
	if _ap == null:
		return
	var name := "%s_%s" % [unit_key, clip]
	if _ap.has_animation(name):
		_ap.play(name)


func state_name() -> String:
	return State.keys()[state]


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r: AnimationPlayer = _find_anim_player(c)
		if r != null:
			return r
	return null
