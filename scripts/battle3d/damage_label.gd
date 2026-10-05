class_name DamageLabel
extends Label
## M1.6 伤害飘字：3D 世界坐标投影到屏幕，弹出缩放 + 上浮淡出 0.7s。

var world_pos := Vector3.ZERO
var camera: Camera3D
var t := 0.0


func setup(p_world: Vector3, p_camera: Camera3D, dmg: float, col: Color) -> void:
	world_pos = p_world
	camera = p_camera
	text = "%d" % roundi(dmg)
	add_theme_font_size_override("font_size", 20)
	add_theme_color_override("font_color", col)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("outline_size", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	t += delta
	var wp := world_pos + Vector3.UP * (0.3 + t * 1.0)
	if camera.is_position_behind(wp):
		visible = false
	else:
		visible = true
		position = camera.unproject_position(wp) - size * 0.5
		pivot_offset = size * 0.5
		# 出现瞬间放大弹出，快速回落到原尺寸
		scale = Vector2.ONE * (1.0 + 0.4 * clampf(1.0 - t / 0.14, 0.0, 1.0))
	modulate.a = clampf(1.0 - t / 0.7, 0.0, 1.0)
	if t > 0.7:
		queue_free()
