class_name DebugHud
extends CanvasLayer
## 调试 HUD（GDD §8）：状态/姿势/延迟/FPS/识别得分/统计。
## 全部代码构建，F1 切换显示。


var info_label: Label
var hint_label: Label
var message_label: Label
var visible_flag := true

var info := {}
var hint := ""
var message := ""


func _init() -> void:
	layer = 10
	info_label = Label.new()
	info_label.position = Vector2(12, 10)
	info_label.add_theme_font_size_override("font_size", 15)
	info_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	info_label.add_theme_constant_override("outline_size", 4)
	add_child(info_label)

	message_label = Label.new()
	message_label.position = Vector2(12, 42)
	message_label.add_theme_font_size_override("font_size", 14)
	message_label.add_theme_color_override("font_color", Color(1, 0.75, 0.3, 0.95))
	message_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	message_label.add_theme_constant_override("outline_size", 4)
	add_child(message_label)

	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(240, 0)
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.9))
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hint_label.add_theme_constant_override("outline_size", 5)
	add_child(hint_label)
	_update_layout()


func _update_layout() -> void:
	var vp := DisplayServer.window_get_size()
	hint_label.position = Vector2(vp.x * 0.5 - 360, vp.y - 46)


func set_info(dict: Dictionary) -> void:
	info = dict
	_refresh()


func set_hint(text: String) -> void:
	hint = text
	_refresh()


func set_message(text: String) -> void:
	message = text
	_refresh()
	if not text.is_empty():
		_fade_message()


var _msg_fade_t := 0.0


func _fade_message() -> void:
	_msg_fade_t = 3.0


func _process(delta: float) -> void:
	if _msg_fade_t > 0.0:
		_msg_fade_t -= delta
		if _msg_fade_t <= 0.0:
			message = ""
			_refresh()


func _refresh() -> void:
	if not visible_flag:
		info_label.text = ""
		message_label.text = ""
		hint_label.text = ""
		return
	info_label.text = ""
	for k in info:
		info_label.text += "%s: %s\n" % [k, str(info[k])]
	message_label.text = message
	hint_label.text = hint


func toggle() -> void:
	visible_flag = not visible_flag
	_refresh()
