class_name Battlefield3D
extends Node3D
## M1.6 3D 战场：环境（噪声草地/线性雾/远景岩环/阵地布景）+ 波次刷怪
## （地面小队编队进场 + 维京战机盘旋 + 医疗船空投）+ 命中反馈（顿帧/音效/焦痕/尘土）。

const PLAYER_POS := Vector3(0.0, 1.65, 8.0)
const GROUND_SIZE := 160.0
const GROUND_COLOR := Color(0.36, 0.52, 0.30)
const BUILDING_SCALE := 2.5
## 布景随机种子（固定 → 每局布局一致）
const PROP_SEED := 20261005

const PATH_UNITS := "res://assets3d/units/%s.glb"
const PATH_BUILDINGS := "res://assets3d/buildings/%s.glb"
const PATH_ENV := "res://assets3d/env/%s.glb"

const SPAWN_INTERVAL := 2.5
const MAX_ALIVE := 20
const FIRST_WAVE_DELAY := 3.0
const WAVE_CLEAR_BONUS := 50
## 地面小队规模区间（同队同侧同集结点，成纵队进场）
const SQUAD_MIN := 3
const SQUAD_SPREAD := 3
## 同名音效最小间隔（ms），防止叠爆音
const SFX_GAP := {
	"shoot": 50, "shoot_big": 80, "hit": 45, "thump": 70,
	"boom": 60, "boom_big": 90, "flyby": 200, "zap": 60,
}

signal wave_started(n: int)
signal wave_cleared(n: int)

enum WavePhase { INTERMISSION, SPAWNING, CLEARING }

var camera: Camera3D
var ui_layer: CanvasLayer
var enemy_layer: Node3D
var bullet_layer: Node3D
var fx_layer: Node3D
var hud3d: BattleHud
var crosshair: Crosshair
var spell_caster: SpellCaster3D
var shield: Shield3D

var player_hp := 100.0
var score := 0
var kills := 0
var is_over := false
var enemies: Array[EnemyUnit3D] = []
var spawning := true
## 护盾挡弹开关（main.gd 依据手势/右键驱动）
var shield_up := false
## 测试钩子：无视手势强制开盾
var shield_force := false
var mana_ratio := 0.0:
	set(v):
		mana_ratio = v
		if hud3d != null:
			hud3d.mana_ratio = v

var _spawn_acc := 0.0
var _spawn_count := 0
var _flash: ColorRect
var _overlay: ColorRect
var _overlay_label: Label
var _banner: Label
var _shake_t := 0.0

# 波次状态
var wave_n := 0
var phase: WavePhase = WavePhase.INTERMISSION
var _queue: Array[String] = []
var _phase_t := FIRST_WAVE_DELAY
var _spawn_interval := SPAWN_INTERVAL
var best_score := 0
var _drops_per_medivac := 4

# 小队刷怪状态
var _squad_side := 1.0
var _squad_left := 0
var _squad_idx := 0
var _squad_lane := Vector3.ZERO
var _squad_waypoint := Vector3.ZERO
var _air_warned := {"viking": false, "medivac": false}

# 音效池 + 击杀顿帧
var _sfx_pool: Array[AudioStreamPlayer3D] = []
var _sfx_cursor := 0
var _sfx_last := {}
var _hitstop_cd := 0.0

const SPELL_KEYS := {
	KEY_1: "fireball", KEY_2: "lightning", KEY_3: "ice_field",
	KEY_4: "wind_blade", KEY_5: "quick_shot",
}


func _ready() -> void:
	_build_environment()
	_build_lights()
	_build_ground()
	_build_castle()
	_scatter_props()
	_build_layers()
	_setup_camera()
	_build_sfx_pool()
	hud3d = BattleHud.new()
	ui_layer.add_child(hud3d)
	crosshair = Crosshair.new()
	ui_layer.add_child(crosshair)
	spell_caster = SpellCaster3D.new()
	spell_caster.battlefield = self
	add_child(spell_caster)
	shield = Shield3D.new()
	shield.setup(PLAYER_POS)
	add_child(shield)
	_build_overlay()
	_load_best()
	_show_banner("守住阵地！")


