class_name RuneRecordPanel
extends CanvasLayer
## 符文录制面板（G / HUD 设置按钮）：玩家给每个法术录制自己的画符样本。
## 打开时游戏暂停（战场 DISABLE 冻结敌人），但手势管线继续跑——
## 画符仍走原状态机（伸指起笔/握拳收笔），完成的一笔存为样本并即时注入识别器。
## 内置模板始终参与匹配：不录制也完全能玩。
## 与图鉴面板共用"暂停+ALWAYS"范式；open_guard 防止两个面板同时打开。


var fsm: GestureFSM          # main 注入
var store: RuneSamples       # main 注入（已加载存档）
var main_node: Node          # main（暂停期间转 ALWAYS，驱动手势管线）
var battle: Node             # Battlefield3D（暂停期间 DISABLE 冻结敌人）
var trail: TrailRenderer     # 拖尾（暂停期间 ALWAYS 保实时轨迹可见）
var open_guard: Callable     # 返回 true 时禁止打开（互斥另一面板）

var _open := false
var _selected := ""          # 当前录制的 spell_id
var _root: Control
var _select_view: Control
var _record_view: Control
var _status: Label
var _count_label: Label
var _last_stroke: StrokeThumb
var _buttons: Array[Button] = []


func _init() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build()


func is_open() -> bool:
	return _open


func selected_spell() -> String:
	return _selected


## 鼠标是否悬停在面板按钮上：主循环据此跳过鼠标兜底的姿势合成，
## 避免点按钮被当成画符（摄像头玩家不受影响）
func is_pointer_over_ui() -> bool:
	for b in _buttons:
		if b != null and b.is_hovered():
			return true
	return false


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	if open_guard.is_valid() and open_guard.call():
		return
	_open = true
	_root.visible = true
	_show_select()
	get_tree().paused = true
	_set_pipeline_active(true)
	if fsm != null:
		fsm.reset()


func close() -> void:
	if not _open:
		return
	_open = false
	_selected = ""
	_root.visible = false
	_set_pipeline_active(false)
	get_tree().paused = false
	if fsm != null:
		fsm.reset()


func _set_pipeline_active(active: bool) -> void:
	if main_node != null:
		main_node.process_mode = Node.PROCESS_MODE_ALWAYS if active else Node.PROCESS_MODE_INHERIT
	if battle != null:
		battle.process_mode = Node.PROCESS_MODE_DISABLED if active else Node.PROCESS_MODE_INHERIT
	if trail != null:
		trail.process_mode = Node.PROCESS_MODE_ALWAYS if active else Node.PROCESS_MODE_INHERIT


## 测试/按钮共用：直接进入某法术的录制态
func select_spell(spell_id: String) -> void:
	_selected = spell_id
	_select_view.visible = false
	_record_view.visible = true
	_update_record_labels("画你的【%s】——伸指起笔，画完握拳收笔（鼠标：按住左键画，松开收）" % _spell_name(spell_id))


func _spell_name(spell_id: String) -> String:
	for e in SpellCodex.entries():
		if e["id"] == spell_id:
			return str(e["name"])
	return spell_id


func _rune_of(spell_id: String) -> String:
	return RuneSamples.rune_of(spell_id)


# ---------------- UI 构建 ----------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 画符要在全屏进行，只有按钮挡点击
	_root.visible = false
	add_child(_root)

	_select_view = _build_select_view()
	_record_view = _build_record_view()
	_root.add_child(_select_view)
	_root.add_child(_record_view)


