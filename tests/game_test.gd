class_name GameTest
extends Node
## 守卫法阵迷你游戏逻辑测试（--game-test，headless）。
## 直接驱动 spawner/spell_manager/mini_game 的 API 验证游戏规则。
## 结果: tests/game_result.txt


var main: Node2D
var results: Array = []
var pass_count := 0
var fail_count := 0


func _ready() -> void:
	await _run()
	main.get_tree().quit(1 if fail_count > 0 else 0)


func _check(name: String, cond: bool) -> void:
	if cond:
		pass_count += 1
	else:
		fail_count += 1
	results.append("%s %s" % ["[PASS]" if cond else "[FAIL]", name])
	print("%s %s" % ["[PASS]" if cond else "[FAIL]", name])


func _s(norm: Vector2) -> Vector2:
	return Vector2(norm.x * 1280.0, norm.y * 960.0)


func _dead(e) -> bool:
	# 敌人被击杀后 0.6s 会 queue_free，断言时对象可能已释放
	return not is_instance_valid(e) or not e.alive


func _run() -> void:
	var spawner: EnemySpawner = main.spawner
	var sm: SpellManager = main.spell_manager
	var mg: MiniGame = main.mini_game
	await get_tree().create_timer(0.2).timeout

	# 1. 生成与移动
	var e1: GameEnemy = spawner.spawn()
	e1.position = Vector2(100, 480)
	var d0: float = e1.global_position.distance_to(spawner.ward_center)
	await get_tree().create_timer(0.8).timeout
	var d1: float = e1.global_position.distance_to(spawner.ward_center)
	_check("敌人向法阵移动 (%.0f→%.0f)" % [d0, d1], d1 < d0 - 20.0)

	# 2. 火球击杀 + 得分
	var kills0: int = mg.kills
	sm.cast("fireball", Vector2(100.0 / 1280.0, 480.0 / 960.0))
	await get_tree().create_timer(0.1).timeout
	_check("火球击杀敌人", _dead(e1))
	_check("击杀计分 (+%d)" % (mg.kills - kills0), mg.kills == kills0 + 1)

	# 3. 掌心火弹（快速施法）
	var e2: GameEnemy = spawner.spawn()
	e2.position = Vector2(1100, 300)
	sm.quick_shot(Vector2(900.0 / 1280.0, 300.0 / 960.0))
	await get_tree().create_timer(0.8).timeout
	_check("掌心火弹命中敌人", _dead(e2))

	# 4. 冰域减速
	var e3: GameEnemy = spawner.spawn()
	e3.position = Vector2(640, 200)
	sm.cast("ice_field", Vector2(0.5, 0.25))
	_check("冰域冻结敌人", e3.frozen_t > 0.0)

	# 5. 敌人触碰法阵扣血
	var hp0: int = mg.ward_hp
	var e4: GameEnemy = spawner.spawn()
	e4.position = spawner.ward_center
	await get_tree().create_timer(0.2).timeout
	_check("敌人撞法阵扣血 (%d→%d)" % [hp0, mg.ward_hp], mg.ward_hp == hp0 - 1)

	# 6. 法阵破碎 → 游戏结束
	mg.ward_hp = 1
	var e5: GameEnemy = spawner.spawn()
	e5.position = spawner.ward_center
	await get_tree().create_timer(0.2).timeout
	_check("法阵破碎进入结算", mg.is_over)
	_check("生成器停止", not spawner.active)

	# 7. 重开
	mg.restart()
	await get_tree().create_timer(0.1).timeout
	_check("重开恢复状态", not mg.is_over and mg.ward_hp == MiniGame.WARD_HP_MAX and mg.score == 0)

	var summary := "%d PASS / %d FAIL" % [pass_count, fail_count]
	print("-------- GAME 测试: %s --------" % summary)
	var f := FileAccess.open("res://tests/game_result.txt", FileAccess.WRITE)
	if f:
		f.store_string(summary + "\n")
		for r in results:
			f.store_string(r + "\n")
		f.flush()