func _process(delta: float) -> void:
	if not is_over and spawning:
		_update_waves(delta)
	_refresh_hud()
	_update_camera(delta)
	_hitstop_cd = maxf(0.0, _hitstop_cd - delta)
	crosshair.on_enemy = spell_caster.scan_enemy(get_viewport().get_mouse_position()) != null
	shield.active = (shield_up or shield_force) and not is_over
	# 护盾挡弹
	if shield.active:
		for b in bullet_layer.get_children():
			if b is EnemyBullet3D and shield.blocks(b.global_position):
				shield.flash()
				play_sfx("shield", b.global_position, -6.0)
				b.queue_free()


# ---------- 音效池（3D 空间声，同名限频） ----------

func _build_sfx_pool() -> void:
	for i in 14:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 12.0
		p.max_distance = 120.0
		add_child(p)
		_sfx_pool.append(p)


func play_sfx(key: String, pos := Vector3.INF, vol_db := 0.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_sfx_last.get(key, -9999)) < int(SFX_GAP.get(key, 30)):
		return
	_sfx_last[key] = now
	var wav := SfxKit.stream(key)
	if wav.data.is_empty():
		return
	var p := _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	p.stream = wav
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-0.05, 0.05)
	p.global_position = camera.global_position if pos == Vector3.INF else pos
	p.play()


# ---------- 击杀顿帧（hitstop） ----------

func hitstop() -> void:
	if _hitstop_cd > 0.0 or is_over:
		return
	_hitstop_cd = 0.5
	Engine.time_scale = 0.3
	await get_tree().create_timer(0.05, true, false, true).timeout
	Engine.time_scale = 1.0


# ---------- 波次状态机 ----------

func _update_waves(delta: float) -> void:
	match phase:
		WavePhase.INTERMISSION:
			_phase_t -= delta
			if _phase_t <= 0.0:
				_start_wave()
		WavePhase.SPAWNING:
			_spawn_acc += delta
			if _spawn_acc >= _spawn_interval and not _queue.is_empty() and _alive_count() < MAX_ALIVE:
				_spawn_acc = 0.0
				spawn_enemy(_queue.pop_front())
			if _queue.is_empty():
				phase = WavePhase.CLEARING
		WavePhase.CLEARING:
			if _alive_count() == 0:
				score += WAVE_CLEAR_BONUS
				wave_cleared.emit(wave_n)
				_show_banner("第 %d 波肃清！+%d" % [wave_n, WAVE_CLEAR_BONUS])
				phase = WavePhase.INTERMISSION
				_phase_t = WaveTable.wave(wave_n).get("intermission", 5.0)


func _start_wave() -> void:
	wave_n += 1
	var w := WaveTable.wave(wave_n)
	_spawn_interval = w["spawn_interval"]
	_drops_per_medivac = int(w.get("drops", 4))
	_air_warned = {"viking": false, "medivac": false}
	_queue.clear()
	for i in int(w["marines"]):
		_queue.append("marine")
	for i in int(w["marauders"]):
		_queue.append("marauder")
	for i in int(w.get("vikings", 0)):
		_queue.append("viking")
	for i in int(w.get("medivacs", 0)):
		_queue.append("medivac")
	_queue.shuffle()
	_spawn_acc = _spawn_interval  # 立即出第一只
	phase = WavePhase.SPAWNING
	wave_started.emit(wave_n)
	play_sfx("chime")
	var parts: Array[String] = ["第 %d 波来袭！" % wave_n]
	if int(w["marines"]) + int(w["marauders"]) > 0:
		parts.append("步兵×%d" % (int(w["marines"]) + int(w["marauders"])))
	if int(w.get("vikings", 0)) > 0:
		parts.append("维京×%d" % int(w["vikings"]))
	if int(w.get("medivacs", 0)) > 0:
		parts.append("运输机×%d" % int(w["medivacs"]))
	_show_banner("　".join(parts))


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://best_score.cfg") == OK:
		best_score = int(cfg.get_value("runehand", "best", 0))


func _save_best() -> void:
	if score > best_score:
		best_score = score
	var cfg := ConfigFile.new()
	cfg.set_value("runehand", "best", best_score)
	cfg.save("user://best_score.cfg")


