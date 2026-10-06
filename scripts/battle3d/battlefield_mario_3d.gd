class_name BattlefieldMario3D
extends Battlefield3D
## M2 马里奥换皮战场（GDD docs/gdd-mario-reskin-v0.1.md）：
## 敌人全是"走来走去"的展示单位，不攻击玩家 → 无玩家 HP/失败态；
## 固定 4 波（MarioWaveTable），第 4 波大部队 + 库巴压轴，杀库巴→金币雨→结算面板。
## 复用父类：相机/HUD/法术栏/音效池/飘字/尘土/横幅/存档；覆写：环境换肤/布景/刷怪/结算。

const MARIO_GROUND_COLOR := Color(0.42, 0.70, 0.34)
const MAX_ALIVE_M := 14
const PLAZA_Z_MIN := -22.0
const PLAZA_Z_MAX := -6.0
const PATH_MARIO := "res://assets3d/mario/%s.glb"
const BOWSER_DELAY := 8.0       # 第 4 波大部队后库巴压轴登场延迟
const BOWSER_EARLY_ALIVE := 5   # 场上剩 ≤5 只时提前请出库巴
const COIN_VALUE := 5
const COMBO_WINDOW := 3.0
const COMBO_MAX_MULT := 2.0
const WIND_RANGE_M := 22.0  # 广场怪不近身（最近 14m），风刃射程须覆盖巡逻区

var combo := 0
var max_combo := 0
var _combo_t := 0.0
var _bowser_delay_t := 0.0
var _bowser_spawned := false
var _victory_done := false
var _boo_respawn: Array[float] = []  # 幽灵补充到期时间戳（msec）


func _ready() -> void:
	_build_environment()
	_build_lights()
	_build_ground()
	_build_mario_set()
	_build_layers()
	_setup_camera()
	_build_sfx_pool()
	_build_combat_ui()
	spell_caster.wind_range = WIND_RANGE_M  # 风刃够得着广场（星际版保持 8m 贴身）
	_build_overlay()
	_load_best()
	_show_banner("欢迎来到马里奥广场！")


# ---------- 环境换肤（GDD §6） ----------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.62, 0.92)
	sky_mat.sky_horizon_color = Color(0.82, 0.90, 0.96)
	sky_mat.ground_bottom_color = Color(0.30, 0.42, 0.24)
	sky_mat.ground_horizon_color = Color(0.70, 0.80, 0.62)
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 0.95
	# 晴朗浅雾：远景柔和融进天际
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.80, 0.88, 0.94)
	env.fog_depth_begin = 40.0
	env.fog_depth_end = 130.0
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.98, 0.92)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 5.0, 10.0)
	fill.light_color = Color(1.0, 0.95, 0.85)
	fill.light_energy = 0.4
	fill.omni_range = 30.0
	add_child(fill)


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = MARIO_GROUND_COLOR
	mat.roughness = 1.0
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.60, 0.72, 0.48), Color(1.0, 1.0, 0.95)])
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


## 马里奥布景：水管勾边 + 砖块堆 + 浮空问号砖 + 远景水管剪影（替代星际城堡/props）
func _build_mario_set() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PROP_SEED
	for p in [Vector3(-15.0, 0.0, -25.0), Vector3(15.0, 0.0, -25.0), Vector3(-17.0, 0.0, -12.0),
			Vector3(17.0, 0.0, -12.0), Vector3(-11.0, 0.0, -2.0), Vector3(11.0, 0.0, -2.0)]:
		_instance_glb(PATH_MARIO % "pipe", p, 0.0, 2.2)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		var base := Vector3(side * rng.randf_range(19.0, 24.0), 0.0, rng.randf_range(-26.0, -6.0))
		for j in 3:
			_instance_glb(PATH_MARIO % "brick", base + Vector3(j * 1.8, 0.0, 0.0), 0.0, 1.6)
	for i in 3:
		_instance_glb(PATH_MARIO % "qblock", Vector3(-5.0 + i * 5.0, 3.2, -19.0), 0.0, 1.8)
	for i in 8:
		var ang := TAU * i / 8.0 + 0.4
		var r := rng.randf_range(55.0, 70.0)
		_instance_glb(PATH_MARIO % "pipe", Vector3(cos(ang) * r, 0.0, sin(ang) * r), rng.randf() * TAU, rng.randf_range(4.0, 7.0))


