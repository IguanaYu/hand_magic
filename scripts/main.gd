extends Node2D
## RuneHand 主场景（M1 起）：
## 默认 = 3D 第一人称战场（battlefield_3d）；--ward = 守卫法阵迷你游戏（M0.5）；
## --e2e-test = 练习靶模式（测试用）；--anim-probe = GLB 动画资产验证。
## 快捷键：F1 切 HUD / R 重开 / ESC 退出 / 无摄像头时鼠标兜底。

## 调试期：法力免费（用户要求，测试手感不受蓝条限制；正式版改 false）
const MANA_FREE := true


const TARGET_SLOTS := [
	Vector2(0.25, 0.28), Vector2(0.75, 0.28),
	Vector2(0.22, 0.68), Vector2(0.78, 0.68),
]

var tracker: HandTracker
var fsm: GestureFSM
var pose_classifier := PoseClassifier.new()
var spell_manager: SpellManager
var skeleton: SkeletonRenderer
var trail: TrailRenderer
var ward: WardRing
var hud: DebugHud
var spawner: EnemySpawner
var mini_game: MiniGame
var battle3d: Battlefield3D
var codex: CodexPanel
var mode3d := false

var _cam_container: SubViewportContainer
var _cam_viewport: SubViewport
var _cam_texture: TextureRect
var _cam_pip_panel: Panel
var _latest_hands: Array = []
var _camera_alive := false
var _mouse_fallback_note := false
var _no_camera_t := 0.0
var _mouse_down_pos := Vector2.ZERO
var _mouse_was_down := false
var _shield_hold_t := 0.0
var _overlay: ColorRect
var _overlay_label: Label
var _overlay_layer: CanvasLayer
var practice_mode := false

var _pose_log: FileAccess
var _last_logged_pose := -1
var _last_logged_state := ""
var _gui_test := false
var _gui_dump_t := 0.0
var _gui_shot_i := 0


