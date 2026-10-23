class_name CodexPanel
extends CanvasLayer
## 手势图鉴（H / Tab 打开），两页：
##   P1 符文法术——每个法术一张卡片，画出符文形状与画法（未装备的加角标）。
##   P2 手势骨架——6 个静态手形的 21 关节骨架卡（MediaPipe 风格：绿骨/红关节/黄
##      指尖），扩展手形（比耶/点赞/我爱你）标"未启用"。
## 打开时暂停游戏（自身 process_mode=ALWAYS 保输入）；关闭时恢复并
## reset 手势状态机兜底（暂停前画到一半的轨迹不残留）。←/→ 或点标签切页。


const CARD := Vector2(168.0, 236.0)
const CARD_GAP := 20.0
const PANEL_PAD_X := 40.0
const POSE_CARD := Vector2(140.0, 236.0)
const POSE_GAP := 14.0

## 21 关节骨路（MediaPipe HandLandmarks 连接表）：0 腕；1-4 拇指；5-8 食指；
## 9-12 中指；13-16 无名指；17-20 小指
const HAND_BONES := [[0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8],
	[5, 9], [9, 10], [10, 11], [11, 12], [9, 13], [13, 14], [14, 15], [15, 16],
	[13, 17], [17, 18], [18, 19], [19, 20], [0, 17]]
const HAND_TIPS := [4, 8, 12, 16, 20]

## 静态手形关节摆位（100x112 视框，与 docs/gesture-gallery.html 同源数据）：
## 关节序 0 腕 / 1-4 拇指 / 5-8 食指（5=掌指关节）/ 9-12 中指 / 13-16 无名指 / 17-20 小指
const HAND_POSES := {
	"pinch": [Vector2(50, 100), Vector2(33, 74), Vector2(26, 62), Vector2(22, 51), Vector2(20.8, 40.2),
		Vector2(36, 48), Vector2(32.9, 36.5), Vector2(25.25, 36.5), Vector2(20.4, 39.9),
		Vector2(50, 44), Vector2(50, 29), Vector2(50, 19), Vector2(50, 11),
		Vector2(63, 47), Vector2(63.5, 33), Vector2(63.8, 24), Vector2(64, 17),
		Vector2(74, 53), Vector2(75.3, 42.1), Vector2(76.2, 35.1), Vector2(76.9, 29.1)],
	"fist": [Vector2(50, 100), Vector2(36, 82), Vector2(33.9, 70.2), Vector2(38.9, 61.5), Vector2(47.8, 59.9),
		Vector2(36, 48), Vector2(29, 35.9), Vector2(21.6, 41.1), Vector2(18.1, 47.1),
		Vector2(50, 44), Vector2(43, 30.8), Vector2(34.6, 36.2), Vector2(30.4, 43),
		Vector2(63, 47), Vector2(57.3, 35.3), Vector2(49.6, 39.9), Vector2(45.7, 45.7),
		Vector2(74, 53), Vector2(70.1, 42.7), Vector2(63.8, 45.8), Vector2(60, 50.5)],
	"palm": [Vector2(50, 100), Vector2(36, 82), Vector2(29.1, 72.2), Vector2(25.7, 62.8), Vector2(24.2, 53.9),
		Vector2(36, 48), Vector2(35.5, 34), Vector2(35.2, 25), Vector2(35, 18),
		Vector2(50, 44), Vector2(50, 29), Vector2(50, 19), Vector2(50, 11),
		Vector2(63, 47), Vector2(63.5, 33), Vector2(63.8, 24), Vector2(64, 17),
		Vector2(74, 53), Vector2(75.3, 42.1), Vector2(76.2, 35.1), Vector2(76.9, 29.1)],
	"victory": [Vector2(50, 100), Vector2(36, 82), Vector2(33.9, 70.2), Vector2(38.9, 61.5), Vector2(47.8, 59.9),
		Vector2(36, 48), Vector2(33.6, 34.2), Vector2(32, 25.4), Vector2(31.9, 18.4),
		Vector2(50, 44), Vector2(53.1, 29.3), Vector2(55.2, 19.5), Vector2(56.6, 11.7),
		Vector2(63, 47), Vector2(57.3, 35.3), Vector2(49.6, 39.9), Vector2(45.7, 45.7),
		Vector2(74, 53), Vector2(70.1, 42.7), Vector2(63.8, 45.8), Vector2(60, 50.5)],
	"thumb_up": [Vector2(50, 100), Vector2(36, 82), Vector2(33, 70), Vector2(31, 60), Vector2(30, 49),
		Vector2(36, 48), Vector2(29, 35.9), Vector2(21.6, 41.1), Vector2(18.1, 47.1),
		Vector2(50, 44), Vector2(43, 30.8), Vector2(34.6, 36.2), Vector2(30.4, 43),
		Vector2(63, 47), Vector2(57.3, 35.3), Vector2(49.6, 39.9), Vector2(45.7, 45.7),
		Vector2(74, 53), Vector2(70.1, 42.7), Vector2(63.8, 45.8), Vector2(60, 50.5)],
	"iloveyou": [Vector2(50, 100), Vector2(36, 82), Vector2(29.1, 72.2), Vector2(25.7, 62.8), Vector2(24.2, 53.9),
		Vector2(36, 48), Vector2(35.5, 34), Vector2(35.2, 25), Vector2(35, 18),
		Vector2(50, 44), Vector2(43, 30.8), Vector2(34.6, 36.2), Vector2(30.4, 43),
		Vector2(63, 47), Vector2(57.3, 35.3), Vector2(49.6, 39.9), Vector2(45.7, 45.7),
		Vector2(74, 53), Vector2(75.3, 42.1), Vector2(76.2, 35.1), Vector2(76.9, 29.1)],
}