# ---------- 波次（固定 4 波 + 库巴压轴 + 通关结算） ----------

func _update_waves(delta: float) -> void:
	match phase:
		WavePhase.INTERMISSION:
			_phase_t -= delta
			if _phase_t <= 0.0:
				_start_wave()
		WavePhase.SPAWNING:
			_spawn_acc += delta
			if _spawn_acc >= _spawn_interval and not _queue.is_empty() and _alive_count() < MAX_ALIVE_M:
				_spawn_acc = 0.0
				spawn_enemy(_queue.pop_front())
			if _queue.is_empty():
				phase = WavePhase.CLEARING
			_tick_bowser(delta)
		WavePhase.CLEARING:
			_tick_bowser(delta)
			if _alive_count() == 0:
				if _bowser_pending():
					_spawn_bowser()  # 打太快：库巴立即压轴登场
				elif wave_n >= MarioWaveTable.last_wave():
					_victory()
				else:
					score += WAVE_CLEAR_BONUS
					wave_cleared.emit(wave_n)
					_show_banner("第 %d 波肃清！+%d" % [wave_n, WAVE_CLEAR_BONUS])
					phase = WavePhase.INTERMISSION
					_phase_t = float(MarioWaveTable.wave(wave_n).get("intermission", 4.0))
	_tick_boo_respawn()
	if _combo_t > 0.0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			combo = 0


func _start_wave() -> void:
	wave_n += 1
	var w := MarioWaveTable.wave(wave_n)
	_spawn_interval = float(w["spawn_interval"])
	_queue.clear()
	for i in int(w["goombas"]):
		_queue.append("goomba")
	for i in int(w["koopas"]):
		_queue.append("koopa")
	_queue.shuffle()
	_spawn_acc = _spawn_interval  # 立即出第一只
	phase = WavePhase.SPAWNING
	wave_started.emit(wave_n)
	play_sfx("chime")
	var parts: Array[String] = ["第 %d/%d 波" % [wave_n, MarioWaveTable.last_wave()]]
	parts.append("栗宝宝×%d" % int(w["goombas"]))
	if int(w["koopas"]) > 0:
		parts.append("慢慢龟×%d" % int(w["koopas"]))
	if int(w["bowser"]) > 0:
		parts.append("库巴压轴")
		_bowser_delay_t = BOWSER_DELAY
		_bowser_spawned = false
	_show_banner("　".join(parts))
	# 幽灵常驻：补到本波上限（死后 4s 场外飘回）
	while _boo_count() < int(w["boo_cap"]):
		spawn_enemy("boo")


func _tick_bowser(delta: float) -> void:
	if wave_n < MarioWaveTable.last_wave() or _bowser_spawned:
		return
	_bowser_delay_t -= delta
	if _bowser_delay_t <= 0.0 or _alive_count() <= BOWSER_EARLY_ALIVE:
		_spawn_bowser()


func _bowser_pending() -> bool:
	return wave_n >= MarioWaveTable.last_wave() and not _bowser_spawned


func _spawn_bowser() -> void:
	_bowser_spawned = true
	spawn_enemy("bowser")
	_show_banner("库巴登场！")


func _tick_boo_respawn() -> void:
	if _boo_respawn.is_empty():
		return
	var now := float(Time.get_ticks_msec())
	var cap := int(MarioWaveTable.wave(maxi(wave_n, 1))["boo_cap"])
	for t in _boo_respawn.duplicate():
		if t <= now and _boo_count() < cap:
			_boo_respawn.erase(t)
			spawn_enemy("boo")


func _boo_count() -> int:
	var n := 0
	for e in enemies:
		if e.alive and e is MarioEnemy3D and (e as MarioEnemy3D).unit_key == "boo":
			n += 1
	return n


# ---------- 刷怪（两侧进场 + 幽灵天上 + 库巴深处） ----------