## --gui-test：每 0.5s 落盘完整游戏状态（供 OS 级输入注入测试验证用）
func _gui_dump() -> void:
	var enemies: Array = []
	if mini_game != null and spawner != null:
		for e in spawner.enemy_layer.get_children():
			if e is GameEnemy and e.alive:
				enemies.append({"x": int(e.global_position.x), "y": int(e.global_position.y)})
	var state := {
		"t": Time.get_ticks_msec(),
		"elapsed": roundf(mini_game.elapsed if mini_game else 0.0),
		"score": mini_game.score if mini_game else 0,
		"kills": mini_game.kills if mini_game else 0,
		"ward_hp": mini_game.ward_hp if mini_game else 0,
		"is_over": mini_game.is_over if mini_game else false,
		"mana": roundi(fsm.mana),
		"fsm": fsm.state_name(),
		"cast": fsm.cast_count,
		"casts_total": spell_manager.cast_total,
		"fizzle": fsm.fizzle_count,
		"hits": spell_manager.hit_total,
		"enemies": enemies,
	}
	var f := FileAccess.open("res://tests/gui_state.txt", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state))
		f.flush()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	practice_mode = "--e2e-test" in args
	if "--anim-probe" in args:
		add_child(load("res://tests/anim_probe.gd").new())
		return
	if "--anim-probe-mario" in args:
		add_child(load("res://tests/anim_probe_mario.gd").new())
		return
	if "--smoke-test" in args:
		var code := SmokeTest.run()
		get_tree().quit(code)
		return
	if "--robust-test" in args:
		var rcode := RobustTest.run()
		get_tree().quit(rcode)
		return
	if "--game-test" in args:
		_build_scene()
		_wire_signals()
		var gt := GameTest.new()
		gt.main = self
		add_child(gt)
		return
	if "--e2e-test" in args:
		_build_scene()
		_wire_signals()
		_open_pose_log()
		var e2e := E2ETest.new()
		e2e.main = self
		add_child(e2e)
		return
	if "--camera-test" in args:
		_build_scene()
		_wire_signals()
		hud.set_message("摄像头管线测试中（8秒）…")
		get_tree().create_timer(8.0).timeout.connect(_finish_camera_test)
		return
	if "--shot3d" in args:
		_build_3d("--mario" in args)
		# --codex 附带参数：截图前打开手势图鉴（目检面板布局）
		if "--codex" in args:
			codex.open()
		if "--mario" in args:
			# 马里奥全家福：栗宝宝排排站 + 慢慢龟 + 幽灵 + 库巴压轴
			for i in 5:
				var g := battle3d.spawn_enemy("goomba")
				g.global_position = Vector3(-8.0 + i * 4.0, 0.0, -12.0)
			var kp := battle3d.spawn_enemy("koopa")
			kp.global_position = Vector3(6.0, 0.0, -16.0)
			var b1 := battle3d.spawn_enemy("boo")
			b1.global_position = Vector3(-6.0, MarioEnemy3D.BOO_HOVER, -18.0)
			var b2 := battle3d.spawn_enemy("boo")
			b2.global_position = Vector3(7.0, MarioEnemy3D.BOO_HOVER + 0.6, -21.0)
			var bs := battle3d.spawn_enemy("bowser")
			bs.global_position = Vector3(0.0, 0.0, -25.0)
		else:
			# 预置敌人在镜头前，用于目检模型/朝向/动画
			for i in 7:
				var key := "marauder" if i % 3 == 2 else "marine"
				var e := battle3d.spawn_enemy(key)
				e.global_position = battle3d.PLAYER_POS + Vector3(-12.0 + i * 4.0, 0.0, -13.0 - (i % 3) * 3.0)
			# M1.6 空军目检：维京到位盘旋 + 医疗船进场空投（截图时恰有枪兵空降）
			var vk := battle3d.spawn_enemy("viking")
			vk.global_position = vk._fly_target
			vk.speed = 60.0
			var md := battle3d.spawn_enemy("medivac")
			md.global_position = md._fly_target - Vector3(0.0, 0.0, 6.0)
			md.speed = 60.0
		# 0.7s 施放火球，1.55s 截图（爆炸瞬间 + 敌人已开火）
		get_tree().create_timer(0.7).timeout.connect(func():
			battle3d.spell_caster.cast("fireball", Vector2(640, 520)))
		get_tree().create_timer(1.55).timeout.connect(_take_3d_shot)
		return
	if "--shot-gallery" in args:
		_build_3d()
		var sg: Node = load("res://tests/shot_gallery.gd").new()
		sg.battlefield = battle3d
		add_child(sg)
		return
	if "--mario-gallery" in args:
		_build_3d(true)
		var mg: Node = load("res://tests/mario_shot_gallery.gd").new()
		mg.battlefield = battle3d
		add_child(mg)
		return
	if "--battle3d-test" in args:
		_build_3d()
		var bt: Node = load("res://tests/battle3d_test.gd").new()
		bt.battlefield = battle3d
		add_child(bt)
		return
	if "--mario-test" in args:
		_build_3d(true)
		var mt: Node = load("res://tests/mario_battle_test.gd").new()
		mt.battlefield = battle3d
		add_child(mt)
		return
	_gui_test = "--gui-test" in args
	# 默认 = 3D 战场（--mario 切马里奥换皮）；--ward = 旧守卫法阵（M0.5）；e2e/practice 走练习靶
	mode3d = not practice_mode and "--ward" not in args
	if mode3d:
		_build_3d("--mario" in args)
		return
	_build_scene()
	_wire_signals()