func _unhandled_input(event: InputEvent) -> void:
	if is_over:
		return
	if event is InputEventKey and event.pressed and SPELL_KEYS.has(event.keycode):
		spell_caster.cast(SPELL_KEYS[event.keycode], get_viewport().get_mouse_position())


func _update_camera(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		var amp := 0.09 * (_shake_t / 0.25)
		camera.position = PLAYER_POS + Vector3(randf_range(-amp, amp), randf_range(-amp, amp), 0.0)
	else:
		# 呼吸感微摆
		var t := Time.get_ticks_msec() / 1000.0
		camera.position = PLAYER_POS + Vector3(sin(t * 0.8) * 0.02, sin(t * 1.3) * 0.015, 0.0)


# ---------- 枪口火光 ----------

func muzzle_flash(pos: Vector3, big: bool) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	var r := 0.24 if big else 0.13
	sphere.radius = r
	sphere.height = r * 2.0
	mi.mesh = sphere
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.8, 0.3, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 6.0
	mi.material_override = mat
	fx_layer.add_child(mi)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.9, 0.07)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.07)
	tw.chain().tween_callback(mi.queue_free)


func add_camera_shake(t: float) -> void:
	_shake_t = maxf(_shake_t, t)


func restart() -> void:
	for e in enemies:
		e.queue_free()
	enemies.clear()
	for b in bullet_layer.get_children():
		b.queue_free()
	for f in fx_layer.get_children():
		f.queue_free()
	player_hp = 100.0
	score = 0
	kills = 0
	is_over = false
	_spawn_acc = 0.0
	_spawn_count = 0
	spawning = true
	wave_n = 0
	phase = WavePhase.INTERMISSION
	_phase_t = FIRST_WAVE_DELAY
	_queue.clear()
	_squad_left = 0
	_squad_idx = 0
	_air_warned = {"viking": false, "medivac": false}
	Engine.time_scale = 1.0
	_overlay.visible = false
	_show_banner("守住阵地！")


# ---------- 玩家受击 ----------

func player_hit(dmg: float) -> void:
	if is_over:
		return
	player_hp = maxf(0.0, player_hp - dmg)
	_flash.color.a = 0.35
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.35)
	_shake_t = maxf(_shake_t, 0.25)
	play_sfx("thump", Vector3.INF, -4.0)
	if player_hp <= 0.0:
		_game_over()


func _game_over() -> void:
	is_over = true
	spawning = false
	Engine.time_scale = 1.0
	_save_best()
	play_sfx("lose")
	_overlay.visible = true
	_overlay_label.text = "阵亡！\n\n到达 第 %d 波　得分 %d　击杀 %d\n最佳 %d\n\n按 R 重新开始" % [wave_n, score, kills, best_score]


# ---------- 敌方子弹 ----------

func spawn_bullet(from: Vector3, target: Vector3, dmg: float, speed: float, big: bool) -> void:
	var b := EnemyBullet3D.new()
	bullet_layer.add_child(b)
	b.setup(from, target, dmg, speed, big, PLAYER_POS)
	b.delivered.connect(func(d): player_hit(d))


# ---------- 伤害飘字 ----------

func spawn_damage_label(world_pos: Vector3, dmg: float, col: Color) -> void:
	var dl := DamageLabel.new()
	dl.setup(world_pos, camera, dmg, col)
	ui_layer.add_child(dl)


# ---------- 通用战场特效 ----------

## 空中爆炸（飞行单位被击落瞬间）
func air_boom(pos: Vector3) -> void:
	var boom: SpellCaster3D.ExplosionFx = SpellCaster3D.ExplosionFx.new()
	boom.radius = 2.8
	boom.position = pos
	fx_layer.add_child(boom)
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.emitting = false
	burst.amount = 24
	burst.lifetime = 0.6
	burst.explosiveness = 1.0
	burst.direction = Vector3.UP
	burst.spread = 180.0
	burst.initial_velocity_min = 3.0
	burst.initial_velocity_max = 9.0
	burst.gravity = Vector3(0, -12.0, 0)
	burst.scale_amount_min = 1.5
	burst.scale_amount_max = 4.0
	burst.color = Color(1.0, 0.55, 0.15, 0.95)
	var pm := SphereMesh.new()
	pm.radius = 0.07
	pm.height = 0.14
	burst.mesh = pm
	burst.position = pos
	fx_layer.add_child(burst)
	burst.restart()
	add_camera_shake(0.2)
	play_sfx("boom_big", pos, -4.0)


