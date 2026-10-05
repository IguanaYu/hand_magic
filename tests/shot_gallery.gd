extends Node
## --shot-gallery：多张目检截图（需带窗口 GPU 渲染，headless 截不了）。
## 依次摆拍：地面小队对射 / 维京盘旋开火 / 医疗船空投 / 全家福 /
## 火球爆炸 / 冰域冻结 / 维京击落坠落。输出 tests/gallery_01..07.png 后退出。

var battlefield: Battlefield3D


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
	img.save_png("res://tests/gallery_%s.png" % tag)
	print("GALLERY saved ", tag, " ", img.get_size())


func _run() -> void:
	# ===== 01 地面小队：3 枪兵 + 2 掠夺者推进到停距，开火对射（曳光弹+枪口焰） =====
	var slots := [
		["marine", -7.0, -12.0], ["marine", -3.5, -9.0], ["marauder", 0.0, -13.0],
		["marine", 3.5, -9.5], ["marauder", 7.0, -12.5],
	]
	for s in slots:
		var e := battlefield.spawn_enemy(s[0], false)
		e.global_position = Vector3(s[1], 0.0, s[2])
	await get_tree().create_timer(2.6).timeout  # HALT→FIRE，打出几轮曳光弹
	await _shot("01_ground_squad")

	# ===== 02 维京战机：正前方 17m 半圆盘旋开火 =====
	var vk := battlefield.spawn_enemy("viking")
	vk.set_orbit(Vector3(0.0, 0.0, -4.0), 17.0, PI * 0.8, 1.0)
	vk.global_position = Vector3(13.0, 7.5, -16.0)
	vk.speed = 40.0
	await get_tree().create_timer(1.8).timeout  # FLY_IN→STRAFE 并开火
	await _shot("02_viking_strafe")

	# ===== 03 医疗船空投：飞到阵前上空悬停，枪兵从天而降+落地扬尘 =====
	var md := battlefield.spawn_enemy("medivac")
	md.set_drop_zone(Vector3(1.0, 0.0, -10.0))
	md.global_position = Vector3(28.0, 10.0, -32.0)
	md.speed = 40.0
	await get_tree().create_timer(1.6).timeout  # FLY_IN→HOVER_DROP 开始卸货
	await get_tree().create_timer(1.1).timeout  # 2-3 只落地/半空
	await _shot("03_medivac_drop")

	# ===== 04 全家福：地面 + 空中同框 =====
	await _shot("04_all_together")

	# ===== 05 火球爆炸瞬间（人群中心） =====
	battlefield.spell_caster.cast("fireball", Vector2(640.0, 620.0))
	await get_tree().create_timer(1.05).timeout  # 飞行 ~18m/s×1s 到人群起爆
	await _shot("05_fireball_boom")

	# ===== 06 冰域：幸存者裹蓝冰壳 =====
	battlefield.spell_caster._cast_ice_field(Vector3(0.0, 0.0, -10.0))
	await get_tree().create_timer(0.45).timeout
	await _shot("06_ice_frozen")

	# ===== 07 维京被击落：空中爆炸+残骸起火坠落 =====
	vk.take_damage(99999.0)
	await get_tree().create_timer(0.4).timeout
	await _shot("07_viking_down")

	get_tree().quit(0)