func _build_3d(mario := false) -> void:
	battle3d = BattlefieldMario3D.new() if mario else Battlefield3D.new()
	battle3d.name = "Battlefield3D"
	add_child(battle3d)
	# 摄像头管线：离屏 SubViewport（modulate 全透明——只供手部追踪读帧，不上屏）。
	# stretch 必须关：stretch 模式下容器会把视口压成自身尺寸（Node2D 父级下解析为
	# 2x2 占位），读回帧全是空图，MediaPipe 永远识别不到手。
	_cam_container = SubViewportContainer.new()
	_cam_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cam_container.stretch = false
	_cam_container.modulate = Color(1, 1, 1, 0)
	add_child(_cam_container)
	_cam_viewport = SubViewport.new()
	_cam_viewport.size = Vector2i(640, 480)
	_cam_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cam_container.add_child(_cam_viewport)
	_cam_texture = TextureRect.new()
	_cam_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cam_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cam_texture.flip_h = true
	_cam_viewport.add_child(_cam_texture)
	# 手势渲染层 + 调试 HUD（挂在战场 CanvasLayer 上，叠在 3D 画面之上）
	trail = TrailRenderer.new()
	battle3d.ui_layer.add_child(trail)
	skeleton = SkeletonRenderer.new()
	battle3d.ui_layer.add_child(skeleton)
	hud = DebugHud.new()
	battle3d.ui_layer.add_child(hud)
	hud.set_hint("H 手势图鉴 ｜ F1 调试 ｜ F2 摄像头预览 ｜ R 重开")
	hud.set_message("按 H 查看每个法术怎么画")
	# 摄像头预览小窗（F2 切换）：直接看追踪用的画面——手在不在镜头里一目了然
	_cam_pip_panel = Panel.new()
	_cam_pip_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_cam_pip_panel.offset_left = -258.0
	_cam_pip_panel.offset_top = -198.0
	_cam_pip_panel.offset_right = -8.0
	_cam_pip_panel.offset_bottom = -8.0
	var pip_style := StyleBoxFlat.new()
	pip_style.bg_color = Color(0.02, 0.03, 0.06, 0.55)
	pip_style.border_color = Color(0.35, 0.9, 1.0, 0.75)
	pip_style.set_border_width_all(2)
	pip_style.set_corner_radius_all(6)
	pip_style.set_content_margin_all(2)
	_cam_pip_panel.add_theme_stylebox_override("panel", pip_style)
	hud.add_child(_cam_pip_panel)
	var pip := TextureRect.new()
	pip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pip.texture = _cam_viewport.get_texture()
	_cam_pip_panel.add_child(pip)
	tracker = HandTracker.new()
	add_child(tracker)
	fsm = GestureFSM.new()
	add_child(fsm)
	codex = CodexPanel.new()
	codex.fsm = fsm
	battle3d.add_child(codex)
	_wire_3d_signals()


func _wire_3d_signals() -> void:
	tracker.hands_updated.connect(_on_hands_updated)
	tracker.tracker_message.connect(func(msg): hud.set_message(msg))
	fsm.drawing_updated.connect(func(pts): trail.set_points(pts))
	fsm.cast_performed.connect(_on_3d_cast)
	fsm.quick_shot_performed.connect(_on_3d_quick_shot)
	fsm.fizzle.connect(_on_fizzle)
	# 清波奖励：回 30 法力（波间喘息）
	battle3d.wave_cleared.connect(func(_n):
		if fsm != null:
			fsm.mana = minf(GestureFSM.MANA_MAX, fsm.mana + 30.0))
	tracker.setup(_cam_viewport, _cam_texture)


func _on_3d_cast(spell_id: String, anchor: Vector2, _score: float) -> void:
	trail.begin_fade()
	var vp := _view_size()
	battle3d.spell_caster.cast(spell_id, Vector2(anchor.x * vp.x, anchor.y * vp.y))


func _on_3d_quick_shot(_anchor: Vector2) -> void:
	battle3d.spell_caster.cast("quick_shot", Vector2.ZERO)
	hud.set_message("掌心火弹！")


func _view_size() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x < 100.0:
		vp = Vector2(1280, 960)  # headless 回退
	return vp


