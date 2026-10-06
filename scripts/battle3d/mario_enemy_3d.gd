class_name MarioEnemy3D
extends EnemyUnit3D
## M2 马里奥换皮敌人：不攻击玩家、不逃跑，广场巡逻供玩家施法刷分（GDD gdd-mario-reskin-v0.1 §2/§3）。
## 元素克制表：
##   goomba  任意法术一下秒杀；冰可冻结（纯演出）
##   koopa   一段任意伤→弃壳（本体计 15 分）；落地 shell 再被打→高速炮弹撞杀
##   shell   静止被打（冰除外）→发射；飞行途中撞杀地面敌人（连锁合计×2 分）；
##           冰冻不发射；久置 6s 无主溜走（escaped，不计分）
##   boo     火系临近→隐身侧闪（闪避期间无敌，火球必空）；链电 ×2 且隐身照样命中；
##           冰免疫；风小伤+击飞；大眼始终盯玩家
##   bowser  Boss：火/掌心 ×1.0，链电 ×0.8，风 ×0.2（打不动），冰减速（半血狂暴后免疫）；
##           周期咆哮演出；壳撞它只扣 30 固定伤
## 素材：res://assets3d/mario/<key>.glb（mario_kit 单件，动画片段 <key>_idle/_move，
## 壳只有 shell_move、金币 coin_idle；原始尺寸 0.3~0.7m（anim_probe_mario 实测），
## scale 按战斗距离校准：栗宝宝≈0.95m 高、库巴≈2.9m 高压场。
const MARIO_STATS := {
	"goomba": {"hp": 1.0, "speed": 1.25, "score": 10, "scale": 2.2, "aim_h": 0.45, "shadow": 0.5},
	"koopa": {"hp": 1.0, "speed": 1.0, "score": 15, "scale": 2.2, "aim_h": 0.45, "shadow": 0.5},
	"shell": {"hp": 1.0, "speed": 0.0, "score": 15, "scale": 1.6, "aim_h": 0.25, "shadow": 0.45},
	"boo": {"hp": 60.0, "speed": 0.85, "score": 50, "scale": 2.3, "aim_h": 0.55, "shadow": 0.55,
		"flying": true, "fly_height": 3.2},
	"bowser": {"hp": 600.0, "speed": 0.9, "score": 500, "scale": 4.2, "aim_h": 1.5, "shadow": 1.4},
}
const PATROL_MIN_X := -14.0
const PATROL_MAX_X := 14.0
const SHELL_FLY_SPEED := 15.0
const SHELL_KILL_RADIUS := 1.3
const SHELL_STILL_LIFE := 6.0
const SHELL_FLY_LIFE := 4.0
const BOO_DODGE_RADIUS := 3.5
const BOO_DODGE_T := 1.1
const BOO_HOVER := 3.2
const BOWSER_SHELL_DMG := 30.0

enum MState { STROLL, PAUSE, SHELL_STILL, SHELL_FLY, DODGE, DEAD }

var mstate: MState = MState.STROLL
var walk_dir := 1.0
var patrol_min_x := PATROL_MIN_X
var patrol_max_x := PATROL_MAX_X

var _pause_t := 0.0
var _stealth_t := 0.0
var _invulnerable := false
var _enraged := false
var _roar_t := 4.0
var _shell_t := 0.0
var _shell_dir := Vector3.ZERO
var _alpha_mats: Array[StandardMaterial3D] = []
var _hp_bar: Label3D


