class_name CodexPanel
extends CanvasLayer
## 手势图鉴（H / Tab 打开）：每个法术一张卡片，画出手势怎么画。
## 打开时暂停游戏（自身 process_mode=ALWAYS 保输入）；关闭时恢复并
## reset 手势状态机兜底（暂停前画到一半的轨迹不残留）。


const CARD := Vector2(168.0, 236.0)
const CARD_GAP := 20.0
const PANEL_PAD_X := 40.0

var fsm: GestureFSM   # main.gd 注入

var _root: Control
var _open := false


func _init() -> void:
	layer = 11   # 盖过 DebugHud(10)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build()


func _build() -> void:
	var vp := DisplayServer.window_get_size()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # 打开时挡住点击，不穿透到战场
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.06, 0.85)
	_root.add_child(dim)

	var cards_w := 5 * CARD.x + 4 * CARD_GAP
	var panel_w := cards_w + PANEL_PAD_X * 2.0
	var panel_h := 436.0
	var panel_pos := Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5)
	# 边框（底垫矩形外扩 2px）
	var border := ColorRect.new()
	border.position = panel_pos - Vector2(2.0, 2.0)
	border.size = Vector2(panel_w, panel_h) + Vector2(4.0, 4.0)
	border.color = Color(0.35, 0.55, 0.85, 0.6)
	_root.add_child(border)
	var panel := ColorRect.new()
	panel.position = panel_pos
	panel.size = Vector2(panel_w, panel_h)
	panel.color = Color(0.06, 0.07, 0.12, 0.97)
	_root.add_child(panel)

	var title := _label(panel, Rect2(0.0, 16.0, panel_w, 40.0), "手势图鉴", 26, Color(1.0, 0.95, 0.82))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var legend := _label(panel, Rect2(0.0, 56.0, panel_w, 20.0), "● 绿点 = 起笔 ｜ 橙点 = 收笔（画得像就行，大小方向不限）", 13, Color(0.55, 0.85, 0.65))
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var cards := CardsGrid.new()
	cards.entries = SpellCodex.entries()
	cards.position = panel_pos + Vector2(PANEL_PAD_X, 84.0)
	_root.add_child(cards)

	var f1 := _label(_root, Rect2(0.0, panel_pos.y + 330.0, vp.x, 26.0), "施法三步：① 握拳蓄力 → ② 食指画符 → ③ 张掌释放", 17, Color(1.0, 0.95, 0.85))
	f1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var f2 := _label(_root, Rect2(0.0, panel_pos.y + 360.0, vp.x, 22.0), "空闲张掌 / 按住右键 = 护盾 ｜ 数字键直放法术 ｜ R 重开 ｜ F1 调试", 14, Color(0.85, 0.88, 0.95, 0.9))
	f2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var f3 := _label(_root, Rect2(0.0, panel_pos.y + 388.0, vp.x, 22.0), "H / ESC 关闭（游戏已暂停）", 14, Color(0.6, 0.65, 0.75))
	f3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


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


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_root.visible = true
	get_tree().paused = true


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	get_tree().paused = false
	if fsm != null:
		fsm.reset()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _open:
			if event.keycode in [KEY_H, KEY_TAB, KEY_ESCAPE]:
				close()
				get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_H, KEY_TAB]:
			open()
			get_viewport().set_input_as_handled()


## 卡片网格（自绘）：手势大图 + 键位 + 消耗 + 画法/效果
class CardsGrid extends Control:
	var entries: Array[Dictionary] = []

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for i in entries.size():
			var e: Dictionary = entries[i]
			var r := Rect2(Vector2(i * (CodexPanel.CARD.x + CodexPanel.CARD_GAP), 0.0), CodexPanel.CARD)
			draw_rect(r, Color(0.09, 0.10, 0.16, 0.95))
			draw_rect(r, Color(0.55, 0.75, 1.0, 0.30), false, 1.0)
			# 键位徽标（左上）+ 法术名（居中）
			draw_string(font, r.position + Vector2(12.0, 30.0), "[%s]" % e["key_label"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.65, 0.85, 1.0, 0.95))
			draw_string(font, Vector2(r.position.x, r.position.y + 32.0), str(e["name"]),
				HORIZONTAL_ALIGNMENT_CENTER, CodexPanel.CARD.x, 21, Color(1.0, 0.95, 0.85))
			# 手势大图（quick_shot 无符文，画掌心火弹图标）
			var rune_rect := Rect2(r.position + Vector2(28.0, 52.0), Vector2(CodexPanel.CARD.x - 56.0, 92.0))
			var pts: Array = e["points"]
			if pts.is_empty():
				var c := rune_rect.get_center()
				draw_circle(c, 16.0, Color(1.0, 0.55, 0.2, 0.9))
				draw_circle(c, 7.0, Color(1.0, 0.85, 0.5, 0.95))
			else:
				SpellCodex.draw_rune(self, pts, rune_rect, Color(0.65, 0.9, 1.0, 0.95), 4.0, true)
			draw_string(font, Vector2(r.position.x, r.position.y + 172.0), "%d 法力" % int(e["cost"]),
				HORIZONTAL_ALIGNMENT_CENTER, CodexPanel.CARD.x, 15, Color(0.45, 0.65, 1.0, 0.9))
			draw_string(font, Vector2(r.position.x, r.position.y + 196.0), str(e["how"]),
				HORIZONTAL_ALIGNMENT_CENTER, CodexPanel.CARD.x, 14, Color(0.7, 0.9, 0.8))
			draw_string(font, Vector2(r.position.x, r.position.y + 218.0), str(e["desc"]),
				HORIZONTAL_ALIGNMENT_CENTER, CodexPanel.CARD.x, 13, Color(0.85, 0.85, 0.9, 0.8))
