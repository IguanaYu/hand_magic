extends Node
## --mario-gallery：马里奥换皮版多张目检截图（需带窗口 GPU 渲染，headless 截不了）。
## 依次摆拍：波次开战巡逻 / 火球炸群 / 龟壳连锁 / 幽灵隐身闪避 / 链电劈幽灵 /
## 库巴登场咆哮 / 狂暴红光 / 击破金币雨 / 通关结算。输出 tests/mario_gallery_01..09.png 后退出。

var battlefield: BattlefieldMario3D


func _ready() -> void:
	battlefield.spawning = false
	battlefield._phase_t = 9999.0  # 锁在开场波间，不让波次逻辑加戏
	await get_tree().process_frame
	await _run()


## 本节点在战场之后处理，每帧盖掉"准备中 9999 s"的波间倒计时
func _process(_delta: float) -> void:
	if battlefield != null and battlefield.hud3d != null:
		battlefield.hud3d.wave_text = ""


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/mario_gallery_%s.png" % tag)
	print("GALLERY saved ", tag, " ", img.get_size())


func _clear_field() -> void:
	for e in battlefield.enemies.duplicate():
		battlefield.enemies.erase(e)
		e.queue_free()
	for f in battlefield.fx_layer.get_children():
		f.queue_free()
	battlefield.combo = 0
	battlefield._combo_t = 0.0