## 残骸落地：爆炸 + 尘土 + 焦痕 + 小范围溅射伤害（会误伤敌军）
func ground_impact(pos: Vector3, big: bool) -> void:
	var gpos := Vector3(pos.x, 0.0, pos.z)
	var boom: SpellCaster3D.ExplosionFx = SpellCaster3D.ExplosionFx.new()
	boom.radius = 2.2 if big else 1.5
	boom.position = gpos + Vector3.UP * 0.4
	fx_layer.add_child(boom)
	dust_puff(gpos, big)
	spawn_scorch(gpos, 2.0 if big else 1.4)
	add_camera_shake(0.22 if big else 0.12)
	play_sfx("boom_big" if big else "boom", gpos, -4.0 if big else -7.0)
	if big:
		for e in enemies.duplicate():
			if e.alive and e.global_position.distance_to(gpos) <= 2.6:
				e.take_damage(25.0)
				spawn_damage_label(e.aim_center() + Vector3.UP * 0.7, 25.0, Color(1.0, 0.7, 0.3))


## 出生/落地尘土
func dust_puff(pos: Vector3, big := false) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 12 if big else 7
	p.lifetime = 0.5
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.0 if big else 2.0
	p.gravity = Vector3(0, -4.0, 0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5 if big else 2.5
	p.color = Color(0.55, 0.47, 0.35, 0.75)
	var pm := SphereMesh.new()
	pm.radius = 0.09
	pm.height = 0.18
	p.mesh = pm
	p.position = pos + Vector3.UP * 0.1
	fx_layer.add_child(p)
	p.restart()
	get_tree().create_timer(0.9).timeout.connect(p.queue_free)


## 地面焦痕（渐隐贴片）
func spawn_scorch(pos: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = q
	var gt := GradientTexture2D.new()
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.05, 0.04, 0.03, 0.55), Color(0.05, 0.04, 0.03, 0.0)])
	g.offsets = PackedFloat32Array([0.3, 1.0])
	gt.gradient = g
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = gt
	mi.material_override = mat
	mi.rotation.x = -PI / 2.0
	# 微小随机抬升，避免多层焦痕 z-fighting
	mi.position = Vector3(pos.x, 0.02 + randf() * 0.02, pos.z)
	fx_layer.add_child(mi)
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 3.0)
	tw.tween_callback(mi.queue_free)


func _build_overlay() -> void:
	# 受击红闪（全屏）
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.8, 0.1, 0.1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_flash)
	# 游戏结束浮层
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.01, 0.01, 0.05, 0.75)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	ui_layer.add_child(_overlay)
	_overlay_label = Label.new()
	_overlay_label.set_anchors_preset(Control.PRESET_CENTER)
	_overlay_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_overlay_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 34)
	_overlay_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.7))
	_overlay_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_overlay_label.add_theme_constant_override("outline_size", 6)
	_overlay.add_child(_overlay_label)
	# 波次横幅（中上大字，淡出）
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y = 110.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 30)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	ui_layer.add_child(_banner)


# ---------- 敌人生成 ----------
# 地面：小队编队（同侧纵队进场 → 共享集结点 → 压向玩家）
# 空军：维京从场外飞入绕玩家前方半圆盘旋开火；医疗船飞到阵前上空悬停空投

