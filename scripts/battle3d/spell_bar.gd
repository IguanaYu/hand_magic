class_name SpellBar
extends Control
## 底部法术快捷栏（自绘）：键位数字 + 手势形状 + 法术名/法力消耗。
## 按键施放时槽位闪白；法力不足的槽整体压暗。不拦截鼠标。


const SLOT := Vector2(92.0, 100.0)
const GAP := 12.0
const BOTTOM_MARGIN := 44.0   # 栏底距屏幕底（底部操作提示在 vp.y-30）
const FLASH_TIME := 0.18

var mana := 100.0:
	set(v):
		if not is_equal_approx(v, mana):
			mana = v
			queue_redraw()

var _entries: Array[Dictionary] = []
var _flash_left := {}   # 键码 -> 剩余闪光秒数


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entries = SpellCodex.entries()


func _process(delta: float) -> void:
	if _flash_left.is_empty():
		return
	for k in _flash_left.keys():
		_flash_left[k] = maxf(0.0, float(_flash_left[k]) - delta)
	queue_redraw()


func flash(key_code: int) -> void:
	_flash_left[key_code] = FLASH_TIME
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var total_w := _entries.size() * SLOT.x + (_entries.size() - 1) * GAP
	var x0 := (vp.x - total_w) * 0.5
	var y0 := vp.y - BOTTOM_MARGIN - SLOT.y
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var r := Rect2(Vector2(x0 + i * (SLOT.x + GAP), y0), SLOT)
		var affordable: bool = mana >= float(e["cost"])
		draw_rect(r, Color(0.05, 0.06, 0.10, 0.72))
		draw_rect(r, Color(0.55, 0.75, 1.0, 0.35), false, 1.0)
		# 键位数字（左上角标）
		draw_string(font, r.position + Vector2(10.0, 24.0), str(e["key_label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.95))
		# 手势形状（quick_shot 无符文，画掌心火弹图标）
		var rune_rect := Rect2(r.position + Vector2(22.0, 32.0), Vector2(SLOT.x - 44.0, 34.0))
		var pts: Array = e["points"]
		if pts.is_empty():
			var c := rune_rect.get_center()
			draw_circle(c, 9.0, Color(1.0, 0.55, 0.2, 0.9) if affordable else Color(0.6, 0.5, 0.45, 0.5))
			draw_circle(c, 4.0, Color(1.0, 0.85, 0.5, 0.95) if affordable else Color(0.7, 0.6, 0.5, 0.5))
		else:
			var rune_color := Color(0.65, 0.9, 1.0, 0.95) if affordable else Color(0.5, 0.6, 0.7, 0.45)
			SpellCodex.draw_rune(self, pts, rune_rect, rune_color, 3.0)
		# 法术名 + 消耗
		var name_color := Color(1, 1, 1, 0.92) if affordable else Color(0.6, 0.6, 0.65, 0.7)
		draw_string(font, Vector2(r.position.x, r.position.y + 78.0), str(e["name"]),
			HORIZONTAL_ALIGNMENT_CENTER, SLOT.x, 15, name_color)
		var cost_color := Color(0.45, 0.65, 1.0, 0.9) if affordable else Color(0.4, 0.45, 0.55, 0.6)
		draw_string(font, Vector2(r.position.x, r.position.y + 94.0), "%d 法力" % int(e["cost"]),
			HORIZONTAL_ALIGNMENT_CENTER, SLOT.x, 12, cost_color)
		# 法力不足：整槽压暗（盖在内容之上）
		if not affordable:
			draw_rect(r, Color(0.0, 0.0, 0.05, 0.45))
		# 按键施放闪光
		var fl := float(_flash_left.get(int(e["key"]), 0.0))
		if fl > 0.0:
			draw_rect(r, Color(1, 1, 1, 0.55 * fl / FLASH_TIME))