func _build_select_view() -> Control:
	var v := Control.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_STOP  # 选法术页挡住战场点击

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.06, 0.85)
	v.add_child(dim)

	var vp := DisplayServer.window_get_size()
	var panel_w := 620.0
	var panel_h := 420.0
	var pos := Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5)
	var border := ColorRect.new()
	border.position = pos - Vector2(2, 2)
	border.size = Vector2(panel_w, panel_h) + Vector2(4, 4)
	border.color = Color(0.35, 0.55, 0.85, 0.6)
	v.add_child(border)
	var panel := ColorRect.new()
	panel.position = pos
	panel.size = Vector2(panel_w, panel_h)
	panel.color = Color(0.06, 0.07, 0.12, 0.97)
	v.add_child(panel)

	var title := _label(panel, Rect2(0, 14, panel_w, 34), "符文录制", 24, Color(1.0, 0.95, 0.82))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var desc := _label(panel, Rect2(0, 50, panel_w, 40),
		"每个法术按你自己的习惯画几笔（建议 3~5 笔），识别会更懂你的手。\n内置画法始终有效——不录制也照常玩。", 14, Color(0.65, 0.85, 0.95))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var y := 104.0
	for e in SpellCodex.entries():
		if e["points"].is_empty():
			continue
		var spell_id := str(e["id"])
		var thumb := StrokeThumb.new()
		thumb.pts = e["points"]
		thumb.position = Vector2(24, y)
		thumb.size = Vector2(64, 64)
		panel.add_child(thumb)
		var name_l := _label(panel, Rect2(104, y + 6, 150, 28), str(e["name"]), 19, Color(1.0, 0.95, 0.85))
		name_l.name = "name_%s" % spell_id
		var count_l := _label(panel, Rect2(104, y + 34, 260, 22), "", 13, Color(0.55, 0.85, 0.65))
		count_l.name = "count_%s" % spell_id
		var rec_btn := _button(panel, Rect2(panel_w - 220, y + 8, 92, 40), "录这一笔")
		rec_btn.pressed.connect(func(): select_spell(spell_id))
		var clr_btn := _button(panel, Rect2(panel_w - 116, y + 8, 92, 40), "清空")
		clr_btn.pressed.connect(func(): _clear_spell(spell_id))
		y += 66.0

	var close_btn := _button(panel, Rect2(panel_w * 0.5 - 60, panel_h - 56, 120, 40), "关闭 (G)")
	close_btn.pressed.connect(close)
	return v


func _build_record_view() -> Control:
	var v := Control.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 录制中画符要穿透，只按钮挡
	v.visible = false

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.06, 0.30)  # 淡压暗：画符时看得见战场和拖尾
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(dim)

	var vp := DisplayServer.window_get_size()
	var hint := _label(v, Rect2(0, 18, vp.x, 30), "", 19, Color(1.0, 0.95, 0.85))
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var status := _label(v, Rect2(0, 52, vp.x, 26), "", 15, Color(0.55, 0.85, 0.65))
	status.name = "Status"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_last_stroke = StrokeThumb.new()
	_last_stroke.position = Vector2(24, 24)
	_last_stroke.size = Vector2(120, 120)
	_last_stroke.title = "上一笔"
	v.add_child(_last_stroke)

	var bx := vp.x - 320.0
	var by := vp.y - 64.0
	var back_btn := _button(v, Rect2(bx, by, 96, 40), "换法术")
	back_btn.pressed.connect(_show_select)
	var clr_btn := _button(v, Rect2(bx + 106, by, 96, 40), "清空")
	clr_btn.pressed.connect(func(): _clear_spell(_selected))
	var done_btn := _button(v, Rect2(bx + 212, by, 96, 40), "完成 (G)")
	done_btn.pressed.connect(close)
	return v