func spawn_enemy(key := "", with_waypoint := true) -> EnemyUnit3D:
	if key == "":
		key = "marauder" if (_spawn_count + 1) % 4 == 0 else "marine"
	var e := EnemyUnit3D.new()
	e.setup(key, PLAYER_POS)
	e.battlefield = self
	match key:
		"viking":
			var side := -1.0 if randf() < 0.5 else 1.0
			e.position = Vector3(side * randf_range(48.0, 58.0), randf_range(12.0, 15.0), -randf_range(52.0, 66.0))
			var center := PLAYER_POS + Vector3(0.0, 0.0, -8.0)
			e.set_orbit(center, randf_range(16.0, 24.0), PI + side * 0.9, side)
			play_sfx("flyby", e.position, -4.0)
			if not _air_warned["viking"]:
				_air_warned["viking"] = true
				_show_banner("维京战机来袭！")
		"medivac":
			var mside := -1.0 if randf() < 0.5 else 1.0
			e.position = Vector3(mside * randf_range(42.0, 52.0), 12.0, -randf_range(48.0, 60.0))
			e.drop_count = _drops_per_medivac
			e.set_drop_zone(Vector3(randf_range(-10.0, 10.0), 0.0, randf_range(-26.0, -14.0)))
			play_sfx("flyby", e.position, -4.0)
			if not _air_warned["medivac"]:
				_air_warned["medivac"] = true
				_show_banner("医疗运输机空投！")
		_:
			# 地面小队：每 3-5 只换边换路线，队内成纵队（外侧依次排开）
			if _squad_left <= 0:
				_squad_left = SQUAD_MIN + (randi() % SQUAD_SPREAD)
				_squad_side *= -1.0
				_squad_idx = 0
				_squad_lane = Vector3(_squad_side * randf_range(24.0, 32.0), 0.0, randf_range(-28.0, -12.0))
				_squad_waypoint = Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-22.0, -12.0))
			e.position = _squad_lane + Vector3(_squad_side * _squad_idx * 2.0, 0.0, _squad_idx * 2.4)
			if with_waypoint:
				e.set_waypoint(_squad_waypoint + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)))
			dust_puff(e.position)
			_squad_idx += 1
			_squad_left -= 1
	enemy_layer.add_child(e)
	enemies.append(e)
	e.died.connect(_on_enemy_died)
	e.escaped.connect(_on_enemy_escaped)
	_spawn_count += 1
	return e


## 医疗船空投：枪兵从天而降，落地扬尘
func drop_marine(xz: Vector3) -> void:
	var e := spawn_enemy("marine", false)
	var target := xz + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
	e.global_position = Vector3(target.x, 7.0, target.z)
	e.stun_t = 0.45
	play_sfx("thump", e.global_position, -10.0)
	var tw := create_tween()
	tw.tween_property(e, "global_position:y", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if is_instance_valid(e) and e.alive:
			dust_puff(e.global_position)
			play_sfx("thump", e.global_position, -8.0))


func _alive_count() -> int:
	var n := 0
	for e in enemies:
		if e.alive:
			n += 1
	return n


func _on_enemy_died(u: EnemyUnit3D) -> void:
	enemies.erase(u)
	kills += 1
	score += u.score_value
	hitstop()
	if u.flying:
		add_camera_shake(0.18)
	else:
		play_sfx("boom", u.global_position, -6.0)
		spawn_scorch(u.global_position, 1.3)
		dust_puff(u.global_position)


func _on_enemy_escaped(u: EnemyUnit3D) -> void:
	enemies.erase(u)


func _refresh_hud() -> void:
	if hud3d == null:
		return
	hud3d.hp_ratio = player_hp / 100.0
	if is_over:
		hud3d.wave_text = "第 %d 波" % wave_n
	elif phase == WavePhase.INTERMISSION:
		if wave_n == 0:
			hud3d.wave_text = "准备中 %.0f s" % ceilf(maxf(_phase_t, 0.0))
		else:
			hud3d.wave_text = "下一波 %.0f s" % ceilf(maxf(_phase_t, 0.0))
	else:
		hud3d.wave_text = "第 %d 波" % wave_n
	hud3d.enemy_text = "敌人 %d" % (_alive_count() + _queue.size())
	hud3d.score_text = "得分 %d（击杀 %d）最佳 %d" % [score, kills, best_score]


# ---------- 场景搭建 ----------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.56, 0.85)
	sky_mat.sky_horizon_color = Color(0.76, 0.86, 0.93)
	sky_mat.ground_bottom_color = Color(0.20, 0.30, 0.18)
	sky_mat.ground_horizon_color = Color(0.64, 0.74, 0.60)
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 0.9
	# 深度雾：纵深层次 + 远景岩环融进天际
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.74, 0.83, 0.90)
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 110.0
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	# 城堡方向暖色补光
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 4.0, 22.0)
	fill.light_color = Color(1.0, 0.85, 0.7)
	fill.light_energy = 0.5
	fill.omni_range = 28.0
	add_child(fill)


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROUND_COLOR
	mat.roughness = 1.0
	# 程序噪声草地：无缝平铺，绿色深浅变化打破纯色地面
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.55, 0.62, 0.46), Color(1.0, 1.0, 0.92)])
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.color_ramp = ramp
	tex.noise = noise
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(12.0, 12.0, 1.0)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.material_override = mat
	add_child(ground)


