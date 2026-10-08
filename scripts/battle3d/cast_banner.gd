class_name CastBanner
extends Control
## M2 施法成功反馈：法术名大字在画面中上方弹出——元素配色 + 下划线展开 + 回弹缩放 + 淡出。
## 手势/键盘/掌心火弹三条施法路径统一触发（main._on_3d_* 与战场键盘直放）。

var _label: Label
var _line_w := 0.0
var _accent := Color(1.0, 0.7, 0.3)
var _label_cy := 0.0
var _tw: Tween


static func color_of(spell_id: String) -> Color:
	match spell_id:
		"fireball":
			return Color(1.0, 0.55, 0.2)
		"lightning":
			return Color(0.75, 0.85, 1.0)
		"ice_field":
			return Color(0.55, 0.85, 1.0)
		"wind_blade":
			return Color(0.6, 1.0, 0.7)
		_:
			return Color(1.0, 0.75, 0.35)  # 掌心火弹等


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 46)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 10)
	_label.modulate.a = 0.0
	add_child(_label)
	modulate.a = 0.0


## 弹出一条施法成功提示（重复调用会打断上一次）
func pop(spell_name: String, accent: Color) -> void:
	_accent = accent
	_label.text = spell_name
	_label.add_theme_color_override("font_color", accent.lightened(0.25))
	_label.reset_size()
	# 挂在 CanvasLayer 下的 Control 布局不可靠（同 BattleHud），直接用视口尺寸定位
	var vp := get_viewport_rect().size
	_label_cy = vp.y * 0.40
	_label.position = Vector2(vp.x * 0.5 - _label.size.x * 0.5, _label_cy - _label.size.y * 0.5)
	_label.pivot_offset = _label.size * 0.5
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_line_w = 0.0
	modulate.a = 1.0
	_label.modulate.a = 1.0  # _ready 里藏底的透明度，弹出时恢复
	_label.scale = Vector2.ONE * 0.6
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(_label, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_method(_set_line_w, 0.0, 150.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.chain().tween_interval(0.35)
	_tw.chain().tween_property(self, "modulate:a", 0.0, 0.4)
	queue_redraw()


func _set_line_w(v: float) -> void:
	_line_w = v
	queue_redraw()


func _draw() -> void:
	if _line_w <= 0.0:
		return
	var ly := _label_cy + _label.size.y * 0.5 + 10.0
	var cx := get_viewport_rect().size.x * 0.5
	draw_rect(Rect2(cx - _line_w * 0.5, ly, _line_w, 3.0), _accent)
	# 两端小圆点装饰
	draw_circle(Vector2(cx - _line_w * 0.5 - 9.0, ly + 1.5), 3.0, _accent)
	draw_circle(Vector2(cx + _line_w * 0.5 + 9.0, ly + 1.5), 3.0, _accent)