func _build_scene() -> void:
	# 摄像头画面（SubViewport 读回方案，见 hand_tracker.gd）；stretch=false 同 _build_3d
	_cam_container = SubViewportContainer.new()
	_cam_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cam_container.stretch = false
	add_child(_cam_container)

	_cam_viewport = SubViewport.new()
	_cam_viewport.size = Vector2i(640, 480)
	_cam_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cam_container.add_child(_cam_viewport)

	_cam_texture = TextureRect.new()
	_cam_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cam_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cam_texture.flip_h = true
	_cam_viewport.add_child(_cam_texture)

	# 压暗层：保证魔法特效在真实画面上的可读性（GDD §9.1）
	var darken := ColorRect.new()
	darken.set_anchors_preset(Control.PRESET_FULL_RECT)
	darken.color = Color(0.02, 0.03, 0.08, 0.35)
	add_child(darken)

	ward = WardRing.new()
	add_child(ward)

	hud = DebugHud.new()
	add_child(hud)

	var target_layer := Node2D.new()
	target_layer.name = "Targets"
	add_child(target_layer)

	spell_manager = SpellManager.new()
	spell_manager.name = "Spells"
	spell_manager.target_layer = target_layer
	add_child(spell_manager)
	var fx_layer := Node2D.new()
	fx_layer.name = "FX"
	add_child(fx_layer)
	spell_manager.fx_layer = fx_layer

	if practice_mode:
		for slot in TARGET_SLOTS:
			var dummy := TargetDummy.new()
			dummy.position = Vector2(slot.x * 1280, slot.y * 960)
			target_layer.add_child(dummy)
	else:
		# M0.5 守卫法阵：敌人层 + 生成器 + 游戏状态
		var enemy_layer := Node2D.new()
		enemy_layer.name = "Enemies"
		add_child(enemy_layer)
		spawner = EnemySpawner.new()
		spawner.enemy_layer = enemy_layer
		add_child(spawner)
		spell_manager.enemy_layer = enemy_layer
		mini_game = MiniGame.new()
		mini_game.name = "MiniGame"
		mini_game.setup(spawner, enemy_layer, hud)
		add_child(mini_game)
		# 游戏结束浮层
		_overlay_layer = CanvasLayer.new()
		_overlay_layer.layer = 20
		add_child(_overlay_layer)
		_overlay = ColorRect.new()
		_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay.color = Color(0.01, 0.01, 0.05, 0.75)
		_overlay.visible = false
		_overlay_layer.add_child(_overlay)
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

	trail = TrailRenderer.new()
	add_child(trail)

	skeleton = SkeletonRenderer.new()
	add_child(skeleton)

	if practice_mode:
		hud.set_hint("握拳聚气 → 伸食指画符 → 张掌施放　|　◯圆=火球　Z=链电　△=冰域　/=风刃　|　F1 HUD　R 重置　ESC 退出")
	else:
		hud.set_hint("握拳→张掌 = 掌心火弹　|　握拳→画◯→张掌 = 火球AoE　|　Z=链电 △=冰域(减速) /=风刃　|　R 重开　ESC 退出")

	tracker = HandTracker.new()
	add_child(tracker)
	fsm = GestureFSM.new()
	add_child(fsm)


func _wire_signals() -> void:
	tracker.hands_updated.connect(_on_hands_updated)
	tracker.tracker_message.connect(func(msg): hud.set_message(msg))
	fsm.drawing_updated.connect(func(pts): trail.set_points(pts))
	fsm.cast_performed.connect(_on_cast)
	fsm.quick_shot_performed.connect(_on_quick_shot)
	fsm.fizzle.connect(_on_fizzle)
	fsm.mana_changed.connect(func(m): ward.mana_ratio = m / GestureFSM.MANA_MAX)
	spell_manager.spell_hit.connect(func(spell_id, n):
		hud.set_message("%s 命中 %d 个目标！" % [GestureFSM.SPELL_NAME.get(spell_id, spell_id), n]))
	tracker.setup(_cam_viewport, _cam_texture)
	if mini_game != null:
		spell_manager.spell_hit.connect(func(_id, _n): mini_game.state_dirty.emit())
		spawner.enemy_spawned.connect(mini_game.register_enemy)
		mini_game.game_over.connect(_on_game_over)
		mini_game.state_dirty.connect(_refresh_game_ui)
		_refresh_game_ui()


func _on_quick_shot(anchor: Vector2) -> void:
	spell_manager.quick_shot(anchor)
	hud.set_message("掌心火弹！")


func _on_game_over(score: int) -> void:
	_overlay.visible = true
	_overlay_label.text = "法阵破碎！\n\n得分 %d　最佳 %d\n击杀 %d　存活 %.0f 秒\n\n按 R 重新开始" % [
		score, mini_game.best, mini_game.kills, mini_game.elapsed]
	_refresh_game_ui()


func _refresh_game_ui() -> void:
	if mini_game == null or ward == null:
		return
	ward.hp_ratio = float(mini_game.ward_hp) / float(MiniGame.WARD_HP_MAX)


func _on_hands_updated(hands: Array) -> void:
	_latest_hands = hands
	if hands.size() > 0:
		_camera_alive = true


func _on_cast(spell_id: String, anchor: Vector2, score: float) -> void:
	trail.begin_fade()
	spell_manager.cast(spell_id, anchor)
	hud.set_message("%s！识别得分 %.2f" % [GestureFSM.SPELL_NAME.get(spell_id, spell_id), score])


func _on_fizzle(reason: String) -> void:
	trail.begin_fade()
	hud.set_message("法术失败：%s" % reason)