func _build_castle() -> void:
	# 指挥中心在玩家身后（逻辑上的大本营，画面外）；地堡/导弹塔前移到
	# 玩家前方两翼画面边缘，营造"驻守阵地"的第一人称构图（模型面朝 +Y，转 PI 朝 -Z 战场）
	_instance_glb(PATH_BUILDINGS % "b_command_center", Vector3(0.0, 0.0, 30.0), PI, BUILDING_SCALE * 1.6)
	_instance_glb(PATH_BUILDINGS % "b_bunker", Vector3(-11.0, 0.0, -2.0), PI, BUILDING_SCALE)
	_instance_glb(PATH_BUILDINGS % "b_bunker", Vector3(11.0, 0.0, -2.0), PI, BUILDING_SCALE)
	_instance_glb(PATH_BUILDINGS % "b_missile_turret", Vector3(-16.0, 0.0, -8.0), PI, BUILDING_SCALE * 0.9)
	_instance_glb(PATH_BUILDINGS % "b_missile_turret", Vector3(16.0, 0.0, -8.0), PI, BUILDING_SCALE * 0.9)
	# 补给站：阵地后方两翼，丰富近景轮廓
	_instance_glb(PATH_BUILDINGS % "b_supply_depot", Vector3(-25.0, 0.0, 6.0), PI, BUILDING_SCALE * 0.9)
	_instance_glb(PATH_BUILDINGS % "b_supply_depot", Vector3(25.0, 0.0, 6.0), PI, BUILDING_SCALE * 0.9)


func _scatter_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PROP_SEED
	var props := ["e_rock", "e_tree", "e_mineral", "e_bush"]
	for i in 26:
		# 只布两翼（|x|>22 留空中路走廊），纵深覆盖战场
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * rng.randf_range(22.0, 46.0)
		var z := rng.randf_range(-42.0, 14.0)
		var key: String = props[rng.randi() % props.size()]
		var s := rng.randf_range(1.2, 2.8)
		_instance_glb(PATH_ENV % key, Vector3(x, 0.0, z), rng.randf() * TAU, s)
	# 城堡两侧矿场点缀
	_instance_glb(PATH_ENV % "e_mineral", Vector3(-16.0, 0.0, 14.0), 0.6, 2.2)
	_instance_glb(PATH_ENV % "e_mineral", Vector3(-17.5, 0.0, 12.0), 2.1, 1.8)
	_instance_glb(PATH_ENV % "e_mineral", Vector3(16.0, 0.0, 14.0), 0.6, 2.2)
	_instance_glb(PATH_ENV % "e_mineral", Vector3(17.5, 0.0, 12.0), 2.1, 1.8)
	# 远景岩环：大块岩石围出地平线剪影，融进雾里
	for i in 14:
		var ang := TAU * i / 14.0 + rng.randf() * 0.35
		var r := rng.randf_range(60.0, 74.0)
		_instance_glb(PATH_ENV % "e_rock", Vector3(cos(ang) * r, 0.0, sin(ang) * r), rng.randf() * TAU, rng.randf_range(5.0, 9.0))


func _build_layers() -> void:
	enemy_layer = Node3D.new()
	enemy_layer.name = "Enemies"
	add_child(enemy_layer)
	bullet_layer = Node3D.new()
	bullet_layer.name = "Bullets"
	add_child(bullet_layer)
	fx_layer = Node3D.new()
	fx_layer.name = "FX"
	add_child(fx_layer)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.position = PLAYER_POS
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 300.0
	camera.current = true
	add_child(camera)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	ui_layer.layer = 10
	add_child(ui_layer)


func _instance_glb(path: String, pos: Vector3, rot_y: float, scl: float) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("GLB 未导入: " + path)
		return null
	var ps: PackedScene = load(path)
	var node := ps.instantiate()
	node.position = pos
	node.rotation.y = rot_y
	node.scale = Vector3.ONE * scl
	add_child(node)
	return node
