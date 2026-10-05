class_name SpellCodex
extends RefCounted
## 法术图鉴数据（单一数据源）：快捷键映射 + 手势展示形状 + 说明文案。
## 供 SpellBar（底部快捷栏）与 CodexPanel（H 手势图鉴）共用。
## 展示形状点与 DollarRecognizer 的原始模板一致（0~1 屏幕坐标，y 向下），
## 玩家看到的形状 = 识别器认的形状。


const SPELL_KEYS := {
	KEY_1: "fireball", KEY_2: "lightning", KEY_3: "ice_field",
	KEY_4: "wind_blade", KEY_5: "quick_shot",
}

# 起笔一致性说明：识别器对圆/三角/Z 字旋转不敏感、对斜线方向不敏感，
# 展示图只取模板原样（起笔点在图鉴中用绿点标出，照着画最容易命中）。
# 圆是 33 点曲线，const 装不下循环，见 circle_points()
const DISPLAY_POINTS := {
	"zigzag": [Vector2(0.1, 0.2), Vector2(0.9, 0.2), Vector2(0.1, 0.8), Vector2(0.9, 0.8)],
	"triangle": [Vector2(0.5, 0.1), Vector2(0.9, 0.9), Vector2(0.1, 0.9), Vector2(0.5, 0.1)],
	"slash": [Vector2(0.15, 0.85), Vector2(0.85, 0.15)],
}


static func circle_points() -> Array:
	var pts := []
	for i in range(33):
		var t := TAU * i / 32.0
		pts.append(Vector2(0.5 + 0.4 * cos(t - PI / 2.0), 0.5 + 0.4 * sin(t - PI / 2.0)))
	return pts


## 5 条目：id / name / key(键码) / key_label / cost / points(展示折线，空=无符文) /
## how(怎么画) / desc(效果一句话)
static func entries() -> Array[Dictionary]:
	return [
		{
			"id": "fireball", "name": "火球术", "key": KEY_1, "key_label": "1",
			"cost": GestureFSM.SPELL_COST["fireball"], "points": circle_points(),
			"how": "画一个圆圈", "desc": "范围爆炸，砸一片",
		},
		{
			"id": "lightning", "name": "链电术", "key": KEY_2, "key_label": "2",
			"cost": GestureFSM.SPELL_COST["lightning"], "points": DISPLAY_POINTS["zigzag"],
			"how": "画 Z 字闪电", "desc": "链式跳跃多个敌人",
		},
		{
			"id": "ice_field", "name": "冰霜领域", "key": KEY_3, "key_label": "3",
			"cost": GestureFSM.SPELL_COST["ice_field"], "points": DISPLAY_POINTS["triangle"],
			"how": "画一个三角形", "desc": "范围减速并持续冻伤",
		},
		{
			"id": "wind_blade", "name": "风刃", "key": KEY_4, "key_label": "4",
			"cost": GestureFSM.SPELL_COST["wind_blade"], "points": DISPLAY_POINTS["slash"],
			"how": "一笔斜挥", "desc": "快速直线切割",
		},
		{
			"id": "quick_shot", "name": "掌心火弹", "key": KEY_5, "key_label": "5",
			"cost": GestureFSM.QUICK_COST, "points": [],
			"how": "握拳后直接张掌（不画符）", "desc": "快速单发火弹",
		},
	]


## 把 0~1 归一化折线映射进目标矩形：按自身包围盒等比缩放并居中（不拉伸变形）
static func map_points(points: Array, rect: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for p in points:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	var span := Vector2(maxf(max_v.x - min_v.x, 1e-4), maxf(max_v.y - min_v.y, 1e-4))
	var scale := minf(rect.size.x / span.x, rect.size.y / span.y)
	var draw_size := Vector2(span.x * scale, span.y * scale)
	var offset := rect.position + (rect.size - draw_size) * 0.5
	for p in points:
		out.append(offset + (p - min_v) * Vector2(scale, scale))
	return out


## 画手势符文折线：闭合形状首尾相连；markers=true 时绿点标起笔、橙点标收笔
static func draw_rune(c: CanvasItem, points: Array, rect: Rect2, color: Color, width: float, markers := false) -> void:
	if points.is_empty():
		return
	var pts := map_points(points, rect)
	var first: Vector2 = points[0]
	var last: Vector2 = points[points.size() - 1]
	if (last - first).length() < 0.05:
		pts.append(pts[0])
	c.draw_polyline(pts, color, width, true)
	if markers:
		c.draw_circle(pts[0], width * 1.4, Color(0.35, 0.95, 0.55))
		if (last - first).length() >= 0.05:
			c.draw_circle(pts[pts.size() - 1], width * 1.4, Color(1.0, 0.65, 0.25))