func _ready() -> void:
	_stats = MARIO_STATS.get(unit_key, MARIO_STATS["goomba"])
	flying = bool(_stats.get("flying", false))
	max_hp = float(_stats["hp"])
	hp = max_hp
	speed = float(_stats["speed"])
	if unit_key != "bowser" and unit_key != "shell":
		speed *= randf_range(0.85, 1.15)  # 同种个体速度抖动，队形自然散开
	score_value = int(_stats["score"])
	var ps: PackedScene = load("res://assets3d/mario/%s.glb" % unit_key)
	_model = ps.instantiate()
	_model_base_scale = Vector3.ONE * float(_stats.get("scale", 1.5))
	_model.scale = _model_base_scale
	add_child(_model)
	_collect_flash_mats(_model)
	if unit_key == "boo":
		# 幽灵需要隐身：复用受击闪白的那批材质副本，打开透明通道
		for m in _flash_mats:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_alpha_mats = _flash_mats
	if not flying:
		_build_freeze_shell()
	_build_shadow()
	_ap = _find_anim_player(_model)
	if _ap != null:
		for anim_name in _ap.get_animation_list():
			var anim: Animation = _ap.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR
	# 初始行走方向：从出生侧走向广场内侧
	walk_dir = -1.0 if global_position.x > 0.0 else 1.0
	if unit_key == "bowser":
		patrol_min_x = -8.0
		patrol_max_x = 8.0
		_roar_t = randf_range(3.0, 5.0)
		_build_hp_bar()
	elif unit_key == "boo":
		global_position.y = BOO_HOVER
	elif unit_key == "shell":
		mstate = MState.SHELL_STILL
		_shell_t = SHELL_STILL_LIFE
	if unit_key != "shell":
		_play("move")
	# 同批生成错峰，避免齐步走
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
			_freeze_shell.visible = true
		return  # 冻结罚站（boo 免疫冰不会进这里）
	elif _freeze_shell != null:
		_freeze_shell.visible = false
	match unit_key:
		"boo":
			_process_boo(delta)
		"shell":
			_process_shell(delta)
		_:
			_process_walker(delta)
			if unit_key == "bowser":
				_process_bowser(delta)


# ---------- 行为：地面巡逻 ----------

func _process_walker(delta: float) -> void:
	var v := speed * (1.5 if _enraged else 1.0)
	global_position.x += walk_dir * v * delta
	if walk_dir > 0.0 and global_position.x >= patrol_max_x:
		walk_dir = -1.0
	elif walk_dir < 0.0 and global_position.x <= patrol_min_x:
		walk_dir = 1.0
	_face_to(Vector3(walk_dir, 0.0, 0.0))
	if mstate == MState.PAUSE:
		_pause_t -= delta
		if _pause_t <= 0.0:
			mstate = MState.STROLL
			_play("move")
	else:
		# 随机驻足张望（库巴节奏慢些）
		var chance := 0.12 if unit_key == "bowser" else 0.25
		if randf() < delta * chance:
			mstate = MState.PAUSE
			_pause_t = randf_range(0.6, 1.2)
			_play("idle")


# ---------- 行为：幽灵 ----------

func _process_boo(delta: float) -> void:
	if mstate == MState.DODGE:
		_stealth_t -= delta
		if _stealth_t <= 0.0:
			mstate = MState.STROLL
			_invulnerable = false
			_set_alpha(1.0, 0.3)
	# 水平漂移 + 边界回弹（活动区比地面巡逻带大一圈）
	var drift := Vector3.ZERO
	if global_position.x > PATROL_MAX_X + 2.0:
		drift.x = -1.0
	elif global_position.x < PATROL_MIN_X - 2.0:
		drift.x = 1.0
	if global_position.z > -4.0:
		drift.z = -1.0
	elif global_position.z < -24.0:
		drift.z = 1.0
	if drift == Vector3.ZERO and randf() < delta * 0.4:
		drift = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if drift.length_squared() > 0.001:
		global_position += drift.normalized() * speed * delta
	# 正弦浮沉 + googly 大眼始终盯玩家
	global_position.y = BOO_HOVER + sin(Time.get_ticks_msec() * 0.0016) * 0.35
	_face_to(player_pos - global_position)