func spawn_enemy(key := "", with_waypoint := true) -> EnemyUnit3D:
	var e := MarioEnemy3D.new()
	e.setup(key, PLAYER_POS)
	e.battlefield = self
	match key:
		"boo":
			var side := -1.0 if randf() < 0.5 else 1.0
			e.position = Vector3(side * randf_range(17.0, 21.0), MarioEnemy3D.BOO_HOVER, randf_range(PLAZA_Z_MIN, PLAZA_Z_MAX))
		"bowser":
			e.position = Vector3(randf_range(-4.0, 4.0), 0.0, PLAZA_Z_MIN + 2.0)
			play_sfx("boom_big", e.position, -2.0)
			add_camera_shake(0.5)
			dust_puff(e.position, true)
		_:
			var side2 := -1.0 if randf() < 0.5 else 1.0
			e.position = Vector3(side2 * randf_range(16.0, 19.0), 0.0, randf_range(PLAZA_Z_MIN, PLAZA_Z_MAX))
			dust_puff(e.position)
	enemy_layer.add_child(e)
	enemies.append(e)
	e.died.connect(_on_enemy_died)
	e.escaped.connect(_on_enemy_escaped)
	_spawn_count += 1
	return e


## 慢慢龟弃壳：原地留一颗静止壳（再被打→发射）
func spawn_shell(pos: Vector3) -> void:
	var s := MarioEnemy3D.new()
	s.setup("shell", PLAYER_POS)
	s.battlefield = self
	s.position = pos
	enemy_layer.add_child(s)
	enemies.append(s)
	s.died.connect(_on_enemy_died)
	s.escaped.connect(_on_enemy_escaped)


# ---------- 得分：连击 + 金币 ----------

func _on_enemy_died(u: EnemyUnit3D) -> void:
	enemies.erase(u)
	# 连击：3s 窗口内连续击杀叠加倍率（首杀 ×1，封顶 ×2）
	if _combo_t > 0.0:
		combo += 1
	else:
		combo = 1
	_combo_t = COMBO_WINDOW
	max_combo = maxi(max_combo, combo)
	var mult := minf(1.0 + (combo - 1) * 0.1, COMBO_MAX_MULT)
	score += roundi(u.score_value * mult)
	kills += 1
	# Boss 免顿帧；幽灵/库巴死亡演出自带，战场不补特效
	if u.unit_key != "bowser":
		hitstop()
	# 击杀掉金币（GDD §4）：栗宝宝/龟/壳 1 枚，幽灵 2 枚；库巴走金币雨（_bowser_finale）
	match u.unit_key:
		"goomba", "koopa", "shell":
			drop_coin(u.global_position + Vector3.UP * 0.4)
		"boo":
			drop_coin(u.global_position + Vector3.UP * 0.4)
			drop_coin(u.global_position + Vector3.UP * 0.9, 0.1)
	if u is MarioEnemy3D:
		var me := u as MarioEnemy3D
		if me.unit_key == "boo":
			_boo_respawn.append(Time.get_ticks_msec() + 4000.0)
		elif me.unit_key == "bowser":
			_bowser_finale()


## 击杀掉金币：弹出→落地→磁吸向玩家→+5 分
func drop_coin(pos: Vector3, delay := 0.0) -> void:
	var c := CoinFx.new()
	c.battlefield = self
	fx_layer.add_child(c)
	c.position = pos
	c.start(delay)


func add_coin_score() -> void:
	score += COIN_VALUE
	play_sfx("coin", Vector3.INF, -6.0)


## 库巴击破演出：横幅 + 金币雨（通关结算由 CLEARING → _victory 接棒）
func _bowser_finale() -> void:
	_show_banner("库巴击破！")
	add_camera_shake(0.8)
	for i in 20:
		var c := CoinFx.new()
		c.battlefield = self
		c.from_sky = true
		fx_layer.add_child(c)
		c.position = Vector3(randf_range(-5.0, 5.0), randf_range(7.0, 11.0), randf_range(-18.0, -8.0))
		c.start(0.06 * i)


# ---------- 通关结算（无失败态） ----------

