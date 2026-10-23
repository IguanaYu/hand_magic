class_name SpellLoadoutPanel
extends CanvasLayer
## 法术配置面板（C 打开）：勾选当前要用的法术，同时最多 SpellLoadout.MAX_EQUIPPED
## 个（暂定 5）。未装备的法术三处施法路径全部失效（FSM 画符 / 掌心火弹 / 数字键直放）。
## 范式沿用 RuneRecordPanel / CodexPanel：纯代码 UI，打开暂停游戏并冻结战场
##（配置不需要手势管线，main 保持 INHERIT 自然冻结），关闭时存档并 fsm.reset()。


const PANEL_SIZE := Vector2(560.0, 472.0)
const ROW_H := 62.0
const ROW_GAP := 6.0
const ROW_Y0 := 80.0

var loadout: SpellLoadout   # main.gd 注入
var battle: Node3D          # 战场（main 注入，打开时冻结）
var open_guard: Callable    # 返回 true 时禁止打开（与图鉴/录制面板互斥）

var _root: Control
var _open := false
var _buttons := {}          # spell_id -> Button（勾选框）
var _footer: Label
var _hint: Label
var _hint_left := 0.0


func _init() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build()


func _build() -> void:
	var vp := DisplayServer.window_get_size()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.06, 0.85)
	_root.add_child(dim)

	var panel_pos := Vector2((vp.x - PANEL_SIZE.x) * 0.5, (vp.y - PANEL_SIZE.y) * 0.5)
	var border := ColorRect.new()
	border.position = panel_pos - Vector2(2.0, 2.0)
	border.size = PANEL_SIZE + Vector2(4.0, 4.0)
	border.color = Color(0.35, 0.55, 0.85, 0.6)
	_root.add_child(border)
	var panel := ColorRect.new()
	panel.position = panel_pos
	panel.size = PANEL_SIZE
	panel.color = Color(0.06, 0.07, 0.12, 0.97)
	_root.add_child(panel)

	var title := _label(panel, Rect2(0.0, 14.0, PANEL_SIZE.x, 34.0), "法术配置", 24, Color(1.0, 0.95, 0.82))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label(panel, Rect2(0.0, 48.0, PANEL_SIZE.x, 20.0),
		"勾选要使用的法术（最多同时 %d 个，暂定）｜ 未勾选的法术无法施放" % _cap(),
		13, Color(0.55, 0.85, 0.65))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var y := ROW_Y0
	for e in SpellCodex.entries():
		_build_row(panel, panel_pos, e, y)
		y += ROW_H + ROW_GAP

	_footer = _label(panel, Rect2(0.0, PANEL_SIZE.y - 40.0, PANEL_SIZE.x, 22.0), "", 15, Color(0.65, 0.85, 1.0))
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint = _label(panel, Rect2(0.0, PANEL_SIZE.y - 18.0, PANEL_SIZE.x, 18.0), "", 13, Color(1.0, 0.55, 0.45))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_footer()