func _process(delta: float) -> void:
	if mode3d:
		_process_3d(delta)
		return
	if ward == null:
		return  # 探针等未完整构建的模式
	var vp := get_viewport_rect().size
	if vp.x < 100.0:
		vp = Vector2(1280, 960)  # headless 无窗口时视口为 64x64，回退到设计分辨率
	ward.view_size = vp
	skeleton.view_size = vp
	trail.view_size = vp
	spell_manager.view_size = vp
	if spawner != null:
		spawner.view_size = vp
		spawner.ward_center = vp * 0.5
		spawner.ward_radius = minf(vp.x, vp.y) * 0.12

	var pose := PoseClassifier.Pose.NONE
	var hand_present := false
	var index_tip := Vector2.ZERO
	var anchor := Vector2(0.5, 0.5)

	if _latest_hands.size() > 0:
		var hand: Dictionary = _latest_hands[0]
		hand_present = true
		pose = pose_classifier.classify(hand.get("points", []))
		index_tip = hand.get("index_tip", Vector2.ZERO)
		anchor = hand.get("palm", Vector2(0.5, 0.5))
	else:
		pose_classifier.reset()
		# 无摄像头兜底：鼠标左键=聚气，按住移动=画符，松开=施放/快速喷火（GDD §3.5 键鼠兜底）
		var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var m := get_viewport().get_mouse_position() / vp
		if down and not _mouse_was_down:
			_mouse_down_pos = m
		_mouse_was_down = down
		if down:
			hand_present = true
			if fsm.state == GestureFSM.State.IDLE:
				pose = PoseClassifier.Pose.FIST
			elif fsm.state == GestureFSM.State.CHARGE and (m - _mouse_down_pos).length() < 0.015:
				pose = PoseClassifier.Pose.FIST  # 原地按住不动画符 → 松开即掌心火弹
			else:
				pose = PoseClassifier.Pose.DRAWING
			index_tip = m
			anchor = m
		elif fsm.state == GestureFSM.State.DRAWING:
			hand_present = true
			pose = PoseClassifier.Pose.PALM
			index_tip = get_viewport().get_mouse_position() / vp
			anchor = index_tip
		elif fsm.state == GestureFSM.State.CHARGE:
			hand_present = true
			pose = PoseClassifier.Pose.PALM  # 松开 = 快速喷火
			index_tip = m
			anchor = m

	fsm.update(pose, hand_present, index_tip, anchor, delta)

	# 渲染层同步
	skeleton.set_hands(_latest_hands)
	skeleton.state_color = _state_color()

	# 无摄像头提示（4 秒后提示鼠标兜底）
	if not _camera_alive:
		_no_camera_t += delta
		if _no_camera_t > 4.0 and not _mouse_fallback_note:
			_mouse_fallback_note = true
			hud.set_message("未检测到摄像头——鼠标兜底：点按=掌心火弹，按住画圈=火球")

	_update_hud(delta)
	_log_pose(pose)
	if _gui_test:
		_gui_dump_t += delta
		if _gui_dump_t >= 0.5:
			_gui_dump_t = 0.0
			_gui_dump()


func _state_color() -> Color:
	match fsm.state:
		GestureFSM.State.CHARGE: return Color(1.0, 0.75, 0.25, 0.8)
		GestureFSM.State.DRAWING: return Color(0.4, 0.95, 1.0, 0.9)
		GestureFSM.State.COOLDOWN: return Color(0.7, 0.7, 0.8, 0.6)
		_: return Color(0.6, 0.85, 1.0, 0.55)


