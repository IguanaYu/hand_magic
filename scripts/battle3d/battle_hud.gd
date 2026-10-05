class_name BattleHud
extends Control
## M1.1 战场 HUD：HP 条 / 法力条(占位) / 波次文字 / 敌人数 / 得分。
## 自绘（_draw），不拦截鼠标（mouse_filter=IGNORE）。

var hp_ratio := 1.0
var mana_ratio := 0.0
var wave_text := "自由刷怪"
var enemy_text := "场上敌人 0"
var score_text := "得分 0（击杀 0）"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	# 状态量是普通变量，需手动请求重绘（否则血条/文字停留在首帧）
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font

	# HP 条（底部左）
	var bar_w := 320.0
	var bar_h := 20.0
	var x := 24.0
	var y := vp.y - 24.0 - bar_h
	draw_rect(Rect2(x, y, bar_w, bar_h), Color(0.05, 0.06, 0.10, 0.75))
	draw_rect(Rect2(x + 2.0, y + 2.0, (bar_w - 4.0) * clampf(hp_ratio, 0.0, 1.0), bar_h - 4.0), Color(0.85, 0.25, 0.20))
	draw_string(font, Vector2(x, y - 6.0), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.75))

	# 法力条（HP 上方，M1.3 接数据）
	var my := y - bar_h - 10.0
	draw_rect(Rect2(x, my, bar_w, 12.0), Color(0.05, 0.06, 0.10, 0.75))
	draw_rect(Rect2(x + 2.0, my + 2.0, (bar_w - 4.0) * clampf(mana_ratio, 0.0, 1.0), 8.0), Color(0.30, 0.55, 0.95))
	draw_string(font, Vector2(x, my - 6.0), "MP", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.75))

	# 顶部中：波次 + 敌人数
	draw_string(font, Vector2(vp.x * 0.5 - 90.0, 38.0), wave_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.95, 0.80))
	draw_string(font, Vector2(vp.x * 0.5 - 90.0, 64.0), enemy_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.9, 0.9, 0.95))

	# 顶部右：得分
	draw_string(font, Vector2(vp.x - 300.0, 38.0), score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(0.85, 0.95, 1.0))