## 手势卡条目：id / name / use / builtin（false = 扩展手形，未启用）
const POSE_ENTRIES := [
	{"id": "pinch", "name": "捏合", "use": "拇指食指相捏 = 落笔画符", "builtin": true},
	{"id": "fist", "name": "握拳", "use": "聚气 · 收笔施放", "builtin": true},
	{"id": "palm", "name": "张掌", "use": "取消 · 护盾 · 掌心火弹", "builtin": true},
	{"id": "victory", "name": "比耶", "use": "扩展手形", "builtin": false},
	{"id": "thumb_up", "name": "点赞", "use": "扩展手形", "builtin": false},
	{"id": "iloveyou", "name": "我爱你", "use": "扩展手形", "builtin": false},
]

var fsm: GestureFSM   # main.gd 注入
var loadout: SpellLoadout = null  # main.gd 注入；null = 全装备（不画角标）
var open_guard: Callable  # 返回 true 时禁止打开（与录制/配置面板互斥）

var _root: Control
var _open := false
var _page := 0
var _cards: CardsGrid
var _pose_cards: PoseCardsGrid
var _legend: Label
var _tab_buttons: Array[Button] = []


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
	_legend = _label(panel, Rect2(0.0, 56.0, panel_w, 20.0), "● 绿点 = 起笔 ｜ 橙点 = 收笔（画得像就行，大小方向不限）", 13, Color(0.55, 0.85, 0.65))
	_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 页签（点击切页；←/→ 亦可）
	var tabs := [["符文法术", 0], ["手势骨架", 1]]
	var tab_x := panel_pos.x + PANEL_PAD_X
	for t in tabs:
		var b := _tab_button(_root, Vector2(tab_x, panel_pos.y + panel_h - 30.0), str(t[0]))
		b.pressed.connect(_set_page.bind(int(t[1])))
		_tab_buttons.append(b)
		tab_x += 96.0

	_cards = CardsGrid.new()
	_cards.entries = SpellCodex.entries()
	_cards.loadout = loadout
	_cards.position = panel_pos + Vector2(PANEL_PAD_X, 84.0)
	_root.add_child(_cards)

	_pose_cards = PoseCardsGrid.new()
	_pose_cards.position = panel_pos + Vector2((panel_w - (6 * POSE_CARD.x + 5 * POSE_GAP)) * 0.5, 84.0)
	_root.add_child(_pose_cards)

	var f1 := _label(_root, Rect2(0.0, panel_pos.y + 330.0, vp.x, 26.0), "施法两步：① 捏合拇指食指落笔 → ② 画完松开即施放", 17, Color(1.0, 0.95, 0.85))
	f1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var f2 := _label(_root, Rect2(0.0, panel_pos.y + 360.0, vp.x, 22.0), "空闲张掌 / 按住右键 = 护盾 ｜ 数字键直放法术 ｜ R 重开 ｜ F1 调试", 14, Color(0.85, 0.88, 0.95, 0.9))
	f2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var f3 := _label(_root, Rect2(0.0, panel_pos.y + 388.0, vp.x, 22.0), "← / → 切页 ｜ H / ESC 关闭（游戏已暂停）", 14, Color(0.6, 0.65, 0.75))
	f3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_set_page(0)


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