func _victory() -> void:
	if _victory_done:
		return
	_victory_done = true
	is_over = true
	spawning = false
	Engine.time_scale = 1.0
	wave_cleared.emit(wave_n)
	_show_banner("广场肃清！")
	# 等金币雨演出收尾再弹结算
	await get_tree().create_timer(2.2).timeout
	_save_best()
	play_sfx("chime", Vector3.INF, 0.0)
	_overlay.visible = true
	_overlay_label.text = "通 关 ！\n\n总分 %d　击杀 %d　最大连击 ×%d\n历史最佳 %d\n\n按 R 再来一次" % [
		score, kills, max_combo, best_score]


func restart() -> void:
	super.restart()
	combo = 0
	max_combo = 0
	_combo_t = 0.0
	_bowser_delay_t = 0.0
	_bowser_spawned = false
	_victory_done = false
	_boo_respawn.clear()
	_show_banner("欢迎来到马里奥广场！")


func _refresh_hud() -> void:
	if hud3d == null:
		return
	hud3d.hp_ratio = 1.0  # 敌人不攻击：无 HP 概念，血条常满（M2.3 HUD 换肤时去掉）
	if is_over:
		hud3d.wave_text = "第 %d/%d 波" % [wave_n, MarioWaveTable.last_wave()]
	elif phase == WavePhase.INTERMISSION:
		if wave_n == 0:
			hud3d.wave_text = "准备中 %.0f s" % ceilf(maxf(_phase_t, 0.0))
		else:
			hud3d.wave_text = "第 %d/%d 波　下一波 %.0f s" % [wave_n, MarioWaveTable.last_wave(), ceilf(maxf(_phase_t, 0.0))]
	else:
		hud3d.wave_text = "第 %d/%d 波" % [wave_n, MarioWaveTable.last_wave()]
	hud3d.enemy_text = "敌人 %d" % (_alive_count() + _queue.size())
	var score_line := "得分 %d（击杀 %d）最佳 %d" % [score, kills, best_score]
	if combo >= 2:
		score_line += "　连击 ×%d" % combo
	hud3d.score_text = score_line


# ---------- 金币实体 ----------

## 金币：弹出→落地→磁吸向玩家→+5 分；from_sky=true 为库巴金币雨（从天而降）
class CoinFx:
	extends Node3D
	var battlefield: BattlefieldMario3D
	var from_sky := false
	var _spin := 0.0
	var _model: Node3D

	func _ready() -> void:
		var ps: PackedScene = load("res://assets3d/mario/coin.glb")
		_model = ps.instantiate()
		_model.scale = Vector3.ONE * 1.2
		add_child(_model)
		var ap := _find_ap(_model)
		if ap != null:
			var anims: Array = ap.get_animation_list()
			for anim_name in anims:
				ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
			if anims.size() > 0:
				ap.play(anims[0])
		visible = false

	func _process(delta: float) -> void:
		# 兜底自转（金币 GLB 无动画时也保持旋转感）
		_spin += delta * 4.0
		if _model != null and not _model.has_node("AnimationPlayer"):
			_model.rotation.y = _spin

	func start(delay: float) -> void:
		_run(delay)

	func _run(delay: float) -> void:
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
		if not is_instance_valid(self):
			return
		visible = true
		var tw := create_tween()
		if from_sky:
			tw.tween_property(self, "position:y", 0.25, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		else:
			tw.tween_property(self, "position:y", position.y + 1.8, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "position:y", 0.25, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(0.12)
		tw.tween_callback(_magnet)

	func _magnet() -> void:
		if battlefield == null or not is_instance_valid(self):
			return
		var tw := create_tween()
		tw.tween_property(self, "global_position", battlefield.camera.global_position, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(_collect)

	func _collect() -> void:
		if battlefield != null and is_instance_valid(battlefield):
			battlefield.add_coin_score()
		queue_free()

	func _find_ap(node: Node) -> AnimationPlayer:
		if node is AnimationPlayer:
			return node
		for c in node.get_children():
			var r: AnimationPlayer = _find_ap(c)
			if r != null:
				return r
		return null