## M1.3：3D 模式的手势主循环（与 2D 版同构：姿势判定 → FSM → 渲染同步 → 护盾/法力）
func _process_3d(delta: float) -> void:
	var vp := _view_size()
	skeleton.view_size = vp
	trail.view_size = vp

	var pose := PoseClassifier.Pose.NONE
	var hand_present := false
	var index_tip := Vector2.ZERO
	var anchor := Vector2(0.5, 0.5)

	if _latest_hands.size() > 0:
		var hand: Dictionary = _latest_hands[0]
		hand_present = true
		pose = pose_classifier.classify(hand.get("points", []))
		index_tip = hand.get("index_tip", Vector2.ZERO)
		anchor = hand.get("palm", Vector2(0.5, 0.5))
	else:
		pose_classifier.reset()
		# 鼠标兜底：左键=聚气/画符，右键=护盾
		var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var m := get_viewport().get_mouse_position() / vp
		if down and not _mouse_was_down:
			_mouse_down_pos = m
		_mouse_was_down = down
		if down:
			hand_present = true
			if fsm.state == GestureFSM.State.IDLE:
				pose = PoseClassifier.Pose.FIST
			elif fsm.state == GestureFSM.State.CHARGE and (m - _mouse_down_pos).length() < 0.015:
				pose = PoseClassifier.Pose.FIST
			else:
				pose = PoseClassifier.Pose.DRAWING
			index_tip = m
			anchor = m
		elif fsm.state == GestureFSM.State.DRAWING:
			hand_present = true
			pose = PoseClassifier.Pose.PALM
			index_tip = m
			anchor = m
		elif fsm.state == GestureFSM.State.CHARGE:
			hand_present = true
			pose = PoseClassifier.Pose.PALM
			index_tip = m
			anchor = m

	fsm.update(pose, hand_present, index_tip, anchor, delta)
	if MANA_FREE:
		fsm.mana = GestureFSM.MANA_MAX  # 调试期法力免费
	skeleton.set_hands(_latest_hands)
	skeleton.state_color = _state_color()

	# 护盾：空闲持续张掌 ≥0.3s 或按住右键；进入施法状态立即撤盾
	var shield_want := false
	if not battle3d.is_over:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			shield_want = true
		elif pose == PoseClassifier.Pose.PALM and fsm.state == GestureFSM.State.IDLE:
			_shield_hold_t += delta
			if _shield_hold_t >= 0.3:
				shield_want = true
		else:
			_shield_hold_t = 0.0
	if fsm.state != GestureFSM.State.IDLE:
		_shield_hold_t = 0.0
		shield_want = false
	if shield_want and fsm.mana > 1.0:
		battle3d.shield_up = true
		fsm.mana = maxf(0.0, fsm.mana - 12.0 * delta)
		if fsm.mana <= 0.0:
			battle3d.shield_up = false
			hud.set_message("法力耗尽，护盾破碎！")
	else:
		battle3d.shield_up = false
	battle3d.mana_ratio = fsm.mana / GestureFSM.MANA_MAX

	if not _camera_alive:
		_no_camera_t += delta
		if _no_camera_t > 4.0 and not _mouse_fallback_note:
			_mouse_fallback_note = true
			hud.set_message("未检测到摄像头——鼠标兜底：按住画符施法，右键护盾")
	_update_hud(delta)


func _update_hud(_delta: float) -> void:
	var last := fsm.last_result
	var diag := tracker.diagnostics()
	var cam := str(diag.get("camera", ""))
	var sent := int(diag.get("frames_sent", 0))
	var recv := int(diag.get("results_received", 0))
	# 管线判定：定位「没手势」卡在哪一环（摄像头→帧→识别→见手）
	var verdict := "追踪中"
	if cam.is_empty():
		verdict = "摄像头未接入"
	elif sent == 0:
		verdict = "摄像头无帧"
	elif recv == 0:
		verdict = "识别无回调"
	elif int(diag.get("hands_frames", 0)) == 0:
		verdict = "未见手（对准镜头）"
	var info := {
		"追踪": verdict,
		"摄像头": cam if not cam.is_empty() else "—",
		"管线": "送 %d / 回 %d / 弃 %d" % [sent, recv, int(diag.get("frames_dropped", 0))],
		"状态": fsm.state_name(),
		"姿势": PoseClassifier.pose_name(pose_classifier.stable_pose()),
		"延迟": "%.0f ms" % tracker.latency_ms,
		"FPS": Engine.get_frames_per_second(),
		"手": "%d" % _latest_hands.size(),
		"法力": "%.0f" % fsm.mana,
		"识别": "%s (%.2f)" % [GestureFSM.SPELL_NAME.get(str(last.get("name", "")), last.get("name", "—")), float(last.get("score", 0.0))],
		"施放/失败": "%d / %d" % [fsm.cast_count, fsm.fizzle_count],
	}
	if spell_manager != null:
		info["命中"] = "%d" % spell_manager.hit_total
	if battle3d != null:
		info["HP"] = "%.0f" % battle3d.player_hp
		info["得分"] = "%d（击杀 %d）" % [battle3d.score, battle3d.kills]
		info["场上敌人"] = "%d" % battle3d._alive_count()
	if mini_game != null:
		info["得分"] = "%d（击杀 %d）" % [mini_game.score, mini_game.kills]
		info["法阵"] = "%d/%d" % [mini_game.ward_hp, MiniGame.WARD_HP_MAX]
		info["存活"] = "%.0f s" % mini_game.elapsed
		info["场上敌人"] = "%d" % mini_game.alive_enemies()
	hud.set_info(info)