## 页签按钮（样式沿用录制面板 _button 的 StyleBoxFlat 约定）
func _tab_button(parent: Node, pos: Vector2, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(88.0, 24.0)
	b.add_theme_font_size_override("font_size", 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.22, 0.95)
	sb.border_color = Color(0.35, 0.55, 0.85, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate()
	sb_h.bg_color = Color(0.14, 0.19, 0.32, 0.9)
	b.add_theme_stylebox_override("hover", sb_h)
	parent.add_child(b)
	return b


func _set_page(page: int) -> void:
	_page = clampi(page, 0, 1)
	_cards.visible = _page == 0
	_pose_cards.visible = _page == 1
	_legend.text = "● 绿点 = 起笔 ｜ 橙点 = 收笔（画得像就行，大小方向不限）" if _page == 0 \
		else "绿 = 骨骼 ｜ 红 = 关节 ｜ 黄 = 指尖（灰色卡 = 扩展手形，尚未启用）"
	for i in _tab_buttons.size():
		var b := _tab_buttons[i]
		b.modulate = Color(1, 1, 1, 1.0) if i == _page else Color(1, 1, 1, 0.45)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	if open_guard.is_valid() and open_guard.call():
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
			elif event.keycode == KEY_LEFT:
				_set_page(_page - 1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_RIGHT:
				_set_page(_page + 1)
				get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_H, KEY_TAB]:
			open()
			get_viewport().set_input_as_handled()


## P1 卡片网格（自绘）：手势大图 + 键位 + 消耗 + 画法/效果；未装备的加角标
class CardsGrid extends Control:
	var entries: Array[Dictionary] = []
	var loadout: SpellLoadout = null

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
			# 未装备角标（配置面板 C 勾掉的法术）
			if loadout != null and not loadout.is_equipped(str(e["id"])):
				var tag := Vector2(r.position.x + CodexPanel.CARD.x - 58.0, r.position.y + 6.0)
				draw_rect(Rect2(tag, Vector2(52.0, 20.0)), Color(0.45, 0.12, 0.10, 0.9))
				draw_string(font, tag + Vector2(0.0, 15.0), "未装备",
					HORIZONTAL_ALIGNMENT_CENTER, 52.0, 12, Color(1.0, 0.6, 0.5, 0.95))


## P2 手势骨架网格：21 关节骨架卡（绿骨/红关节/黄指尖，MediaPipe 风格）
class PoseCardsGrid extends Control:
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for i in CodexPanel.POSE_ENTRIES.size():
			var e: Dictionary = CodexPanel.POSE_ENTRIES[i]
			var pts: Array = CodexPanel.HAND_POSES[str(e["id"])]
			var r := Rect2(Vector2(i * (CodexPanel.POSE_CARD.x + CodexPanel.POSE_GAP), 0.0), CodexPanel.POSE_CARD)
			var active: bool = bool(e["builtin"])
			draw_rect(r, Color(0.09, 0.10, 0.16, 0.95) if active else Color(0.07, 0.075, 0.115, 0.95))
			draw_rect(r, Color(0.55, 0.75, 1.0, 0.30) if active else Color(0.5, 0.5, 0.55, 0.25), false, 1.0)
			draw_string(font, Vector2(r.position.x, r.position.y + 30.0), str(e["name"]),
				HORIZONTAL_ALIGNMENT_CENTER, CodexPanel.POSE_CARD.x, 20,
				Color(1.0, 0.95, 0.85) if active else Color(0.75, 0.75, 0.8, 0.8))
			var box := Rect2(r.position + Vector2(14.0, 46.0), Vector2(CodexPanel.POSE_CARD.x - 28.0, 130.0))
			_draw_hand(pts, box)
			draw_string(font, Vector2(r.position.x, r.position.y + 200.0), str(e["use"]),
				HORIZONTAL_ALIGNMENT_CENTER, CodexPanel.POSE_CARD.x, 13,
				Color(0.7, 0.9, 0.8) if active else Color(0.6, 0.62, 0.68, 0.8))
			if not active:
				draw_string(font, Vector2(r.position.x, r.position.y + 222.0), "未启用",
					HORIZONTAL_ALIGNMENT_CENTER, CodexPanel.POSE_CARD.x, 13, Color(1.0, 0.6, 0.5, 0.9))

	## 骨架绘制：关节点从 100x112 视框等比映射进 box（复用 SpellCodex.map_points
	## 的包围盒归一化），画掌心多边形 + 骨路 + 关节/指尖点
	func _draw_hand(pts: Array, box: Rect2) -> void:
		var mapped := SpellCodex.map_points(pts, box)
		var palm := PackedVector2Array()
		for idx in [0, 1, 5, 9, 13, 17]:
			palm.append(mapped[idx])
		draw_colored_polygon(palm, Color(1, 1, 1, 0.045))
		for b in CodexPanel.HAND_BONES:
			draw_line(mapped[b[0]], mapped[b[1]], Color(0.24, 0.88, 0.55, 0.95), 3.0)
		for i in mapped.size():
			if CodexPanel.HAND_TIPS.has(i):
				draw_circle(mapped[i], 3.4, Color(1.0, 0.82, 0.24))
			else:
				draw_circle(mapped[i], 2.4, Color(1.0, 0.36, 0.36))
