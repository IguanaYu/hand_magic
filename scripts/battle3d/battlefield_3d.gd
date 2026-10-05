class_name Battlefield3D
extends Node3D
## M1.0 3D 战场骨架：地面/天空/光照/相机站位/城堡布景/环境点缀。
## 后续里程碑在此扩展：敌人层(M1.1) 战斗(M1.2) 手势(M1.3) 波次(M1.4)。

const PLAYER_POS := Vector3(0.0, 1.65, 8.0)
const GROUND_SIZE := 160.0
const GROUND_COLOR := Color(0.36, 0.52, 0.30)
const BUILDING_SCALE := 2.5
## 布景随机种子（固定 → 每局布局一致）
const PROP_SEED := 20261005

const PATH_UNITS := "res://assets3d/units/%s.glb"
const PATH_BUILDINGS := "res://assets3d/buildings/%s.glb"
const PATH_ENV := "res://assets3d/env/%s.glb"

## 自由刷怪（M1.4 换波次表）
const SPAWN_INTERVAL := 2.5
const MAX_ALIVE := 20
const FIRST_WAVE_DELAY := 3.0
const WAVE_CLEAR_BONUS := 50

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

# 波次状态（M1.4）
var wave_n := 0
var phase: WavePhase = WavePhase.INTERMISSION
var _queue: Array[String] = []
var _phase_t := FIRST_WAVE_DELAY
var _spawn_interval := SPAWN_INTERVAL
var best_score := 0

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
	crosshair.on_enemy = spell_caster.scan_enemy(get_viewport().get_mouse_position()) != null
	shield.active = (shield_up or shield_force) and not is_over
	# 护盾挡弹
	if shield.active:
		for b in bullet_layer.get_children():
			if b is EnemyBullet3D and shield.blocks(b.global_position):
				shield.flash()
				b.queue_free()


# ---------- 波次状态机（M1.4） ----------

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
	_queue.clear()
	for i in int(w["marines"]):
		_queue.append("marine")
	for i in int(w["marauders"]):
		_queue.append("marauder")
	_queue.shuffle()
	_spawn_acc = _spawn_interval  # 立即出第一只
	phase = WavePhase.SPAWNING
	wave_started.emit(wave_n)
	_show_banner("第 %d 波来袭！（枪兵×%d 掠夺者×%d）" % [wave_n, w["marines"], w["marauders"]])


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
		# 呼吸感微摆（M1.5）
		var t := Time.get_ticks_msec() / 1000.0
		camera.position = PLAYER_POS + Vector3(sin(t * 0.8) * 0.02, sin(t * 1.3) * 0.015, 0.0)


# ---------- 枪口火光（M1.5） ----------

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
	_overlay.visible = false
	_show_banner("守住阵地！")


# ---------- 玩家受击（M1.2） ----------

func player_hit(dmg: float) -> void:
	if is_over:
		return
	player_hp = maxf(0.0, player_hp - dmg)
	_flash.color.a = 0.35
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.35)
	_shake_t = maxf(_shake_t, 0.25)
	if player_hp <= 0.0:
		_game_over()


func _game_over() -> void:
	is_over = true
	spawning = false
	_save_best()
	_overlay.visible = true
	_overlay_label.text = "阵亡！\n\n到达 第 %d 波　得分 %d　击杀 %d\n最佳 %d\n\n按 R 重新开始" % [wave_n, score, kills, best_score]


# ---------- 敌方子弹 ----------

func spawn_bullet(from: Vector3, target: Vector3, dmg: float, speed: float, big: bool) -> void:
	var b := EnemyBullet3D.new()
	b.setup(from, target, dmg, speed, big, PLAYER_POS)
	b.delivered.connect(func(d): player_hit(d))
	bullet_layer.add_child(b)


# ---------- 伤害飘字 ----------

func spawn_damage_label(world_pos: Vector3, dmg: float, col: Color) -> void:
	var dl := DamageLabel.new()
	dl.setup(world_pos, camera, dmg, col)
	ui_layer.add_child(dl)


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


# ---------- 敌人生成（左右两翼弧线为主，少量正面远处） ----------

func spawn_enemy(key := "", with_waypoint := true) -> EnemyUnit3D:
	if key == "":
		key = "marauder" if (_spawn_count + 1) % 4 == 0 else "marine"
	var e := EnemyUnit3D.new()
	e.setup(key, PLAYER_POS)
	e.battlefield = self
	# 两段路径：两侧近处出生（画面边缘可见）→ 中间集结点 → 朝玩家
	var side := -1.0 if _spawn_count % 2 == 0 else 1.0
	e.position = Vector3(side * randf_range(20.0, 30.0), 0.0, randf_range(-14.0, -5.0))
	if with_waypoint:
		e.set_waypoint(Vector3(randf_range(-8.0, 8.0), 0.0, randf_range(-24.0, -14.0)))
	enemy_layer.add_child(e)
	enemies.append(e)
	e.died.connect(_on_enemy_died)
	_spawn_count += 1
	return e


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
