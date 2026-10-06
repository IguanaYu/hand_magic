class_name EnemyUnit3D
extends Node3D
## M1.6 战场敌人：地面单位（枪兵/掠夺者）+ 空军（维京战机/医疗运输机）。
## 地面：ADVANCE→HALT→FIRE/近身 MELEE；空军：FLY_IN→盘旋 STRAFE / 悬停空投 HOVER_DROP→FLY_OUT。
## 命中反馈：模型自发光闪 + 缩放冲击 + 音效；死亡：地面炸飞 / 空中爆炸后坠落起火。
## 素材面朝本地 +Z（Blender +Y → glTF +Z），_face_to 做 +PI 修正。

signal died(unit: EnemyUnit3D)
signal reached_melee(unit: EnemyUnit3D)
signal escaped(unit: EnemyUnit3D)  # 医疗船卸载完飞离（不计分不清波）

enum State { ADVANCE, HALT, FIRE, MELEE, DIE, FLY_IN, STRAFE, HOVER_DROP, FLY_OUT }

const UNIT_STATS := {
	"marine": {"hp": 30.0, "speed": 1.6, "stop_dist": 10.0, "score": 10, "scale": 1.4,
		"aim_h": 0.9, "shadow": 1.4,
		"fire_interval": 1.8, "burst": 3, "burst_gap": 0.12, "dmg": 4.0,
		"bullet_speed": 30.0, "hit_chance": 0.7, "miss_offset": 2.5},
	"marauder": {"hp": 100.0, "speed": 1.1, "stop_dist": 14.0, "score": 30, "scale": 1.4,
		"aim_h": 0.9, "shadow": 1.7,
		"fire_interval": 2.6, "burst": 1, "burst_gap": 0.0, "dmg": 12.0,
		"bullet_speed": 12.0, "hit_chance": 0.9, "miss_offset": 2.0, "big_bullet": true},
	"viking": {"hp": 130.0, "speed": 13.0, "score": 60, "scale": 6.5,
		"aim_h": 0.2, "shadow": 3.2, "flying": true, "fly_height": 7.5,
		"fire_interval": 2.3, "burst": 2, "burst_gap": 0.28, "dmg": 9.0,
		"bullet_speed": 15.0, "hit_chance": 0.8, "miss_offset": 2.5, "big_bullet": true},
	"medivac": {"hp": 160.0, "speed": 11.0, "score": 80, "scale": 4.0,
		"aim_h": 0.4, "shadow": 3.4, "flying": true, "fly_height": 10.0,
		"drops": 4, "drop_gap": 0.5},
}
const MELEE_DIST := 3.0
const MELEE_DMG := 15.0
const MELEE_INTERVAL := 1.2
const FROZEN_FACTOR := 0.45
## 维京只在玩家前方半圆盘旋（cos(a) 超过该值就折返）
const ORBIT_FRONT_COS := -0.15
const ORBIT_SPEED := 0.35

var unit_key := "marine"
var hp: float = 30.0
var max_hp: float = 30.0
var speed := 1.6
var stop_dist := 10.0
var score_value := 10
var alive := true
var flying := false
var frozen_t := 0.0
var stun_t := 0.0
var state: State = State.ADVANCE
var battlefield = null
## 两段路径：先横穿到中间集结点，再朝玩家推进（地面单位）
var has_waypoint := false
var waypoint := Vector3.ZERO
## 医疗船本趟空投数量（0=未指定，_ready 时取表值；战场依波次在 add_child 前覆写）
var drop_count := 0

var player_pos := Vector3(0.0, 0.0, 8.0)

