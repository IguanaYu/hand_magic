class_name SpellManager
extends Node2D
## 法术分发与命中判定（GDD §4 + §10.2）。
## 可伤害目标 = 练习靶（e2e 模式）+ 蚀影（游戏模式），统一走 hit()/frozen 接口。


signal spell_hit(spell_id: String, count: int)

const SPELL_LABEL := {
	"fireball": "火球术",
	"lightning": "链电术",
	"ice_field": "冰霜领域",
	"wind_blade": "风刃",
	"quick_shot": "掌心火弹",
}

var fx_layer: Node2D
var target_layer: Node2D      # 练习靶（e2e/修炼用，可为空）
var enemy_layer: Node2D       # 蚀影（游戏模式，可为空）
var view_size := Vector2(1280, 960)

var cast_total := 0
var hit_total := 0


func to_screen(norm: Vector2) -> Vector2:
	return Vector2(norm.x * view_size.x, norm.y * view_size.y)


func cast(spell_id: String, anchor_norm: Vector2) -> void:
	cast_total += 1
	var anchor := to_screen(anchor_norm)
	match spell_id:
		"fireball":
			_cast_fireball(anchor)
		"lightning":
			_cast_lightning(anchor)
		"ice_field":
			_cast_ice_field(anchor)
		"wind_blade":
			_cast_wind_blade(anchor)
		_:
			pass


## 快速施法（GDD M0.5）：拳→掌 触发，从掌心朝最近目标喷一枚小火弹
func quick_shot(anchor_norm: Vector2) -> void:
	cast_total += 1
	var origin := to_screen(anchor_norm)
	var nearest = _nearest_damageable(origin)
	var dir: Vector2
	if nearest != null:
		dir = (nearest.global_position - origin).normalized()
	else:
		dir = (view_size * 0.5 - origin).normalized()
	var fx := ProjectileFx.new()
	fx.position = origin
	fx.direction = dir
	fx.speed = 1000.0
	fx.view_size = view_size
	fx.target_layer = target_layer
	fx.enemy_layer = enemy_layer
	fx.manager = self
	fx.color = Color(1.0, 0.5, 0.15)
	fx.spell_id = "quick_shot"
	fx.pierce = 1
	fx_layer.add_child(fx)


# ---------- 可伤害目标（鸭子类型：alive / hit() / frozen_t 或 frozen / radius） ----------

func _damageables() -> Array:
	var out: Array = []
	if enemy_layer != null:
		for e in enemy_layer.get_children():
			if e is GameEnemy and e.alive:
				out.append(e)
	if target_layer != null:
		for t in target_layer.get_children():
			if t is TargetDummy and t.alive:
				out.append(t)
	return out


func _damageables_in_radius(pos: Vector2, r: float) -> Array:
	var out: Array = []
	for d in _damageables():
		if d.global_position.distance_to(pos) <= r + d.radius:
			out.append(d)
	return out


func _nearest_damageable(pos: Vector2):
	var best_node = null
	var best_d := INF
	for d in _damageables():
		var dist: float = d.global_position.distance_to(pos)
		if dist < best_d:
			best_d = dist
			best_node = d
	return best_node


func _break_all(damageables: Array, spell_id: String) -> void:
	var n := 0
	for d in damageables:
		if d.hit():
			n += 1
	if n > 0:
		hit_total += n
		spell_hit.emit(spell_id, n)


# ---------- 火球：锚点 AoE 爆炸（半径 15% 屏，GDD §4.4） ----------
func _cast_fireball(anchor: Vector2) -> void:
	var radius := minf(view_size.x, view_size.y) * 0.15
	var fx := FireballFx.new()
	fx.position = anchor
	fx.radius = radius
	fx_layer.add_child(fx)
	_break_all(_damageables_in_radius(anchor, radius), "fireball")


# ---------- 链电：锚点链最近的 3 个目标 ----------
func _cast_lightning(anchor: Vector2) -> void:
	var alive_targets := _damageables()
	alive_targets.sort_custom(func(a, b): return a.global_position.distance_squared_to(anchor) < b.global_position.distance_squared_to(anchor))
	var chained := alive_targets.slice(0, 3)
	var fx := LightningFx.new()
	fx.origin = anchor
	for t in chained:
		fx.targets.append(t.global_position)
	fx_layer.add_child(fx)
	_break_all(chained, "lightning")


# ---------- 冰域：锚点扩张冰环，领域内目标减速/冰冻 4s ----------
func _cast_ice_field(anchor: Vector2) -> void:
	var radius := view_size.x * 0.25
	var fx := IceFieldFx.new()
	fx.position = anchor
	fx.radius = radius
	fx_layer.add_child(fx)
	var caught := _damageables_in_radius(anchor, radius)
	var n := 0
	for d in caught:
		if d is GameEnemy:
			d.frozen_t = 4.0
		else:
			d.frozen = true
		n += 1
	# 冰域不击碎目标（GDD：控场定位），命中数记为受控数
	if n > 0:
		spell_hit.emit("ice_field", n)


# ---------- 风刃：从屏幕底部中点射向锚点方向的直线弹 ----------
func _cast_wind_blade(anchor: Vector2) -> void:
	var origin := Vector2(view_size.x * 0.5, view_size.y + 30.0)
	var dir := (anchor - origin).normalized()
	var fx := ProjectileFx.new()
	fx.position = origin
	fx.direction = dir
	fx.speed = 1400.0
	fx.view_size = view_size
	fx.target_layer = target_layer
	fx.enemy_layer = enemy_layer
	fx.manager = self
	fx.color = Color(0.75, 1.0, 0.6)
	fx.spell_id = "wind_blade"
	fx.pierce = 2
	fx_layer.add_child(fx)