## 火球飞行体临近命中时调用（0.4s 预警）：落点在闪避半径内→隐身侧闪，期间无敌。
## 仅 boo 有此反应——栗宝宝/龟/库巴不会躲火
func try_dodge_fire(impact: Vector3) -> void:
	if unit_key != "boo":
		return
	if not alive or _invulnerable or mstate == MState.DODGE:
		return
	var away := global_position - impact
	away.y = 0.0
	if away.length() > BOO_DODGE_RADIUS:
		return
	mstate = MState.DODGE
	_invulnerable = true
	_stealth_t = BOO_DODGE_T
	# 朝垂直于"幽灵-落点"连线的侧向急闪
	var side := Vector3(-away.z, 0.0, away.x).normalized()
	if side.length_squared() < 0.001 or randf() < 0.5:
		side = -side
	var tw := create_tween()
	tw.tween_property(self, "global_position", global_position + side * 2.2, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_set_alpha(0.12, 0.2)
	if battlefield != null:
		battlefield.play_sfx("cast_wind", global_position, -10.0)  # 下滑音占位（M2.3 换 boo 专属音）
		battlefield.spawn_text_label(aim_center() + Vector3.UP * 1.0, "闪!", Color(0.7, 0.85, 1.0))


func is_stealthed() -> bool:
	return unit_key == "boo" and _invulnerable


# ---------- 行为：龟壳 ----------

func _process_shell(delta: float) -> void:
	_shell_t -= delta
	if mstate == MState.SHELL_FLY:
		global_position += _shell_dir * SHELL_FLY_SPEED * delta
		_chain_kill_sweep()
		if _shell_t <= 0.0 or absf(global_position.x) > 18.0 or global_position.z > 0.0 or global_position.z < -26.0:
			_die_shell_break()
	elif _shell_t <= 0.0:
		# 久置无主：溜走清场（不计分，escaped 让战场清账，避免卡波）
		alive = false
		mstate = MState.DEAD
		escaped.emit(self)
		queue_free()


func _launch_shell(dir: Vector3) -> void:
	if mstate == MState.SHELL_FLY or not alive:
		return
	mstate = MState.SHELL_FLY
	_shell_dir = dir
	_shell_t = SHELL_FLY_LIFE
	_play("move")  # 壳高速自转
	if battlefield != null:
		battlefield.play_sfx("shoot_big", global_position, -10.0)


func _chain_kill_sweep() -> void:
	if battlefield == null:
		return
	# duplicate：撞杀会触发死亡回调从 enemies 移除元素，原数组不能边遍历边改
	for e in battlefield.enemies.duplicate():
		if e == self or not e.alive or not (e is MarioEnemy3D):
			continue
		var me := e as MarioEnemy3D
		if me.flying:
			continue  # 地上滚的壳够不着天上
		if me.unit_key == "bowser":
			# 壳撞 Boss：固定 30 伤（秒杀太破坏 Boss 战）
			if me.global_position.distance_to(global_position) <= SHELL_KILL_RADIUS + 0.7:
				me.take_damage(BOWSER_SHELL_DMG)
			continue
		if me.mstate == MState.SHELL_FLY:
			continue
		if me.global_position.distance_to(global_position) <= SHELL_KILL_RADIUS:
			_chain_kill(me)


func _chain_kill(victim: MarioEnemy3D) -> void:
	var bonus := victim.score_value
	victim.take_damage(99999.0)  # 走各单位自己的死亡演出
	if battlefield != null:
		battlefield.score += bonus  # 连锁击杀额外加成（合计 ×2 分）
		battlefield.spawn_text_label(victim.aim_center() + Vector3.UP * 1.2, "连锁!", Color(1.0, 0.85, 0.3))


# ---------- Boss：库巴 ----------

func _process_bowser(delta: float) -> void:
	if not _enraged and hp <= max_hp * 0.5:
		_enrage()
	_roar_t -= delta
	if _roar_t > 0.0:
		return
	_roar_t = randf_range(5.0, 7.5) if _enraged else randf_range(7.0, 10.0)
	# 咆哮演出：驻足 + 缩放脉冲 + 震屏低鸣（无伤害，纯气氛）
	mstate = MState.PAUSE
	_pause_t = 1.3
	_play("idle")
	if _model != null:
		var tw := create_tween()
		tw.tween_property(_model, "scale", _model_base_scale * 1.12, 0.22)
		tw.tween_property(_model, "scale", _model_base_scale, 0.34)
	if battlefield != null:
		battlefield.add_camera_shake(0.3)
		battlefield.play_sfx("boom_big", global_position, -4.0)


func _enrage() -> void:
	_enraged = true
	speed *= 1.5
	# 泛红：混入自发光红（受击白闪会临时盖过，闪完红光仍在）
	for m in _flash_mats:
		m.emission = Color(1.0, 0.18, 0.08)
		m.emission_energy_multiplier = maxf(m.emission_energy_multiplier, 0.85)
	if battlefield != null:
		battlefield._show_banner("库巴狂暴了！")


func _build_hp_bar() -> void:
	_hp_bar = Label3D.new()
	_hp_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar.font_size = 72
	_hp_bar.pixel_size = 0.016  # 字高 ~1.15m，24m 外也能读清
	_hp_bar.outline_size = 20
	_hp_bar.modulate = Color(1.0, 0.45, 0.3)
	_hp_bar.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_hp_bar.text = "库巴 100%"
	# 挂头顶上方（bowser scale 4.2 ≈ 2.9m 高，字高 1.15m，锚点在字心）
	_hp_bar.position = Vector3.UP * (float(_stats.get("aim_h", 1.9)) + 2.05)
	add_child(_hp_bar)


func _update_hp_bar() -> void:
	if _hp_bar != null:
		_hp_bar.text = "库巴 %d%%" % roundi(hp / max_hp * 100.0)


# ---------- 伤害与元素克制表 ----------

func take_damage(dmg: float) -> bool:
	if not alive:
		return false
	match unit_key:
		"goomba":
			hp -= dmg
			_flash_hit()
			if battlefield != null:
				battlefield.play_sfx("hit", aim_center(), -12.0)
			if hp <= 0.0:
				_die_squash()
				return true
			return false
		"koopa":
			_shell_out()
			return true  # 本体判"击破"（去壳计分）
		"shell":
			if mstate == MState.SHELL_STILL:
				_launch_shell(_launch_dir(Vector3.ZERO))
			return false
		"boo":
			# 注意：无敌判定只在 apply_spell 的 fire 分支做——链电无视隐身，必须能直接命中
			hp -= dmg
			_flash_hit()
			if battlefield != null:
				battlefield.play_sfx("hit", aim_center(), -12.0)
			if hp <= 0.0:
				_die_boo()
				return true
			return false
		"bowser":
			hp -= dmg
			_flash_hit()
			_update_hp_bar()
			if battlefield != null:
				battlefield.play_sfx("hit", aim_center(), -8.0)
			if hp <= 0.0:
				_die_bowser()
				return true
			return false
	return false


## 元素伤害入口（克制表见类头注释）。返回实际伤害：>0 受伤 / 0 无伤 / <0 免疫
func apply_spell(element: String, dmg: float, dir: Vector3 = Vector3.ZERO) -> float:
	if not alive:
		return 0.0
	match unit_key:
		"goomba":
			if element == "ice":
				apply_freeze(2.5)
			take_damage(dmg)
			return dmg
		"koopa":
			if element == "ice":
				apply_freeze(2.5)
			_shell_out()
			return dmg
		"shell":
			if mstate == MState.SHELL_FLY:
				return 0.0
			if element == "ice":
				apply_freeze(2.0)  # 冻住不发射
				return dmg
			_launch_shell(_launch_dir(dir))
			return dmg
		"boo":
			return _boo_spell(element, dmg, dir)
		"bowser":
			return _bowser_spell(element, dmg, dir)
	return 0.0


func _boo_spell(element: String, dmg: float, dir: Vector3) -> float:
	match element:
		"fire":
			if _invulnerable:
				return 0.0  # 已闪避，火球落空
			take_damage(dmg)  # 兜底：0.4s 预警没赶上的贴脸火
			return dmg
		"lightning":
			var d := dmg * 2.0  # 弱点：隐身也躲不掉链电
			take_damage(d)
			return d
		"ice":
			return -1.0  # 幽灵没有实体：免疫（飘"免疫"）
		"wind":
			var d2 := dmg * 0.5
			take_damage(d2)
			if alive:
				var push := dir
				push.y = 0.0
				if push.length_squared() > 0.001:
					var tw := create_tween()
					tw.tween_property(self, "global_position", global_position + push.normalized() * 3.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			return d2
	return 0.0


func _bowser_spell(element: String, dmg: float, _dir: Vector3) -> float:
	match element:
		"ice":
			if _enraged:
				return -1.0  # 狂暴免疫冰
			apply_freeze(1.2)
			take_damage(dmg)
			return dmg
		"lightning":
			var d := dmg * 0.8
			take_damage(d)
			return d
		"wind":
			var d2 := dmg * 0.2  # 皮糙肉厚打不动
			take_damage(d2)
			return d2
		_:
			take_damage(dmg)
			return dmg


func _launch_dir(dir: Vector3) -> Vector3:
	var d := dir
	d.y = 0.0
	if d.length_squared() < 0.001:
		d = global_position - player_pos
		d.y = 0.0
	return d.normalized() if d.length_squared() > 0.001 else Vector3.FORWARD


func _shell_out() -> void:
	if not alive or unit_key != "koopa":
		return
	if battlefield != null:
		battlefield.spawn_shell(global_position)
	_die_squash()


## 马里奥单位自管位移：地面兵不掉队形、boss 打不动、boo 击飞在 apply_spell 里做
func knockback(_dir_xz: Vector3, _dist: float) -> void:
	pass


# ---------- 死亡演出 ----------

func _die_squash() -> void:
	alive = false
	mstate = MState.DEAD
	died.emit(self)
	if _shadow != null:
		_shadow.visible = false
	if _freeze_shell != null:
		_freeze_shell.visible = false
	if battlefield != null:
		battlefield.play_sfx("thump", global_position, -6.0)
		battlefield.dust_puff(global_position)
	if _model != null:
		var tw := create_tween()
		tw.tween_property(_model, "scale", Vector3(_model_base_scale.x * 1.3, _model_base_scale.y * 0.1, _model_base_scale.z * 1.3), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.45)
		tw.tween_callback(queue_free)
	else:
		queue_free()


func _die_shell_break() -> void:
	alive = false
	mstate = MState.DEAD
	died.emit(self)  # 破壳计分
	if _shadow != null:
		_shadow.visible = false
	if battlefield != null:
		battlefield.dust_puff(global_position, true)
		battlefield.play_sfx("boom", global_position, -8.0)
	queue_free()


func _die_boo() -> void:
	alive = false
	mstate = MState.DEAD
	died.emit(self)
	if _shadow != null:
		_shadow.visible = false
	if battlefield != null:
		battlefield.play_sfx("flyby", global_position, -8.0)  # 呜~ 占位
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "rotation:y", rotation.y + TAU * 1.5, 0.6)
	tw.tween_property(self, "scale", scale * 0.15, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(_set_alpha_now, 1.0, 0.0, 0.6)
	tw.chain().tween_callback(queue_free)


func _die_bowser() -> void:
	alive = false
	mstate = MState.DEAD
	died.emit(self)
	if _hp_bar != null:
		_hp_bar.visible = false
	if _shadow != null:
		_shadow.visible = false
	if battlefield != null:
		battlefield.air_boom(global_position + Vector3.UP * 1.5)
		battlefield.add_camera_shake(0.6)
	if _model != null:
		var tw := create_tween()
		tw.tween_property(_model, "scale", Vector3(_model_base_scale.x * 1.5, _model_base_scale.y * 0.25, _model_base_scale.z * 1.5), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.9)
		tw.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free)
	else:
		queue_free()


# ---------- 工具 ----------

func _set_alpha(v: float, dur := 0.2) -> void:
	for m in _alpha_mats:
		var tw := create_tween()
		tw.tween_property(m, "albedo_color:a", v, dur)


func _set_alpha_now(v: float) -> void:
	for m in _alpha_mats:
		m.albedo_color.a = v


## 动画片段名兼容：kit 命名 <key>_idle/_move，也接受裸 idle/move
func _play(clip: String) -> void:
	if _ap == null:
		return
	var full := "%s_%s" % [unit_key, clip]
	if _ap.has_animation(full):
		_ap.play(full)
	elif _ap.has_animation(clip):
		_ap.play(clip)