var _ap: AnimationPlayer
var _model: Node3D
var _model_base_scale := Vector3.ONE
var _halt_t := 0.0
var _face_acc := 0.0
var _fire_cd := 1.0
var _burst_left := 0
var _burst_t := 0.0
var _melee_cd := 0.0
var _stats: Dictionary = {}
var _freeze_shell: MeshInstance3D
var _shadow: MeshInstance3D
var _flash_mats: Array[StandardMaterial3D] = []
var _hit_tw: Tween
var _punch_tw: Tween
# 飞行参数
var _fly_height := 8.0
var _fly_target := Vector3.ZERO
var _orbit_center := Vector3.ZERO
var _orbit_r := 20.0
var _orbit_a := PI
var _orbit_dir := 1.0
var _strafe_t := 3.0
var _drop_left := 4
var _drop_t := 0.6
var _exit_dir := Vector3.BACK
var _bob_phase := 0.0


func setup(p_key: String, p_player_pos: Vector3) -> void:
	unit_key = p_key
	player_pos = p_player_pos


func _ready() -> void:
	_stats = UNIT_STATS.get(unit_key, UNIT_STATS["marine"])
	flying = bool(_stats.get("flying", false))
	max_hp = _stats["hp"]
	hp = max_hp
	speed = _stats["speed"]
	stop_dist = float(_stats.get("stop_dist", 999.0))
	score_value = _stats["score"]
	if drop_count <= 0:
		drop_count = int(_stats.get("drops", 4))
	_drop_left = drop_count
	_fly_height = float(_stats.get("fly_height", 8.0))
	_bob_phase = randf() * TAU
	var ps: PackedScene = load("res://assets3d/units/%s.glb" % unit_key)
	_model = ps.instantiate()
	_model_base_scale = Vector3.ONE * float(_stats.get("scale", 1.4))
	_model.scale = _model_base_scale
	add_child(_model)
	_collect_flash_mats(_model)
	if not flying:
		_build_freeze_shell()
	_build_shadow()
	_ap = _find_anim_player(_model)
	if _ap != null:
		for anim_name in _ap.get_animation_list():
			var anim: Animation = _ap.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR
	if flying:
		state = State.FLY_IN
		_play("move")
	else:
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
	if flying:
		_process_flying(delta)
		return
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


## 维京：绕 player 前方半圆盘旋开火。center/r/a0/dir 由战场指定
func set_orbit(center: Vector3, r: float, a0: float, dir: float) -> void:
	_orbit_center = center
	_orbit_r = r
	_orbit_a = a0
	_orbit_dir = dir
	_fly_target = _orbit_pos(a0)


## 医疗船：飞到 p_xz 上空悬停卸载
func set_drop_zone(p_xz: Vector3) -> void:
	_fly_target = Vector3(p_xz.x, _fly_height, p_xz.z)


func aim_center() -> Vector3:
	return global_position + Vector3.UP * float(_stats.get("aim_h", 0.9))


# ---------- 地面行为 ----------

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


# ---------- 飞行行为 ----------

func _process_flying(delta: float) -> void:
	if _shadow != null:
		_shadow.global_position = Vector3(global_position.x, 0.03, global_position.z)
	var factor := FROZEN_FACTOR if frozen_t > 0.0 else 1.0
	match state:
		State.FLY_IN:
			var to := _fly_target - global_position
			var step := speed * factor * delta
			if to.length() <= step + 0.5:
				if unit_key == "medivac":
					state = State.HOVER_DROP
					_drop_t = 0.5
					_play("idle")
				else:
					state = State.STRAFE
					_play("attack")
			else:
				global_position += to.normalized() * step
				_face_to(to)
				_bank_toward(-_orbit_dir * 0.15, delta)
		State.STRAFE:
			_strafe_t -= delta
			if _strafe_t <= 0.0:
				_strafe_t = randf_range(2.5, 4.5)
				if randf() < 0.4:
					_orbit_dir *= -1.0
			var next_a := _orbit_a + _orbit_dir * ORBIT_SPEED * factor * delta
			# 折返约束：始终留在玩家前方半圆
			if cos(next_a) > ORBIT_FRONT_COS:
				_orbit_dir *= -1.0
			else:
				_orbit_a = next_a
			var target := _orbit_pos(_orbit_a)
			global_position = global_position.lerp(target, clampf(delta * 2.2, 0.0, 1.0))
			_face_to(_orbit_center - global_position)
			_bank_toward(-_orbit_dir * 0.3, delta)
			_update_fire(delta)
		State.HOVER_DROP:
			# 悬停微摆
			var t := Time.get_ticks_msec() * 0.001
			var bob := Vector3(sin(t * 1.1 + _bob_phase), sin(t * 1.7 + _bob_phase), cos(t * 0.9 + _bob_phase)) * 0.4
			global_position = _fly_target + bob
			_face_to(player_pos - global_position)
			if frozen_t > 0.0:
				return  # 冻结时暂停卸载
			_drop_t -= delta
			if _drop_left > 0 and _drop_t <= 0.0:
				_drop_left -= 1
				_drop_t = float(_stats.get("drop_gap", 0.5))
				if battlefield != null:
					battlefield.drop_marine(Vector3(global_position.x, 0.0, global_position.z))
			elif _drop_left <= 0:
				state = State.FLY_OUT
				var away := (global_position - player_pos)
				away.y = 0.0
				_exit_dir = (away.normalized() + Vector3.UP * 0.45).normalized()
				_play("move")
		State.FLY_OUT:
			global_position += _exit_dir * speed * 1.5 * delta
			_face_to(_exit_dir)
			if global_position.distance_to(player_pos) > 70.0:
				alive = false
				escaped.emit(self)
				queue_free()