func _take_3d_shot() -> void:
	_dump_enemy_anim()
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/shot3d.png")
	print("SHOT3D saved ", img.get_size())
	if "--shot3d-twice" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.4).timeout
		_dump_enemy_anim()
		var img2 := get_viewport().get_texture().get_image()
		img2.save_png("res://tests/shot3d_b.png")
		print("SHOT3D_B saved")
	get_tree().quit(0)


func _dump_enemy_anim() -> void:
	for e in battle3d.enemies:
		var ap: AnimationPlayer = e._ap
		if ap != null:
			print("ENEMY ", e.unit_key, " state=", e.state_name(), " anim=", ap.current_animation,
				" pos=", "%.3f" % ap.current_animation_position, " playing=", ap.is_playing())
		# 马里奥朝向验证：walk_dir（+1=朝世界+x=屏幕右）与位置对照截图
		if e is MarioEnemy3D:
			var me := e as MarioEnemy3D
			print("MARIO ", me.unit_key, " walk_dir=", me.walk_dir, " pos=", me.global_position)


func _finish_camera_test() -> void:
	var d := tracker.diagnostics()
	# 追踪用原始画面落盘——肉眼确认渲染目标里到底有没有图像
	var cam_img := _cam_viewport.get_texture().get_image()
	if cam_img != null and not cam_img.is_empty():
		cam_img.save_png("res://tests/camera_shot.png")
	var lines: Array = [
		"camera=" + str(d.get("camera", "")),
		"datatype=" + str(d.get("datatype", -1)),
		"frames_sent=%d" % d.get("frames_sent", 0),
		"frames_dropped=%d" % d.get("frames_dropped", 0),
		"results_received=%d" % d.get("results_received", 0),
		"hands_frames=%d" % d.get("hands_frames", 0),
		"latency_ms=%.1f" % d.get("latency_ms", 0.0),
	]
	var ok: bool = d.get("results_received", 0) > 0
	lines.append("verdict=" + ("PASS" if ok else "FAIL:无识别回调"))
	var f := FileAccess.open("res://tests/camera_result.txt", FileAccess.WRITE)
	if f:
		for line in lines:
			f.store_string(line + "\n")
		f.flush()
	get_tree().quit(0 if ok else 2)


func _log_pose(pose: int) -> void:
	if _pose_log == null:
		return
	var state := fsm.state_name()
	if pose != _last_logged_pose or state != _last_logged_state:
		_last_logged_pose = pose
		_last_logged_state = state
		_pose_log.store_string("%.3f pose=%s state=%s hands=%d\n" % [
			Time.get_ticks_msec() / 1000.0, PoseClassifier.pose_name(pose), state, _latest_hands.size()])
		_pose_log.flush()


func _open_pose_log() -> void:
	if "--e2e-test" in OS.get_cmdline_user_args():
		_pose_log = FileAccess.open("res://tests/pose_log.txt", FileAccess.WRITE)


func _input(event: InputEvent) -> void:
	# --gui-test 输入探针：验证 OS 级消息注入是否到达游戏输入系统
	if _gui_test and (event is InputEventMouseButton or event is InputEventKey or event is InputEventMouseMotion):
		var f := FileAccess.open("res://tests/gui_input_log.txt", FileAccess.READ_WRITE if FileAccess.file_exists("res://tests/gui_input_log.txt") else FileAccess.WRITE_READ)
		if f:
			f.seek_end()
			f.store_string("%s %s\n" % [Time.get_ticks_msec(), str(event).left(120)])
			f.flush()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				hud.toggle()
			KEY_F2:
				if _cam_pip_panel != null:
					_cam_pip_panel.visible = not _cam_pip_panel.visible
			KEY_R:
				if battle3d != null:
					battle3d.restart()
					if fsm != null:
						fsm.reset()
					hud.set_message("重新开始！")
				elif mini_game != null:
					mini_game.restart()
					_overlay.visible = false
					fsm.reset()
					hud.set_message("重新开始！")
				else:
					fsm.cast_count = 0
					fsm.fizzle_count = 0
					spell_manager.hit_total = 0
					spell_manager.cast_total = 0
					hud.set_message("统计已重置")
			KEY_ESCAPE:
				get_tree().quit()