# ---------------- 内嵌特效节点 ----------------

class FireballFx:
	extends Node2D
	var radius := 150.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
		if _t > 0.55:
			queue_free()

	func _draw() -> void:
		var p := clampf(_t / 0.4, 0.0, 1.0)
		var r := radius * (0.3 + 0.7 * p)
		var alpha := 1.0 - clampf((_t - 0.25) / 0.3, 0.0, 1.0)
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.4, 0.1, 0.4 * alpha))
		draw_circle(Vector2.ZERO, r * 0.55, Color(1.0, 0.75, 0.25, 0.7 * alpha))
		draw_circle(Vector2.ZERO, r * 0.22, Color(1.0, 1.0, 0.85, alpha))
		draw_arc(Vector2.ZERO, r * 1.25, 0, TAU, 48, Color(1.0, 0.6, 0.2, 0.6 * alpha), 5.0)
		for i in range(10):
			var a := TAU * i / 10.0 + _t * 2.0
			var d := r * (1.1 + 0.8 * p)
			draw_circle(Vector2(cos(a), sin(a)) * d, 4.0 * alpha, Color(1.0, 0.55, 0.2, alpha))


class LightningFx:
	extends Node2D
	var origin := Vector2.ZERO
	var targets: Array[Vector2] = []
	var _t := 0.0
	var _jag: Array = []

	func _init() -> void:
		randomize()

	func _ready() -> void:
		var pts: Array[Vector2] = [origin]
		for tgt in targets:
			var from: Vector2 = pts[pts.size() - 1]
			var seg := 6
			for i in range(1, seg + 1):
				var base := from.lerp(tgt, float(i) / float(seg))
				if i < seg:
					base += Vector2(randf_range(-16, 16), randf_range(-16, 16))
				pts.append(base)
		_jag = pts

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
		if _t > 0.22:
			queue_free()

	func _draw() -> void:
		var alpha := 1.0 - _t / 0.22
		var flicker := 0.7 + 0.3 * randf()
		for pass_i in range(2):
			var w := 7.0 if pass_i == 0 else 2.5
			var col := Color(0.55, 0.75, 1.0, 0.35 * alpha * flicker) if pass_i == 0 else Color(0.95, 0.98, 1.0, alpha * flicker)
			for i in range(_jag.size() - 1):
				draw_line(_jag[i], _jag[i + 1], col, w)
		for tgt in targets:
			draw_circle(tgt, 18.0 * alpha, Color(0.9, 0.95, 1.0, 0.5 * alpha))


class IceFieldFx:
	extends Node2D
	var radius := 200.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
		if _t > 4.0:
			queue_free()

	func _draw() -> void:
		var expand := clampf(_t / 0.4, 0.0, 1.0)
		var r := radius * expand
		var linger := clampf((4.0 - _t) / 0.8, 0.0, 1.0)
		draw_circle(Vector2.ZERO, r, Color(0.45, 0.8, 1.0, 0.10 * linger))
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(0.5, 0.9, 1.0, 0.8 * linger), 4.0)
		draw_arc(Vector2.ZERO, r * 0.85, 0, TAU, 48, Color(0.7, 0.95, 1.0, 0.35 * linger), 2.0)
		var rot := _t * 0.5
		for i in range(6):
			var a := rot + TAU * i / 6.0
			var dir := Vector2(cos(a), sin(a))
			draw_line(dir * r * 0.2, dir * r * 0.75, Color(0.85, 0.97, 1.0, 0.5 * linger), 2.0)


## 通用投射物（风刃/掌心火弹共用）：直线飞行、命中即碎、可穿透
class ProjectileFx:
	extends Node2D
	var direction := Vector2.UP
	var speed := 1200.0
	var view_size := Vector2(1280, 960)
	var target_layer: Node2D
	var enemy_layer: Node2D
	var manager: SpellManager = null
	var color := Color(0.75, 1.0, 0.6)
	var spell_id := "wind_blade"
	var pierce := 2
	var _trail: Array[Vector2] = []
	var _hit_set: Array = []
	var _pierced := 0

	func _process(delta: float) -> void:
		position += direction * speed * delta
		for layer in [target_layer, enemy_layer]:
			if layer == null:
				continue
			for t in layer.get_children():
				if (t is TargetDummy or t is GameEnemy) and t.alive and not (t in _hit_set):
					if t.global_position.distance_to(position) <= t.radius + 16.0:
						_hit_set.append(t)
						_pierced += 1
						if t.hit() and manager:
							manager.hit_total += 1
							manager.spell_hit.emit(spell_id, 1)
						if _pierced >= pierce:
							queue_free()
							return
		_trail.append(position)
		if _trail.size() > 8:
			_trail.pop_front()
		queue_redraw()
		if position.x < -80 or position.x > view_size.x + 80 or position.y < -80 or position.y > view_size.y + 80:
			queue_free()

	func _draw() -> void:
		if _trail.size() < 2:
			return
		for i in range(_trail.size() - 1):
			var t := float(i) / float(_trail.size() - 1)
			draw_line(_trail[i], _trail[i + 1], Color(color, 0.35 + 0.5 * t), lerpf(2.0, 9.0, t))
		draw_circle(Vector2.ZERO, 7.0, Color(1, 1, 1, 0.95))
		draw_arc(Vector2.ZERO, 13.0, 0, TAU, 20, Color(color, 0.7), 2.0)