func _run() -> void:
	var sc: SpellCaster3D = battlefield.spell_caster

	# ===== 01 波次开战：横幅 + 栗宝宝一排巡逻进场 =====
	battlefield._show_banner("第 1/4 波　栗宝宝×6")
	for i in 6:
		var g := battlefield.spawn_enemy("goomba")
		g.global_position = Vector3(-10.0 + i * 4.0, 0.0, -12.0 - (i % 2) * 3.0)
	await get_tree().create_timer(0.55).timeout  # 横幅亮着 + 队伍走起来
	await _shot("01_wave_start")

	# ===== 02 火球炸群：4 只栗宝宝聚堆，起爆瞬间（压扁+尘土+爆炸球） =====
	_clear_field()
	for i in 4:
		var g2 := battlefield.spawn_enemy("goomba")
		g2.global_position = Vector3(-1.8 + i * 1.2, 0.0, -11.0 + (i % 2) * 1.0)
	await get_tree().create_timer(0.3).timeout
	sc.cast("fireball", battlefield.camera.unproject_position(Vector3(0.0, 0.5, -11.0)))
	await get_tree().create_timer(1.14).timeout  # 飞行 ~19m 起爆后 0.08s（压扁动画进行中）
	await _shot("02_fireball_boom")

	# ===== 03 龟壳连锁：弃壳 → 发射 → 沿途撞杀（"连锁!"飘字） =====
	_clear_field()
	var k := battlefield.spawn_enemy("koopa")
	k.global_position = Vector3(-6.0, 0.0, -12.0)
	await get_tree().create_timer(0.15).timeout
	k.apply_spell("fire", 40.0, Vector3.ZERO)  # 一段：弃壳
	await get_tree().create_timer(0.35).timeout
	var shell: MarioEnemy3D = null
	for e in battlefield.enemies:
		if e is MarioEnemy3D and (e as MarioEnemy3D).unit_key == "shell":
			shell = e
	for i in 3:
		var v := battlefield.spawn_enemy("goomba")
		v.global_position = Vector3(-2.0 + i * 3.0, 0.0, -12.0)  # 壳的必经之路
	shell.global_position = Vector3(-6.0, 0.0, -12.0)
	shell.apply_spell("fire", 40.0, Vector3(1, 0, 0))  # 二段：沿 +x 发射
	await get_tree().create_timer(0.30).timeout  # 飞 ~4.5m，撞杀第一只
	await _shot("03_shell_chain")

	# ===== 04 幽灵隐身闪避：火球临身，半透明侧闪 + "闪!" =====
	_clear_field()
	var boo := battlefield.spawn_enemy("boo")
	boo.global_position = Vector3(2.0, MarioEnemy3D.BOO_HOVER, -11.0)
	await get_tree().create_timer(0.25).timeout
	sc.cast("fireball", battlefield.camera.unproject_position(boo.aim_center()))
	await get_tree().create_timer(0.55).timeout  # 预警 0.32s 触发 + alpha 渐变 0.2s 完成
	await _shot("04_boo_dodge")

	# ===== 05 链电劈幽灵：×2 弱点（50 飘字）+ 天降折线 =====
	_clear_field()
	var b1 := battlefield.spawn_enemy("boo")
	b1.global_position = Vector3(-4.0, MarioEnemy3D.BOO_HOVER, -12.0)
	var b2 := battlefield.spawn_enemy("boo")
	b2.global_position = Vector3(4.0, MarioEnemy3D.BOO_HOVER + 0.5, -13.0)
	var g3 := battlefield.spawn_enemy("goomba")
	g3.global_position = Vector3(0.0, 0.0, -12.0)
	await get_tree().create_timer(0.2).timeout
	sc._cast_lightning({"point": Vector3(0.0, 2.0, -12.0)})
	await get_tree().create_timer(0.1).timeout  # 折线可见期 0.22s 内
	await _shot("05_lightning_boo")

	# ===== 06 库巴登场：深处压轴 + 头顶血条 + 咆哮缩放脉冲 =====
	_clear_field()
	var bs := battlefield.spawn_enemy("bowser")
	bs.global_position = Vector3(0.0, 0.0, -16.0)
	for i in 2:
		var gg := battlefield.spawn_enemy("goomba")
		gg.global_position = Vector3(-7.0 + i * 14.0, 0.0, -13.0)
	await get_tree().create_timer(0.8).timeout
	bs._roar_t = 0.05  # 强制咆哮
	await get_tree().create_timer(0.45).timeout  # 咆哮缩放脉冲进行中
	var bar: Label3D = bs._hp_bar
	print("HPBAR pos=", bar.global_position, " vis=", bar.visible, " in_tree=", bar.is_inside_tree(),
		" text=", bar.text, " psize=", bar.pixel_size, " fsize=", bar.font_size)
	await _shot("06_bowser_roar")

	# ===== 07 狂暴红光：打半血，红光泛体 + 血条 ~40% =====
	bs.take_damage(360.0)
	await get_tree().create_timer(0.5).timeout  # _process 判定狂暴
	await _shot("07_bowser_enrage")

	# ===== 08 击破金币雨：横幅 + 20 金币半空倾泻 =====
	# 接通波次链路：CLEARING + 第 4 波 → 杀库巴后自然走 _victory
	for e in battlefield.enemies.duplicate():
		if e is MarioEnemy3D and (e as MarioEnemy3D).unit_key == "goomba":
			e.take_damage(9999.0)
	battlefield.spawning = true
	battlefield.phase = Battlefield3D.WavePhase.CLEARING
	battlefield.wave_n = MarioWaveTable.last_wave()
	battlefield._bowser_spawned = true
	bs.take_damage(9999.0)
	await get_tree().create_timer(0.85).timeout  # 金币雨半空
	await _shot("08_coin_rain")

	# ===== 09 通关结算：金币落幕后弹出总分面板 =====
	await get_tree().create_timer(3.0).timeout  # _victory 内部 2.2s 后弹面板
	await _shot("09_victory")

	# ===== 10 风刃：竖直气浪墙扫过栗宝宝（重置结算浮层再摆拍） =====
	battlefield._overlay.visible = false
	battlefield.is_over = false
	battlefield.spawning = false
	_clear_field()
	for i in 3:
		var wg := battlefield.spawn_enemy("goomba")
		wg.global_position = Vector3(-2.0 + i * 2.0, 0.0, 2.0)  # 6m 内：风刃射程中
	await get_tree().create_timer(0.2).timeout
	sc._cast_wind_blade(battlefield.camera.unproject_position(Vector3(0.0, 0.8, 2.0)))
	await get_tree().create_timer(0.1).timeout  # 气浪墙扫到怪身上
	await _shot("10_wind_blade")

	# ===== 11 施法成功横幅：火球术大字弹出（元素配色+下划线） =====
	_clear_field()
	battlefield.cast_banner.pop("火球术", CastBanner.color_of("fireball"))
	await get_tree().create_timer(0.32).timeout  # 回弹+下划线展开完成
	await _shot("11_cast_banner")

	get_tree().quit(0)
