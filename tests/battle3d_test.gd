extends Node
## --battle3d-test：3D 战场断言（headless，M1.1 骨架版，M1.2/M1.6 扩展）。
## 结果写 tests/battle3d_result.txt，进程码 0=PASS / 1=FAIL。

var battlefield: Battlefield3D

var _pass := 0
var _fail := 0
var _lines: Array[String] = []


func _ready() -> void:
	battlefield.spawning = false
	await get_tree().process_frame
	_run()


func _check(name: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	_lines.append("[%s] %s" % ["PASS" if ok else "FAIL", name])


func _run() -> void:
	# --- 场景构建 ---
	_check("场景构建：相机/敌人层/HUD 存在",
		battlefield.camera != null and battlefield.enemy_layer != null and battlefield.hud3d != null)

	# --- 生成与前进 ---
	var e: EnemyUnit3D = battlefield.spawn_enemy("marine", false)
	_check("生成枪兵：登记 + 状态 ADVANCE",
		battlefield.enemies.has(e) and e.state == EnemyUnit3D.State.ADVANCE)
	var d0: float = e.global_position.distance_to(battlefield.PLAYER_POS)
	e.speed = 50.0
	await get_tree().create_timer(0.7).timeout
	var d1: float = e.global_position.distance_to(battlefield.PLAYER_POS)
	# 出生点随机（d0 波动数米），只断言相对推进量与未过头，不卡绝对距离
	_check("前进：0.7s 直线推进（d0=%.1f d1=%.1f）" % [d0, d1],
		d0 - d1 > 8.0 and d1 > 5.0)

	# --- 两段路径：先向集结点，再转向玩家（M1 调试版） ---
	var e3: EnemyUnit3D = battlefield.spawn_enemy("marine", false)
	e3.global_position = Vector3(20.0, 0.0, -8.0)
	e3.set_waypoint(Vector3(0.0, 0.0, -20.0))
	e3.speed = 10.0
	await get_tree().create_timer(0.5).timeout
	_check("两段路径①：先朝中间集结点走（x=20→%.1f）" % e3.global_position.x,
		e3.global_position.x < 16.0 and e3.has_waypoint)
	e3.has_waypoint = false
	var dp0: float = e3.global_position.distance_to(battlefield.PLAYER_POS)
	await get_tree().create_timer(0.3).timeout
	_check("两段路径②：集结完成后朝玩家走",
		e3.global_position.distance_to(battlefield.PLAYER_POS) < dp0)
	e3.take_damage(999.0)

	# --- 进停距（确定性摆位：12m 处走入 10m 停止线） ---
	var e2: EnemyUnit3D = battlefield.spawn_enemy("marine", false)
	e2.global_position = battlefield.PLAYER_POS + Vector3(12.0, 0.0, -2.0)
	e2.speed = 50.0
	await get_tree().create_timer(0.2).timeout
	_check("进停距：停止线切 HALT/FIRE（%s）" % e2.state_name(),
		e2.state == EnemyUnit3D.State.HALT or e2.state == EnemyUnit3D.State.FIRE)
	e2.take_damage(999.0)

	# --- 伤害与死亡 ---
	e.take_damage(999.0)
	_check("致死伤害：died 触发 + 从列表移除", not battlefield.enemies.has(e))
	_check("记分：累计 3 枪兵 +30（得分 %d）" % battlefield.score, battlefield.score == 30)

	# --- 冻结 ---
	var m: EnemyUnit3D = battlefield.spawn_enemy("marauder")
	m.apply_freeze(3.0)
	_check("冻结：掠夺者 frozen_t>0 且 HP=100", m.frozen_t > 0.0 and is_equal_approx(m.hp, 100.0))
	m.take_damage(999.0)

	# --- 软分离：重叠的地面单位自动推开（不让模型位置重叠） ---
	var sep_a: EnemyUnit3D = battlefield.spawn_enemy("marine", false)
	sep_a.global_position = Vector3(-0.4, 0.0, -20.0)
	sep_a.speed = 0.0
	var sep_b: EnemyUnit3D = battlefield.spawn_enemy("marine", false)
	sep_b.global_position = Vector3(0.4, 0.0, -20.0)
	sep_b.speed = 0.0
	await get_tree().create_timer(0.5).timeout
	_check("软分离：重叠枪兵自动推开（d=%.2f）" % sep_a.global_position.distance_to(sep_b.global_position),
		sep_a.alive and sep_b.alive
		and sep_a.global_position.distance_to(sep_b.global_position) >= 1.7)
	# 冻结单位保持原地当障碍物，对方绕开
	var fz: EnemyUnit3D = battlefield.spawn_enemy("marine", false)
	fz.global_position = Vector3(6.0, 0.0, -20.0)
	fz.speed = 0.0  # 冻结=定身后本就不移动；speed 归零仅排除其他位移源，单测分离行为本身
	fz.apply_freeze(3.0)
	var wk: EnemyUnit3D = battlefield.spawn_enemy("marine", false)
	wk.global_position = Vector3(6.6, 0.0, -20.0)
	wk.speed = 0.0
	await get_tree().create_timer(0.5).timeout
	_check("软分离：冻结单位不被推走（x=%.2f），对方让开" % fz.global_position.x,
		fz.alive and is_equal_approx(fz.global_position.x, 6.0)
		and fz.global_position.distance_to(wk.global_position) >= 1.7)
	sep_a.take_damage(999.0)
	sep_b.take_damage(999.0)
	fz.take_damage(999.0)
	wk.take_damage(999.0)

	# ===== M1.2 战斗闭环 =====

	# --- 敌方子弹命中玩家 ---
	var hp0: float = battlefield.player_hp
	battlefield.spawn_bullet(Vector3(0.0, 1.65, 2.0), battlefield.PLAYER_POS, 10.0, 20.0, false)
	await get_tree().create_timer(0.5).timeout
	_check("子弹命中：玩家扣血 %.1f（%.0f→%.0f）" % [10.0 * Battlefield3D.PLAYER_DMG_SCALE, hp0, battlefield.player_hp],
		is_equal_approx(battlefield.player_hp, hp0 - 10.0 * Battlefield3D.PLAYER_DMG_SCALE))

	# --- 敌人开火产生曳光弹 ---
	var fm: EnemyUnit3D = battlefield.spawn_enemy("marine", false)
	fm.global_position = Vector3(0.0, 0.0, battlefield.PLAYER_POS.z - 11.0)
	fm.speed = 60.0
	await get_tree().create_timer(0.2).timeout
	fm._fire_cd = 0.05  # 加速开火节奏
	await get_tree().create_timer(0.6).timeout
	_check("敌人开火：曳光弹已生成（%d 发在场上）" % battlefield.bullet_layer.get_child_count(),
		battlefield.bullet_layer.get_child_count() > 0)
	fm.take_damage(999.0)
	for b in battlefield.bullet_layer.get_children():
		b.queue_free()

	# --- 火球 AoE：范围内死、范围外活 ---
	var in_e: EnemyUnit3D = battlefield.spawn_enemy("marine")
	in_e.global_position = Vector3(1.0, 0.0, -10.0)
	var out_e: EnemyUnit3D = battlefield.spawn_enemy("marine")
	out_e.global_position = Vector3(9.0, 0.0, -10.0)
	battlefield.spell_caster.debug_explode(Vector3(0.0, 0.0, -10.0))
	_check("火球 AoE：2.5m 内敌人死 / 9m 外存活", not in_e.alive and out_e.alive)
	out_e.take_damage(999.0)

	# --- 链电：恰好 3 个最近目标 ---
	var lts: Array[EnemyUnit3D] = []
	for i in 5:
		var le: EnemyUnit3D = battlefield.spawn_enemy("marine")
		le.global_position = Vector3(-20.0 + i * 10.0, 0.0, -20.0)
		lts.append(le)
	battlefield.spell_caster._cast_lightning({"point": Vector3(0.0, 1.0, -20.0)})
	var hurt_count := 0
	for le in lts:
		if le.hp < le.max_hp:
			hurt_count += 1
		le.take_damage(999.0)
	_check("链电：5 敌中恰好 3 个受创（实际 %d）" % hurt_count, hurt_count == 3)

	# --- 冰域：冻结范围内敌人 ---
	var ice_e: EnemyUnit3D = battlefield.spawn_enemy("marine")
	ice_e.global_position = Vector3(2.0, 0.0, -15.0)
	battlefield.spell_caster._cast_ice_field(Vector3(0.0, 0.0, -15.0))
	_check("冰域：6m 内敌人被冻结（frozen=%.1f）" % ice_e.frozen_t, ice_e.frozen_t > 0.0)
	ice_e.take_damage(999.0)

	# --- 火球追踪：落点吸附（修"火球老空"，参照=落点保留画哪打哪） ---
	var hm: EnemyUnit3D = battlefield.spawn_enemy("marine")
	hm.global_position = Vector3(4.0, 0.0, -13.0)  # 落点旁 4m > AoE 2.5m：吸附追踪才打得到
	hm.speed = 0.0
	battlefield.spell_caster._spawn_fireball({"enemy": null, "point": Vector3(0.0, 0.0, -13.0)})
	await get_tree().create_timer(1.5).timeout  # 飞行 ~1.1s + 起爆余量
	_check("火球追踪：吸附落点 6m 内最近敌（4m 侧敌被炸死）",
		not is_instance_valid(hm) or not hm.alive)

	# --- 火球追踪：飞行中重指向，横移目标不空炸 ---
	var mv: EnemyUnit3D = battlefield.spawn_enemy("marine")
	mv.global_position = Vector3(0.0, 0.0, -13.0)
	mv.speed = 3.0
	mv.set_waypoint(Vector3(12.0, 0.0, -13.0))  # 飞行 ~1.1s 内横移 ~3.3m，固定落点必空
	battlefield.spell_caster._spawn_fireball({"enemy": null, "point": Vector3(0.0, 0.0, -13.0)})
	await get_tree().create_timer(1.5).timeout
	_check("火球追踪：横移目标仍命中",
		not is_instance_valid(mv) or not mv.alive)

	# --- 火球追踪：吸附圈外不锁定（画哪打哪的瞄准意义保留） ---
	var far_e: EnemyUnit3D = battlefield.spawn_enemy("marine")
	far_e.global_position = Vector3(12.0, 0.0, -13.0)  # 落点 12m > 吸附 6m
	far_e.speed = 0.0
	battlefield.spell_caster._spawn_fireball({"enemy": null, "point": Vector3(0.0, 0.0, -13.0)})
	await get_tree().create_timer(1.5).timeout
	_check("火球追踪：6m 外不吸附，按落点引爆",
		is_instance_valid(far_e) and far_e.alive)
	far_e.take_damage(999.0)

	# --- 冰冻=定身：冻结中纹丝不动（旧为减速 0.45 继续走） ---
	var fz2: EnemyUnit3D = battlefield.spawn_enemy("marine")
	fz2.global_position = Vector3(-4.0, 0.0, -16.0)
	fz2.speed = 3.0
	fz2.set_waypoint(Vector3(6.0, 0.0, -16.0))
	await get_tree().create_timer(0.2).timeout
	var walked: bool = fz2.global_position.x > -4.0  # 前置：确认冻结前在走
	var pos0: Vector3 = fz2.global_position
	fz2.apply_freeze(1.5)
	await get_tree().create_timer(0.5).timeout
	_check("冰冻定身：冻结中不移动（先走=%s，Δ=%.3f）" % [walked, fz2.global_position.distance_to(pos0)],
		walked and fz2.alive and fz2.global_position.distance_to(pos0) < 0.05)
	fz2.take_damage(999.0)

	# --- 冰冻=定身：FIRE 态敌人冻结后停止射击 ---
	var fz3: EnemyUnit3D = battlefield.spawn_enemy("marine", false)
	fz3.global_position = Vector3(0.0, 0.0, battlefield.PLAYER_POS.z - 9.0)
	fz3.speed = 60.0
	await get_tree().create_timer(0.9).timeout  # 冲到停火线 → HALT 0.4s → FIRE
	var firing: bool = fz3.state == EnemyUnit3D.State.FIRE
	fz3.apply_freeze(2.0)
	fz3._fire_cd = 0.05  # 冻结中冷却到了也不该射
	await get_tree().create_timer(0.2).timeout
	for b in battlefield.bullet_layer.get_children():
		b.queue_free()
	var n_b: int = battlefield.bullet_layer.get_child_count()
	await get_tree().create_timer(0.6).timeout
	_check("冰冻定身：冻结中停止射击（FIRE 态=%s，弹 %d→%d）" % [firing, n_b, battlefield.bullet_layer.get_child_count()],
		firing and fz3.alive and battlefield.bullet_layer.get_child_count() == 0)
	fz3.take_damage(999.0)

	# --- 风刃：近身敌人被击退 ---
	var wind_e: EnemyUnit3D = battlefield.spawn_enemy("marauder")
	wind_e.global_position = battlefield.PLAYER_POS + Vector3(0.0, 0.0, -5.0)
	var d_before: float = wind_e.global_position.distance_to(battlefield.PLAYER_POS)
	var center_screen := battlefield.camera.unproject_position(battlefield.PLAYER_POS + Vector3(0.0, 0.0, -6.0))
	battlefield.spell_caster._cast_wind_blade(center_screen)
	await get_tree().create_timer(0.35).timeout
	var d_after: float = wind_e.global_position.distance_to(battlefield.PLAYER_POS)
	_check("风刃：5m 敌被击退更远（%.1f→%.1f）" % [d_before, d_after], d_after > d_before + 1.0)
	wind_e.take_damage(999.0)

	# --- 护盾格挡（M1.3） ---
	battlefield.shield_force = true
	var hp_shield: float = battlefield.player_hp
	battlefield.spawn_bullet(Vector3(0.0, 1.65, 2.0), battlefield.PLAYER_POS, 10.0, 8.0, false)
	await get_tree().create_timer(0.5).timeout
	_check("护盾：正面子弹被格挡，玩家不掉血（%.0f→%.0f）" % [hp_shield, battlefield.player_hp],
		is_equal_approx(battlefield.player_hp, hp_shield))
	battlefield.shield_force = false

	# --- 游戏结束与重开 ---
	battlefield.player_hit(999.0)
	_check("游戏结束：HP 归零进入 is_over + 浮层显示", battlefield.is_over and battlefield._overlay.visible)
	battlefield.restart()
	_check("重开：HP 恢复 + 浮层隐藏", is_equal_approx(battlefield.player_hp, 100.0) and not battlefield._overlay.visible)

	# ===== M1.4 波次流程 =====
	var w1 := WaveTable.wave(1)
	var w3 := WaveTable.wave(3)
	_check("波次表：第1波 5枪兵0掠夺 / 第3波 9枪兵1掠夺",
		int(w1["marines"]) == 5 and int(w1["marauders"]) == 0
		and int(w3["marines"]) == 9 and int(w3["marauders"]) == 1)

	var cleared := {"n": -1}
	battlefield.wave_cleared.connect(func(n): cleared["n"] = n)
	battlefield._phase_t = 0.05  # 压缩波间计时
	await get_tree().create_timer(0.2).timeout
	_check("波间到点开波：第 1 波进入 SPAWNING（%s）" % battlefield.phase,
		battlefield.wave_n == 1 and battlefield.phase == Battlefield3D.WavePhase.SPAWNING)
	for we in battlefield.enemies.duplicate():
		we.take_damage(999.0)
	battlefield._queue.clear()
	await get_tree().create_timer(0.3).timeout
	_check("清场：+50 分进波间，wave_cleared 信号（n=%d）" % cleared["n"],
		battlefield.phase == Battlefield3D.WavePhase.INTERMISSION and cleared["n"] == 1
		and battlefield.score >= 50)

	battlefield.restart()
	_check("重开重置波次：wave_n=0 回开场波间", battlefield.wave_n == 0
		and battlefield.phase == Battlefield3D.WavePhase.INTERMISSION)

	# ===== M1.6 空军单位（维京/医疗运输机） =====

	# --- 维京：飞入 → 前方半圆盘旋开火 → 被击落 ---
	var vk: EnemyUnit3D = battlefield.spawn_enemy("viking")
	_check("维京：登记 + 高空出生 + FLY_IN（y=%.1f）" % vk.global_position.y,
		battlefield.enemies.has(vk) and vk.global_position.y > 5.0
		and vk.state == EnemyUnit3D.State.FLY_IN)
	vk.global_position = vk._fly_target - Vector3(0.0, 0.0, 5.0)
	vk.speed = 60.0
	await get_tree().create_timer(0.4).timeout
	_check("维京：到位后盘旋开火（%s）" % vk.state_name(), vk.state == EnemyUnit3D.State.STRAFE)
	_check("维京：盘旋保持在玩家前方（z=%.1f）" % vk.global_position.z,
		vk.global_position.z < battlefield.PLAYER_POS.z)
	vk._fire_cd = 0.05
	await get_tree().create_timer(0.5).timeout
	_check("维京：导弹已发射（曳光弹 %d 发）" % battlefield.bullet_layer.get_child_count(),
		battlefield.bullet_layer.get_child_count() > 0)
	for b in battlefield.bullet_layer.get_children():
		b.queue_free()
	vk.take_damage(9999.0)
	_check("维京：被击杀移除（alive=%s）" % vk.alive,
		not vk.alive and not battlefield.enemies.has(vk))

	# --- 医疗船：飞入 → 悬停空投枪兵 → 撤离 ---
	var md: EnemyUnit3D = battlefield.spawn_enemy("medivac")
	md.global_position = md._fly_target - Vector3(0.0, 0.0, 6.0)
	md.speed = 60.0
	_check("医疗船：FLY_IN 状态", md.state == EnemyUnit3D.State.FLY_IN)
	await get_tree().create_timer(0.4).timeout
	_check("医疗船：到位悬停空投（%s）" % md.state_name(),
		md.state == EnemyUnit3D.State.HOVER_DROP)
	var alive_at_drop: int = battlefield._alive_count()
	await get_tree().create_timer(2.6).timeout
	_check("医疗船：空投枪兵落地（存活 %d→%d）" % [alive_at_drop, battlefield._alive_count()],
		battlefield._alive_count() >= alive_at_drop + 2)

	# --- 波次表：空军曲线 ---
	var w2 := WaveTable.wave(2)
	var w4 := WaveTable.wave(4)
	_check("波次表：第2波 1 运输机 0 维京 / 第4波 1 维京",
		int(w2["medivacs"]) == 1 and int(w2["vikings"]) == 0 and int(w4["vikings"]) == 1)

	# ===== 符文录制面板（G / HUD 按钮）=====

	var main_ref: Node2D = get_parent()
	var panel: RuneRecordPanel = main_ref.record_panel
	var store: RuneSamples = main_ref.rune_store
	_check("录制：面板/存取器/识别器接线完整",
		panel != null and store != null and main_ref.fsm.recognizer != null)
	if panel != null and store != null:
		# 测试隔离：换测试存档路径，不碰玩家真实样本
		store.save_path = "user://test_rune_samples.json"
		store.clear_all()
		store.save()
		var rec: DollarRecognizer = main_ref.fsm.recognizer
		var user_before: int = rec.template_counts()["circle"]["user"]
		var casts_before: int = main_ref.fsm.cast_count
		process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停期间测试驱动帧继续跑
		main_ref.mode3d = true  # 测试模式早退没置这个标志：置位后 main._process 才会驱动 _process_3d 手势管线
		panel.open()
		_check("录制：打开面板即暂停", get_tree().paused and panel.is_open())
		_check("录制：战场冻结", battlefield.process_mode == Node.PROCESS_MODE_DISABLED)
		panel.select_spell("fireball")
		# 捏合落笔（等多数表决确认进画符）
		var t0 := Time.get_ticks_msec()
		while main_ref.fsm.state != GestureFSM.State.DRAWING and Time.get_ticks_msec() - t0 < 3000:
			main_ref._on_hands_updated([_pinch_hand(_rec_circle(0))])
			await get_tree().process_frame
		_check("录制：捏合落笔进入画符", main_ref.fsm.state == GestureFSM.State.DRAWING)
		# 捏合走轨迹画圆
		var ci := 0
		while ci < 40:
			main_ref._on_hands_updated([_pinch_hand(_rec_circle(ci))])
			ci += 1
			await get_tree().process_frame
		_check("录制：画圆保持画符态", main_ref.fsm.state == GestureFSM.State.DRAWING)
		# 握拳收笔（松开确认兼容路径）→ 录制面板存样本（法术不触发，法力回满，FSM 归位）
		t0 = Time.get_ticks_msec()
		while main_ref.fsm.state != GestureFSM.State.COOLDOWN and Time.get_ticks_msec() - t0 < 2000:
			main_ref._on_hands_updated([_fist_hand()])
			await get_tree().process_frame
		_check("录制：一笔存入样本", store.count("fireball") == 1)
		_check("录制：识别器即时注入新模板",
			rec.template_counts()["circle"]["user"] == user_before + 1)
		_check("录制：FSM 收笔计数+1", main_ref.fsm.cast_count == casts_before + 1)
		_check("录制：存档已写盘", FileAccess.file_exists(store.save_path))
		_check("录制：全程保持暂停", get_tree().paused)
		panel.close()
		_check("录制：关闭恢复不暂停+战场解冻",
			not get_tree().paused and battlefield.process_mode == Node.PROCESS_MODE_INHERIT)
		main_ref.mode3d = false
		store.clear_all()
		store.save()
		process_mode = Node.PROCESS_MODE_INHERIT

	_finish()


func _fist_hand(palm := Vector2(0.5, 0.5)) -> Dictionary:
	var lms: Array = SmokeTest._make_fist()
	var cur: Vector2 = (lms[0] + lms[5] + lms[9] + lms[17]) / 4.0
	var off: Vector2 = palm - cur
	var out: Array = []
	for l in lms:
		out.append(l + off)
	return {"label": "Right", "points": out, "palm": palm, "palm_raw": palm, "index_tip": out[8]}


func _drawing_hand(tip: Vector2) -> Dictionary:
	# 与 e2e_test 同款：食指链指向 tip，其余三指收拢（落在画符姿阈值内）
	var wrist := Vector2(0.5, 0.74)
	var v := tip - wrist
	var l := v.length()
	var palm_size := 0.11
	var dir := v / maxf(l, 1e-5)
	var lms: Array = []
	for i in range(21):
		lms.append(wrist)
	lms[5] = wrist + Vector2(-0.08, 0.02)
	lms[9] = wrist + dir * palm_size
	lms[13] = wrist + Vector2(0.08, 0.03)
	lms[17] = wrist + Vector2(0.10, 0.06)
	lms[6] = wrist + dir * (palm_size + (l - palm_size) * 0.33)
	lms[7] = wrist + dir * (palm_size + (l - palm_size) * 0.66)
	lms[8] = tip
	lms[12] = lms[9] + dir * 0.02
	lms[16] = lms[13] + dir * 0.02
	lms[20] = lms[17] + dir * 0.02
	return {"label": "Right", "points": lms, "palm": (lms[0] + lms[5] + lms[9] + lms[17]) / 4.0,
		"palm_raw": lms[9], "index_tip": tip}


func _pinch_hand(tip: Vector2) -> Dictionary:
	# 捏合画符手：_drawing_hand 基础上把拇指链钉到 tip（捏距 0）
	var hand := _drawing_hand(tip)
	var lms: Array = hand["points"]
	var wrist: Vector2 = lms[0]
	lms[1] = wrist + Vector2(-0.10, -0.02)
	lms[2] = wrist + (tip - wrist) * 0.35 + Vector2(-0.04, 0.0)
	lms[3] = wrist + (tip - wrist) * 0.70 + Vector2(-0.02, 0.0)
	lms[4] = tip
	return {"label": "Right", "points": lms, "palm": hand["palm"],
		"palm_raw": hand["palm_raw"], "index_tip": tip}


func _rec_circle(i: int) -> Vector2:
	var t := TAU * i / 39.0
	return Vector2(0.5, 0.40) + Vector2(cos(t - PI / 2.0), sin(t - PI / 2.0)) * 0.12


func _finish() -> void:
	_lines.append("-------- battle3d 测试: %d PASS / %d FAIL --------" % [_pass, _fail])
	var f := FileAccess.open("res://tests/battle3d_result.txt", FileAccess.WRITE)
	if f:
		for line in _lines:
			f.store_string(line + "\n")
		f.flush()
	for line in _lines:
		print(line)
	get_tree().quit(1 if _fail > 0 else 0)
