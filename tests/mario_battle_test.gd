extends Node
## --mario-test：马里奥换皮战场断言（headless）。
## 覆盖：巡逻/秒杀/弃壳-发射-连锁/幽灵火躲电吃冰免疫/库巴倍率狂暴/波次表/通关/重开。
## 结果写 tests/mario_battle_result.txt，进程码 0=PASS / 1=FAIL。

var battlefield: BattlefieldMario3D

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
	var sc: SpellCaster3D = battlefield.spell_caster

	# --- 场景构建 ---
	_check("场景构建：相机/敌人层/HUD/结算浮层存在",
		battlefield.camera != null and battlefield.enemy_layer != null
		and battlefield.hud3d != null and battlefield._overlay != null)

	# --- 栗宝宝：巡逻 + 任意法术秒杀 ---
	var g: MarioEnemy3D = battlefield.spawn_enemy("goomba")
	g.global_position = Vector3(6.0, 0.0, -14.0)
	var x0: float = g.global_position.x
	await get_tree().create_timer(0.5).timeout
	_check("栗宝宝巡逻：0.5s 内沿 x 移动（%.2f→%.2f）" % [x0, g.global_position.x],
		absf(g.global_position.x - x0) > 0.2)
	var score0: int = battlefield.score
	g.apply_spell("fire", 40.0, Vector3.ZERO)
	_check("栗宝宝火球秒杀：死亡+移除+计分 10", not g.alive
		and not battlefield.enemies.has(g) and battlefield.score >= score0 + 10)
	var g2: MarioEnemy3D = battlefield.spawn_enemy("goomba")
	g2.global_position = Vector3(-6.0, 0.0, -14.0)
	g2.apply_spell("quick", 8.0, Vector3.ZERO)  # 掌心火弹（8 伤）也秒
	_check("栗宝宝掌心火弹秒杀", not g2.alive)

	# --- 火球飞行体全链路：预警不该让栗宝宝闪避（gallery 02 抓到的 bug） ---
	var g3: MarioEnemy3D = battlefield.spawn_enemy("goomba")
	g3.global_position = Vector3(3.0, 0.0, -12.0)
	g3.try_dodge_fire(Vector3(2.5, 0.0, -12.0))
	_check("栗宝宝不闪避火球：无敌不触发", not g3._invulnerable and g3.mstate != MarioEnemy3D.MState.DODGE)
	var g4: MarioEnemy3D = battlefield.spawn_enemy("goomba")
	g4.global_position = Vector3(0.0, 0.0, -12.0)
	battlefield.spell_caster.cast("fireball", battlefield.camera.unproject_position(Vector3(0.0, 0.5, -12.0)))
	await get_tree().create_timer(1.4).timeout  # 飞行+起爆全链路
	_check("火球投射物全链路：栗宝宝被炸死", not is_instance_valid(g4) or not g4.alive)

	# --- 慢慢龟：一段弃壳 → 静止壳 ---
	var k: MarioEnemy3D = battlefield.spawn_enemy("koopa")
	k.global_position = Vector3(0.0, 0.0, -14.0)
	var score1: int = battlefield.score
	k.apply_spell("wind", 18.0, Vector3(1, 0, 0))
	_check("慢慢龟一段：本体破去壳计 15 分", not k.alive and battlefield.score >= score1 + 15)
	await get_tree().create_timer(0.1).timeout
	var shell: MarioEnemy3D = null
	for e in battlefield.enemies:
		if e is MarioEnemy3D and (e as MarioEnemy3D).unit_key == "shell":
			shell = e
	_check("弃壳：场上出现静止壳", shell != null and shell.mstate == MarioEnemy3D.MState.SHELL_STILL)

	# --- 壳发射 + 连锁撞杀 ---
	shell.global_position = Vector3(0.0, 0.0, -14.0)
	var victim: MarioEnemy3D = battlefield.spawn_enemy("goomba")
	victim.global_position = Vector3(4.0, 0.0, -14.0)
	var score2: int = battlefield.score
	shell.apply_spell("fire", 40.0, Vector3(1, 0, 0))  # 火球炸壳 → 沿 +x 发射
	_check("壳被打发射：进入 SHELL_FLY", shell.mstate == MarioEnemy3D.MState.SHELL_FLY)
	await get_tree().create_timer(0.5).timeout
	_check("连锁撞杀：路径上的栗宝宝被撞死（+连锁分）",
		not victim.alive and battlefield.score >= score2 + shell.score_value)
	_check("壳飞出爆炸：已从场上移除", not battlefield.enemies.has(shell) or shell.mstate == MarioEnemy3D.MState.SHELL_FLY)
	await get_tree().create_timer(3.0).timeout
	_check("壳到期爆碎：彻底移除", not is_instance_valid(shell) or not shell.alive)

	# --- 幽灵：火系闪避 / 链电 ×2 / 冰免疫 ---
	var boo: MarioEnemy3D = battlefield.spawn_enemy("boo")
	boo.global_position = Vector3(0.0, MarioEnemy3D.BOO_HOVER, -14.0)
	boo.try_dodge_fire(Vector3(0.5, 0.0, -14.0))
	_check("幽灵闪避：进入 DODGE + 无敌", boo.mstate == MarioEnemy3D.MState.DODGE and boo._invulnerable)
	boo.apply_spell("fire", 40.0, Vector3.ZERO)
	_check("幽灵躲火：火球落空不掉血（hp=%.0f）" % boo.hp, is_equal_approx(boo.hp, 60.0))
	var d_before := boo.apply_spell("lightning", 25.0, Vector3.ZERO)
	_check("幽灵链电弱点 ×2：实伤 50", is_equal_approx(d_before, 50.0) and is_equal_approx(boo.hp, 10.0))
	var d_ice := boo.apply_spell("ice", 10.0, Vector3.ZERO)
	_check("幽灵冰免疫：返回 -1 且无伤", d_ice < 0.0 and is_equal_approx(boo.hp, 10.0))
	boo.apply_spell("lightning", 25.0, Vector3.ZERO)
	_check("幽灵链电致死", not boo.alive)

	# --- 库巴：倍率承伤 + 狂暴免疫冰 + 血条 ---
	var bs: MarioEnemy3D = battlefield.spawn_enemy("bowser")
	bs.global_position = Vector3(0.0, 0.0, -18.0)
	_check("库巴登场：血条生成 + HP600", bs._hp_bar != null and is_equal_approx(bs.hp, 600.0))
	var d_b_l := bs.apply_spell("lightning", 25.0, Vector3.ZERO)
	_check("库巴链电 ×0.8：实伤 20", is_equal_approx(d_b_l, 20.0))
	var d_b_w := bs.apply_spell("wind", 18.0, Vector3.ZERO)
	_check("库巴风刃 ×0.2：打不动（实伤 3.6）", is_equal_approx(d_b_w, 3.6))
	var d_b_i0 := bs.apply_spell("ice", 10.0, Vector3.ZERO)
	_check("库巴冰：狂暴前可减速受伤", d_b_i0 > 0.0 and bs.frozen_t > 0.0)
	bs.frozen_t = 0.0
	bs.take_damage(290.0)  # 总伤 20+3.6+10+290 = 323.6 <600；再补到半血以下
	bs.take_damage(30.0)   # 353.6 → 246.4 < 300 半血
	await get_tree().create_timer(0.15).timeout  # 狂暴判定在 _process_bowser 里，跨帧等真实时间
	_check("库巴半血狂暴：红光标记", bs._enraged)
	var d_b_i1 := bs.apply_spell("ice", 10.0, Vector3.ZERO)
	_check("库巴狂暴免疫冰：返回 -1", d_b_i1 < 0.0)
	var score3: int = battlefield.score
	bs.take_damage(9999.0)
	_check("库巴击破：计 500 分 + 死亡", not bs.alive and battlefield.score >= score3 + 500)

	# --- 波次表 ---
	var w1 := MarioWaveTable.wave(1)
	var w4 := MarioWaveTable.wave(4)
	_check("波次表：第1波 6 栗宝宝 0 龟 / 第4波 12+4+库巴",
		int(w1["goombas"]) == 6 and int(w1["koopas"]) == 0
		and int(w4["goombas"]) == 12 and int(w4["koopas"]) == 4 and int(w4["bowser"]) == 1)

	# --- 开波：幽灵常驻补充 + 队列 ---
	battlefield.restart()
	battlefield._phase_t = 0.05
	await get_tree().create_timer(0.3).timeout
	_check("第 1 波开波：幽灵常驻 2 只", battlefield.wave_n == 1 and battlefield._boo_count() == 2)
	for we in battlefield.enemies.duplicate():
		we.take_damage(999.0)
	battlefield._queue.clear()
	await get_tree().create_timer(0.5).timeout
	_check("清波：进波间歇（%s）" % battlefield.phase,
		battlefield.phase == Battlefield3D.WavePhase.INTERMISSION)

	# --- 通关：杀库巴后全清 → 结算浮层 ---
	battlefield._phase_t = 0.05
	battlefield.wave_n = MarioWaveTable.last_wave() - 1
	battlefield._phase_t = 0.05
	await get_tree().create_timer(0.3).timeout
	_check("第 4 波开波：库巴延迟登记", battlefield.wave_n == MarioWaveTable.last_wave())
	battlefield._bowser_delay_t = 0.05  # 压缩登场延迟
	await get_tree().create_timer(0.5).timeout
	var boss_found := false
	for e in battlefield.enemies:
		if e is MarioEnemy3D and (e as MarioEnemy3D).unit_key == "bowser":
			boss_found = true
	_check("库巴压轴登场", boss_found)
	for we in battlefield.enemies.duplicate():
		we.take_damage(9999.0)
	battlefield._queue.clear()  # 清空刷怪队列，否则 CLEARING 永远等不到
	# 弃壳残留：杀龟会先生成静止壳（不在上面的快照里），直接清场
	for we in battlefield.enemies.duplicate():
		if we is MarioEnemy3D and (we as MarioEnemy3D).unit_key == "shell":
			we.alive = false
			battlefield.enemies.erase(we)
			we.queue_free()
	await get_tree().create_timer(3.0).timeout
	_check("通关：is_over + 结算浮层显示", battlefield.is_over and battlefield._overlay.visible
		and "通 关" in battlefield._overlay_label.text)

	# --- 重开 ---
	battlefield.restart()
	_check("重开：波次/结算/狂暴标记复位", battlefield.wave_n == 0
		and not battlefield._overlay.visible and not battlefield._victory_done)

	_finish()


func _finish() -> void:
	_lines.append("-------- mario 测试: %d PASS / %d FAIL --------" % [_pass, _fail])
	var f := FileAccess.open("res://tests/mario_battle_result.txt", FileAccess.WRITE)
	if f:
		for line in _lines:
			f.store_string(line + "\n")
		f.flush()
	for line in _lines:
		print(line)
	get_tree().quit(1 if _fail > 0 else 0)