func _label(parent: Node, r: Rect2, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = r.position
	l.size = r.size
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


func _button(parent: Node, r: Rect2, text: String) -> Button:
	var b := Button.new()
	b.position = r.position
	b.size = r.size
	b.text = text
	b.add_theme_font_size_override("font_size", 15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.22, 0.95)
	sb.border_color = Color(0.35, 0.55, 0.85, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = Color(0.16, 0.22, 0.36, 0.95)
	b.add_theme_stylebox_override("hover", sb_hover)
	var sb_press := sb.duplicate()
	sb_press.bg_color = Color(0.22, 0.30, 0.48, 0.95)
	b.add_theme_stylebox_override("pressed", sb_press)
	parent.add_child(b)
	_buttons.append(b)
	return b


func _show_select() -> void:
	_selected = ""
	_select_view.visible = true
	_record_view.visible = false
	_refresh_counts()


func _clear_spell(spell_id: String) -> void:
	if spell_id.is_empty():
		return
	store.clear_spell(spell_id)
	store.save()
	fsm.recognizer.clear_user_templates(_rune_of(spell_id))
	_refresh_counts()
	if not _select_view.visible:
		_update_record_labels("已清空【%s】的样本" % _spell_name(spell_id))


func _refresh_counts() -> void:
	for e in SpellCodex.entries():
		var spell_id := str(e["id"])
		var count_l := _select_view.find_child("count_%s" % spell_id, true, false)
		if count_l != null:
			count_l.text = "已录 %d / %d 笔%s" % [store.count(spell_id), RuneSamples.MAX_PER_SPELL,
				"" if store.count(spell_id) > 0 else "（未录制，用内置画法）"]


func _update_record_labels(status_text: String) -> void:
	var hint: Label = _record_view.find_child("Hint", true, false)
	if hint != null:
		hint.text = "录制【%s】｜ 已录 %d 笔" % [_spell_name(_selected), store.count(_selected)]
	var status_l: Label = _record_view.find_child("Status", true, false)
	if status_l != null:
		status_l.text = status_text


# ---------------- 样本收集 ----------------

## 收笔两路（施放/失败）都汇到这里：拿 fsm.last_trajectory 快照入库存
func _on_cast(spell_id: String, _anchor: Vector2, _score: float) -> void:
	_handle_stroke(spell_id)


func _on_fizzle(_reason: String) -> void:
	var recognized := ""
	var rune: String = str(fsm.last_result.get("name", ""))
	if GestureFSM.RUNE_TO_SPELL.has(rune):
		recognized = GestureFSM.RUNE_TO_SPELL[rune]
	_handle_stroke(recognized)


func _handle_stroke(recognized_spell: String) -> void:
	if not _open or _selected.is_empty():
		return
	var traj: Array = fsm.last_trajectory.duplicate()
	var res := store.add(_selected, traj)
	match res:
		"ok":
			fsm.recognizer.add_recorded_template(_rune_of(_selected), traj)
			store.save()
			_last_stroke.pts = traj
			_last_stroke.queue_redraw()
			var msg := "已录 %d 笔" % store.count(_selected)
			if not recognized_spell.is_empty() and recognized_spell != _selected:
				msg += "｜ 注意：这一笔更像【%s】，已按你要录的【%s】保存" % [
					_spell_name(recognized_spell), _spell_name(_selected)]
			_update_record_labels(msg)
		"invalid":
			_update_record_labels("这笔太短没存上——画大一点、画完整一点")
		"full":
			_update_record_labels("已到 %d 笔上限，先清空再录" % RuneSamples.MAX_PER_SPELL)
	# 录制节奏：法力回满 + 状态机归位，立刻能画下一笔
	fsm.mana = GestureFSM.MANA_MAX
	fsm.reset()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _open:
			if event.keycode in [KEY_G, KEY_ESCAPE]:
				close()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_G:
			open()
			get_viewport().set_input_as_handled()


## 上一笔轨迹缩略图（图鉴同款画法）
class StrokeThumb extends Control:
	var pts: Array = []
	var title := ""

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.10, 0.16, 0.8))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.75, 1.0, 0.3), false, 1.0)
		if not title.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(6, 14), title,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.65, 0.75))
		if pts.size() >= 2:
			var inner := Rect2(Vector2(8, 22), size - Vector2(16, 30))
			SpellCodex.draw_rune(self, pts, inner, Color(0.65, 0.9, 1.0, 0.95), 3.0, true)