func _orbit_pos(a: float) -> Vector3:
	return Vector3(
		_orbit_center.x + sin(a) * _orbit_r,
		_fly_height + sin(Time.get_ticks_msec() * 0.0017 + _bob_phase) * 0.45,
		_orbit_center.z + cos(a) * _orbit_r)


func _bank_toward(roll: float, delta: float) -> void:
	rotation.z = lerpf(rotation.z, roll, clampf(delta * 3.0, 0.0, 1.0))


# ---------- 通用 ----------

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
	if battlefield != null:
		battlefield.play_sfx("hit", aim_center(), -12.0)
	if hp <= 0.0:
		_die()
		return true
	return false


## 元素伤害入口（法术统一走这里）：默认=直伤+冰冻减速，行为与旧直伤路径一致；
## 马里奥单位（MarioEnemy3D）覆写实现元素克制表（GDD §3）。
## 返回实际伤害：>0=受伤数值（飘字用），0=无伤，<0=免疫（飘"免疫"）。
func apply_spell(element: String, dmg: float, _dir: Vector3 = Vector3.ZERO) -> float:
	take_damage(dmg)
	if element == "ice":
		apply_freeze(2.0 if unit_key == "marauder" else 3.0)
	return dmg


# ---------- 命中反馈（模型自发光闪 + 缩放冲击） ----------

func _collect_flash_mats(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.get_active_material(i)
			if m is StandardMaterial3D:
				var dup := (m as StandardMaterial3D).duplicate()
				dup.emission_enabled = true
				dup.emission = Color(1.0, 0.85, 0.65)
				dup.emission_energy_multiplier = 0.0
				mi.set_surface_override_material(i, dup)
				_flash_mats.append(dup)
	for c in node.get_children():
		_collect_flash_mats(c)


func _flash_hit() -> void:
	if _hit_tw != null and _hit_tw.is_valid():
		_hit_tw.kill()
	_hit_tw = create_tween()
	_hit_tw.tween_method(_set_flash_energy, 2.4, 0.0, 0.16).set_ease(Tween.EASE_OUT)
	# 模型缩放冲击（1.05 → 1.0）
	if _model != null:
		if _punch_tw != null and _punch_tw.is_valid():
			_punch_tw.kill()
			_model.scale = _model_base_scale
		_model.scale = _model_base_scale * 1.05
		_punch_tw = create_tween()
		_punch_tw.tween_property(_model, "scale", _model_base_scale, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_flash_energy(v: float) -> void:
	for m in _flash_mats:
		m.emission_energy_multiplier = v


func _build_freeze_shell() -> void:
	_freeze_shell = _make_shell(Color(0.55, 0.85, 1.0, 0.42), 1.05)
	_freeze_shell.visible = false


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


## 接地阴影：径向渐变黑圆片。地面单位贴脚下；飞行单位每帧投到地面
func _build_shadow() -> void:
	var size := float(_stats.get("shadow", 1.4)) * 2.0
	var alpha := 0.3 if flying else 0.5
	_shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	_shadow.mesh = q
	var gt := GradientTexture2D.new()
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, alpha), Color(0, 0, 0, 0)])
	g.offsets = PackedFloat32Array([0.35, 1.0])
	gt.gradient = g
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = gt
	mat.vertex_color_use_as_albedo = false
	_shadow.material_override = mat
	_shadow.rotation.x = -PI / 2.0
	_shadow.position = Vector3(0, 0.03, 0)
	add_child(_shadow)