func _build_row(parent: Control, panel_pos: Vector2, e: Dictionary, y: float) -> void:
	var spell_id := str(e["id"])
	# 符文缩略图
	var thumb := LoadoutThumb.new()
	thumb.points = e["points"]
	thumb.position = panel_pos + Vector2(24.0 + 8.0, y + 8.0)
	thumb.size = Vector2(48.0, 48.0)
	_root.add_child(thumb)
	# 名称 / 法力 / 效果（坐标相对面板；文字列从 x=88 起，避开 48px 缩略图）
	_label(parent, Rect2(88.0, y + 10.0, 126.0, 22.0), "[%s] %s" % [e["key_label"], e["name"]], 16, Color(1.0, 0.95, 0.85))
	_label(parent, Rect2(88.0, y + 34.0, 126.0, 18.0), "%d 法力" % int(e["cost"]), 13, Color(0.45, 0.65, 1.0))
	_label(parent, Rect2(226.0, y + 10.0, 200.0, 22.0), str(e["desc"]), 13, Color(0.85, 0.85, 0.9, 0.85))
	_label(parent, Rect2(226.0, y + 34.0, 200.0, 18.0), str(e["how"]), 12, Color(0.6, 0.8, 0.7))
	# 勾选框
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_pressed = loadout != null and loadout.is_equipped(spell_id)
	btn.text = "装备中" if btn.button_pressed else "未装备"
	btn.position = panel_pos + Vector2(440.0, y + 13.0)
	btn.size = Vector2(92.0, 36.0)
	btn.add_theme_font_size_override("font_size", 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.20, 0.14, 0.95) if btn.button_pressed else Color(0.10, 0.13, 0.22, 0.95)
	sb.border_color = Color(0.35, 0.85, 0.55, 0.8) if btn.button_pressed else Color(0.35, 0.55, 0.85, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate()
	sb_h.bg_color = Color(0.14, 0.19, 0.32, 0.9)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.toggled.connect(_on_row_toggled.bind(spell_id, btn))
	_root.add_child(btn)
	_buttons[spell_id] = btn


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


## 生效上限（loadout 可能被测试/难度模式改小）
func _cap() -> int:
	return loadout.max_equipped if loadout != null else SpellLoadout.MAX_EQUIPPED


func _on_row_toggled(pressed: bool, spell_id: String, btn: Button) -> void:
	if loadout == null:
		return
	if pressed:
		var res: String = loadout.equip(spell_id)
		if res != "ok":
			btn.set_pressed_no_signal(false)
			_flash_hint("最多同时装备 %d 个法术（暂定），先取消一个再勾" % _cap() if res == "full" else "未知法术")
			return
	else:
		loadout.unequip(spell_id)
	_refresh_row(btn, pressed)
	_update_footer()


func _refresh_row(btn: Button, equipped: bool) -> void:
	btn.text = "装备中" if equipped else "未装备"
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal")
	sb.bg_color = Color(0.10, 0.20, 0.14, 0.95) if equipped else Color(0.10, 0.13, 0.22, 0.95)
	sb.border_color = Color(0.35, 0.85, 0.55, 0.8) if equipped else Color(0.35, 0.55, 0.85, 0.8)


func _update_footer() -> void:
	if loadout == null:
		return
	_footer.text = "已装备 %d / %d" % [loadout.count(), _cap()]


func _flash_hint(text: String) -> void:
	_hint.text = text
	_hint_left = 2.5


func _process(delta: float) -> void:
	if _hint_left > 0.0:
		_hint_left -= delta
		if _hint_left <= 0.0:
			_hint.text = ""


func is_open() -> bool:
	return _open


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
	get_tree().paused = true
	if battle != null:
		battle.process_mode = Node.PROCESS_MODE_DISABLED
	_update_footer()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	if battle != null:
		battle.process_mode = Node.PROCESS_MODE_INHERIT
	get_tree().paused = false
	if loadout != null:
		loadout.save()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _open:
			if event.keycode in [KEY_C, KEY_ESCAPE]:
				close()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_C:
			open()
			get_viewport().set_input_as_handled()


## 符文缩略图（自绘）：无符文的法术（掌心火弹）画火弹图标
class LoadoutThumb extends Control:
	var points: Array = []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.10, 0.16, 0.95))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.75, 1.0, 0.30), false, 1.0)
		var rect := Rect2(Vector2(6.0, 6.0), size - Vector2(12.0, 12.0))
		if points.is_empty():
			var c := rect.get_center()
			draw_circle(c, 9.0, Color(1.0, 0.55, 0.2, 0.9))
			draw_circle(c, 4.0, Color(1.0, 0.85, 0.5, 0.95))
		else:
			SpellCodex.draw_rune(self, points, rect, Color(0.65, 0.9, 1.0, 0.95), 3.0)