func apply_freeze(sec: float) -> void:
	frozen_t = maxf(frozen_t, sec)
	if state == State.ADVANCE:
		_play("move")


## 风刃击退：沿方向推 dist 米，短暂硬直并打断射击（对空军无效）
func knockback(dir_xz: Vector3, dist: float) -> void:
	if not alive or flying:
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


# ---------- 开火 ----------

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
	var big := bool(_stats.get("big_bullet", unit_key == "marauder"))
	var from: Vector3
	if flying:
		from = global_position + _forward() * 2.2 - Vector3.UP * 0.4
	else:
		from = global_position + _forward() * 0.8 + Vector3.UP * 1.2
	battlefield.muzzle_flash(from, big)
	battlefield.play_sfx("shoot_big" if big else "shoot", from, -9.0)
	var target := player_pos  # 已是胸口高度（PLAYER_POS.y=1.65）
	if randf() > float(_stats.get("hit_chance", 0.7)):
		# 失准弹：横向偏移，擦过相机飞过
		var perp := Vector3.UP.cross(_forward()).normalized()
		target += perp * randf_range(-1.0, 1.0) * float(_stats.get("miss_offset", 2.0)) + Vector3(randf_range(-0.5, 0.5), 0.0, 0.0)
	battlefield.spawn_bullet(from, target, float(_stats.get("dmg", 4.0)), float(_stats.get("bullet_speed", 30.0)), big)


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


# ---------- 死亡 ----------

func _die() -> void:
	alive = false
	state = State.DIE
	died.emit(self)
	if _shadow != null:
		_shadow.visible = false
	if _freeze_shell != null:
		_freeze_shell.visible = false
	if flying:
		_die_flying()
	else:
		_die_ground()


func _die_ground() -> void:
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
	# 简版炸飞 + 原地翻滚缩小
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * -1.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position", global_position + dir * 3.0 + Vector3.UP * 1.5, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation:y", rotation.y + TAU, 0.55)
	tw.tween_property(self, "scale", scale * 0.4, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


func _die_flying() -> void:
	# 空中爆炸（火光 + 碎片），残骸旋转坠落，落地二次爆炸
	if battlefield != null:
		battlefield.air_boom(global_position)
	var smoke := CPUParticles3D.new()
	smoke.amount = 10
	smoke.lifetime = 0.6
	smoke.explosiveness = 0.2
	smoke.direction = Vector3.UP
	smoke.spread = 30.0
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 1.5
	smoke.scale_amount_min = 2.0
	smoke.scale_amount_max = 4.5
	smoke.color = Color(0.25, 0.22, 0.2, 0.8)
	var pm := SphereMesh.new()
	pm.radius = 0.08
	pm.height = 0.16
	smoke.mesh = pm
	add_child(smoke)
	smoke.emitting = true
	var fall_t := clampf(global_position.y * 0.16, 0.5, 1.1)
	var drift := Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", Vector3(global_position.x + drift.x, 0.4, global_position.z + drift.z), fall_t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "rotation:x", rotation.x + randf_range(-2.5, 2.5), fall_t)
	tw.tween_property(self, "rotation:z", rotation.z + randf_range(-2.5, 2.5), fall_t)
	tw.chain().tween_callback(func():
		smoke.emitting = false
		if battlefield != null:
			battlefield.ground_impact(global_position, true)
		queue_free())


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
