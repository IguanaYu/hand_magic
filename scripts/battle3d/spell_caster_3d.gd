class_name SpellCaster3D
extends Node3D
## M1.2 法术施放：屏幕锚点 → 相机射线 → 敌人球检测/地面落点，五法术 3D 化。
## cast(spell_id, screen_pos) 统一入口；键盘 1-5 调试直放也走这里。

const FIREBALL_DMG := 40.0
const FIREBALL_RADIUS := 2.5
const FIREBALL_SPEED := 18.0
const LIGHTNING_DMG := 25.0
const LIGHTNING_TARGETS := 3
const ICE_RADIUS := 6.0
const ICE_DMG := 10.0
const WIND_DMG := 18.0
const WIND_RANGE := 8.0
const WIND_KNOCKBACK := 3.0
const QUICK_DMG := 8.0
## 辅助瞄准：命中球半径随距离放大
const AIM_BASE_RADIUS := 0.8
const AIM_MAX_RADIUS := 1.6

var battlefield: Battlefield3D
## 风刃射程（默认 8m 贴身警戒；马里奥广场怪不近身，战场覆写为 22m 够得着巡逻区）
var wind_range := WIND_RANGE


func cast(spell_id: String, screen_pos: Vector2) -> void:
	match spell_id:
		"fireball":
			var aim := aim(screen_pos)
			_spawn_fireball(aim)
		"lightning":
			var aim := aim(screen_pos)
			_cast_lightning(aim)
		"ice_field":
			var aim := aim_ground(screen_pos)
			_cast_ice_field(aim)
		"wind_blade":
			_cast_wind_blade(screen_pos)
		"quick_shot":
			_cast_quick_shot()
		_:
			pass


# ---------- 瞄准 ----------

## 射线-球体检测命中敌人，否则返回地面落点（y=0）
func aim(screen_pos: Vector2) -> Dictionary:
	var origin: Vector3 = battlefield.camera.project_ray_origin(screen_pos)
	var dir: Vector3 = battlefield.camera.project_ray_normal(screen_pos)
	var enemy := _ray_hit_enemy(origin, dir)
	if enemy != null:
		return {"enemy": enemy, "point": enemy.aim_center()}
	return {"enemy": null, "point": _ground_point(origin, dir)}


func aim_ground(screen_pos: Vector2) -> Vector3:
	var origin: Vector3 = battlefield.camera.project_ray_origin(screen_pos)
	var dir: Vector3 = battlefield.camera.project_ray_normal(screen_pos)
	var enemy := _ray_hit_enemy(origin, dir)
	if enemy != null:
		var p := enemy.global_position
		p.y = 0.0
		return p
	return _ground_point(origin, dir)


func scan_enemy(screen_pos: Vector2) -> EnemyUnit3D:
	var origin: Vector3 = battlefield.camera.project_ray_origin(screen_pos)
	var dir: Vector3 = battlefield.camera.project_ray_normal(screen_pos)
	return _ray_hit_enemy(origin, dir)


func _ray_hit_enemy(origin: Vector3, dir: Vector3) -> EnemyUnit3D:
	var best: EnemyUnit3D = null
	var best_t := INF
	for e in battlefield.enemies:
		if not e.alive:
			continue
		# 隐身中的幽灵不可被瞄准（链电不吃这套：走 _nearest_enemies 全量扫描）
		if "is_stealthed" in e and e.is_stealthed():
			continue
		var center := e.aim_center()
		var assist: float = clampf(AIM_BASE_RADIUS + origin.distance_to(center) * 0.02, AIM_BASE_RADIUS, AIM_MAX_RADIUS)
		var oc := center - origin
		var tca: float = oc.dot(dir)
		if tca < 0.0:
			continue
		var d2: float = oc.length_squared() - tca * tca
		var r2: float = assist * assist
		if d2 > r2:
			continue
		var t: float = tca - sqrt(maxf(r2 - d2, 0.0))
		if t < best_t:
			best_t = t
			best = e
	return best


func _ground_point(origin: Vector3, dir: Vector3) -> Vector3:
	if absf(dir.y) < 0.001:
		return origin + dir * 20.0
	var t := -origin.y / dir.y
	if t < 0.0 or t > 120.0:
		return origin + dir * 25.0
	return origin + dir * t


# ---------- 法术 ----------

func _spawn_fireball(aim: Dictionary) -> void:
	battlefield.play_sfx("cast_fire", Vector3.INF, -4.0)
	var fx := FireballProjectile.new()
	fx.caster = self
	fx.target = aim["point"]
	var launch := battlefield.camera.global_position + battlefield.camera.global_transform.basis.z * 1.2 - Vector3.UP * 0.3
	fx.position = launch
	battlefield.fx_layer.add_child(fx)


## 火球 AoE 伤害判定（爆炸点 r2.5m 内敌人 40 伤；马里奥单位走元素克制表）
func _apply_aoe(point: Vector3) -> void:
	# duplicate：击杀回调会当场把死者从 enemies 移除，遍历原数组会跳过下一只
	for e in battlefield.enemies.duplicate():
		if e.alive and e.global_position.distance_to(point) <= FIREBALL_RADIUS:
			var dir: Vector3 = e.global_position - point
			dir.y = 0.0
			_hit_enemy(e, "fire", FIREBALL_DMG, dir, Color(1.0, 0.7, 0.3))


## 统一伤害入口：马里奥单位（MarioEnemy3D）走 apply_spell 克制表，旧单位=直伤。
## 返回实际伤害（<0=免疫）：免疫/无伤由 apply_spell 方决定飘字
func _hit_enemy(e: EnemyUnit3D, element: String, dmg: float, dir := Vector3.ZERO, col := Color(1.0, 0.7, 0.3)) -> float:
	var dealt: float = e.apply_spell(element, dmg, dir)
	if dealt < 0.0:
		battlefield.spawn_text_label(e.aim_center() + Vector3.UP * 0.7, "免疫", Color(0.75, 0.85, 0.95))
	elif dealt > 0.0:
		battlefield.spawn_damage_label(e.aim_center() + Vector3.UP * 0.7, dealt, col)
	return dealt


## 测试/调试直入口：在指定点引爆火球 AoE
func debug_explode(point: Vector3) -> void:
	_apply_aoe(point)
	var boom := ExplosionFx.new()
	boom.position = point
	battlefield.fx_layer.add_child(boom)


func _cast_lightning(aim: Dictionary) -> void:
	var origin_p: Vector3 = aim["point"]
	var targets := _nearest_enemies(origin_p, LIGHTNING_TARGETS)
	battlefield.play_sfx("zap", origin_p, -3.0)
	var fx := LightningFx.new()
	fx.points.append(origin_p + Vector3.UP * 6.0)  # 从天而降
	for t in targets:
		fx.points.append(t.aim_center())
		_hit_enemy(t, "lightning", LIGHTNING_DMG, Vector3.ZERO, Color(0.8, 0.9, 1.0))
	battlefield.fx_layer.add_child(fx)


func _cast_ice_field(point: Vector3) -> void:
	battlefield.play_sfx("cast_ice", point, -3.0)
	var fx := IceFieldFx.new()
	fx.position = point
	battlefield.fx_layer.add_child(fx)
	# duplicate：同 _apply_aoe，冰域冻杀会移除元素打断遍历
	for e in battlefield.enemies.duplicate():
		if not e.alive:
			continue
		var d: float = e.global_position.distance_to(point)
		if d <= ICE_RADIUS:
			var dir: Vector3 = e.global_position - point
			dir.y = 0.0
			_hit_enemy(e, "ice", ICE_DMG, dir, Color(0.6, 0.9, 1.0))


func _cast_wind_blade(screen_pos: Vector2) -> void:
	var origin: Vector3 = battlefield.camera.project_ray_origin(screen_pos)
	var dir: Vector3 = battlefield.camera.project_ray_normal(screen_pos)
	dir.y = 0.0
	dir = dir.normalized()
	battlefield.play_sfx("cast_wind", Vector3.INF, -3.0)
	var fx := WindBladeFx.new()
	fx.wind_range = wind_range
	fx.setup(battlefield.PLAYER_POS, dir)
	battlefield.fx_layer.add_child(fx)
	# duplicate：同 _apply_aoe，风刃斩杀会移除元素打断遍历
	for e in battlefield.enemies.duplicate():
		if not e.alive:
			continue
		var rel: Vector3 = e.global_position - battlefield.PLAYER_POS
		rel.y = 0.0
		var dist: float = rel.length()
		if dist > wind_range:
			continue
		if rel.normalized().dot(dir) < cos(deg_to_rad(60.0)):
			continue
		var dealt := _hit_enemy(e, "wind", WIND_DMG, rel.normalized(), Color(0.75, 1.0, 0.7))
		if dealt > 0.0:
			e.knockback(rel.normalized(), WIND_KNOCKBACK)


func _cast_quick_shot() -> void:
	var nearest: EnemyUnit3D = null
	var best_d := INF
	for e in battlefield.enemies:
		if not e.alive:
			continue
		var d: float = e.global_position.distance_squared_to(battlefield.PLAYER_POS)
		if d < best_d:
			best_d = d
			nearest = e
	if nearest == null:
		return
	battlefield.play_sfx("bolt", Vector3.INF, -4.0)
	var fx := FireballProjectile.new()
	fx.caster = self
	fx.target = nearest.aim_center()
	fx.speed = 40.0
	fx.radius = 0.18
	fx.single_target = nearest
	fx.damage = QUICK_DMG
	fx.color = Color(1.0, 0.5, 0.15)
	var launch := battlefield.camera.global_position + battlefield.camera.global_transform.basis.z * 1.2
	fx.position = launch
	battlefield.fx_layer.add_child(fx)


func _nearest_enemies(point: Vector3, n: int) -> Array:
	var alive: Array = []
	for e in battlefield.enemies:
		if e.alive:
			alive.append(e)
	alive.sort_custom(func(a, b): return a.global_position.distance_squared_to(point) < b.global_position.distance_squared_to(point))
	return alive.slice(0, n)


# ---------------- 内嵌特效节点 ----------------

## 火球投射物：飞到目标点爆炸（AoE / 单体两用）
class FireballProjectile:
	extends Node3D
	var caster: SpellCaster3D
	var target := Vector3.ZERO
	var speed := FIREBALL_SPEED
	var radius := 0.28
	var damage := FIREBALL_DMG
	var aoe_radius := FIREBALL_RADIUS
	var single_target: EnemyUnit3D = null
	var color := Color(1.0, 0.35, 0.1)
	var _dodge_warned := false

	func _ready() -> void:
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		mesh.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 4.0
		mesh.material_override = mat
		add_child(mesh)

	func _process(delta: float) -> void:
		var to := target - global_position
		var step: float = speed * delta
		if to.length() <= step:
			_explode()
			return
		global_position += to.normalized() * step
		# 临近命中（≤0.4s）时预警幽灵闪避：落点在闪避半径内的 boo 隐身侧开
		if not _dodge_warned and caster != null:
			var remain := (target - global_position).length()
			if remain / speed <= 0.4:
				_dodge_warned = true
				for e in caster.battlefield.enemies:
					if e.has_method("try_dodge_fire"):
						e.try_dodge_fire(target)
		if single_target != null and not single_target.alive:
			_explode()  # 目标已死，原地补爆
			return

	func _explode() -> void:
		if caster == null:
			queue_free()
			return
		var bf := caster.battlefield
		if single_target != null and single_target.alive:
			var flight := (target - global_position)
			flight.y = 0.0
			caster._hit_enemy(single_target, "fire", damage, flight, Color(1.0, 0.5, 0.2))
		else:
			caster._apply_aoe(target)
		var boom := ExplosionFx.new()
		boom.position = target
		boom.radius = aoe_radius if single_target == null else 1.0
		bf.fx_layer.add_child(boom)
		bf.add_camera_shake(0.15)
		bf.play_sfx("boom", target, -5.0)
		queue_free()


## 爆炸：白核+橙焰双层球闪
class ExplosionFx:
	extends Node3D
	var radius := 2.5
	var _t := 0.0
	var _core: MeshInstance3D
	var _flare: MeshInstance3D

	func _ready() -> void:
		_core = _make_sphere(Color(1.0, 0.95, 0.8), 0.4)
		_flare = _make_sphere(Color(1.0, 0.5, 0.1), 1.0)
		add_child(_core)
		add_child(_flare)

	func _make_sphere(col: Color, initial_scale: float) -> MeshInstance3D:
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		mesh.mesh = sphere
		mesh.scale = Vector3.ONE * initial_scale * 0.3
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 5.0
		mesh.material_override = mat
		return mesh

	func _process(delta: float) -> void:
		_t += delta
		var p := clampf(_t / 0.35, 0.0, 1.0)
		_core.scale = Vector3.ONE * (0.3 + 0.5 * p)
		_flare.scale = Vector3.ONE * (0.3 + 1.1 * p)
		_flare.get_active_material(0).albedo_color.a = 1.0 - p
		if _t > 0.45:
			queue_free()


## 链电： jagged 折线（ImmediateMesh）
class LightningFx:
	extends Node3D
	var points: Array[Vector3] = []
	var _t := 0.0
	var _mesh: ImmediateMesh

	func _ready() -> void:
		if points.size() < 2:
			queue_free()  # 没劈中任何目标：无折线可画
			return
		_mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.9, 0.95, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.7, 0.85, 1.0)
		mat.emission_energy_multiplier = 6.0
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		for i in range(points.size() - 1):
			var seg := 6
			var prev: Vector3 = points[i]
			for j in range(1, seg + 1):
				var p := points[i].lerp(points[i + 1], float(j) / float(seg))
				if j < seg:
					p += Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
				_mesh.surface_add_vertex(prev)
				_mesh.surface_add_vertex(p)
				prev = p
		_mesh.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		add_child(mi)

	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.22:
			queue_free()


## 冰域：地面扩张圆盘 + 外环
class IceFieldFx:
	extends Node3D
	var radius := ICE_RADIUS
	var _t := 0.0
	var _disc: MeshInstance3D

	func _ready() -> void:
		_disc = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * radius * 2.0
		_disc.mesh = q
		_disc.rotation.x = -PI / 2.0
		_disc.position.y = 0.03
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.55, 0.85, 1.0, 0.35)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.85, 1.0)
		mat.emission_energy_multiplier = 1.5
		_disc.material_override = mat
		add_child(_disc)
		scale = Vector3(0.05, 1.0, 0.05)

	func _process(delta: float) -> void:
		_t += delta
		var p := clampf(_t / 0.4, 0.0, 1.0)
		var fade := clampf((3.0 - _t) / 0.8, 0.0, 1.0)
		scale = Vector3(p, 1.0, p)
		_disc.get_active_material(0).albedo_color.a = 0.35 * fade
		if _t > 3.0:
			queue_free()


## 风刃：竖直新月形气浪刃，沿施法方向高速切出并消隐。
## 读形要点（从玩家背后看）：中央前凸、两尖向后掠（TIP_SWEEP）、
## 轮廓两端收窄（taper）、端部渐隐（顶点色）——否则弦视角下读成"方块"。
class WindBladeFx:
	extends Node3D
	const SPAN_DEG := 56.0    # 新月弧度
	const H_MIN := 0.3
	const H_MAX := 3.1
	const RADIUS := 2.4
	const TIP_SWEEP := 1.1    # 两尖后掠距离（m）
	const DUR := 0.28
	var _t := 0.0
	var _dir := Vector3.FORWARD
	var _origin := Vector3.ZERO
	var wind_range := WIND_RANGE
	var _main_mat: StandardMaterial3D
	var _echo_mat: StandardMaterial3D
	var _echo: MeshInstance3D

	func setup(origin: Vector3, dir: Vector3) -> void:
		_dir = dir
		_origin = Vector3(origin.x, 0.0, origin.z)
		rotation.y = atan2(dir.x, dir.z)
		_main_mat = _make_mat(0.75, 2.4)
		_echo_mat = _make_mat(0.34, 1.4)
		add_child(_make_ribbon(_main_mat, RADIUS))
		_echo = _make_ribbon(_echo_mat, RADIUS * 0.7)
		add_child(_echo)

	func _make_mat(alpha: float, energy: float) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.82, 1.0, 0.86, alpha)
		m.emission_enabled = true
		m.emission = Color(0.7, 1.0, 0.8)
		m.emission_energy_multiplier = energy
		m.vertex_color_use_as_albedo = true  # 端部渐隐走顶点色
		m.cull_mode = BaseMaterial3D.CULL_DISABLED  # 双面：贴脸施法从内侧也可见
		return m

	## 新月轮廓采样：t∈[0,1]（0/1=两尖，0.5=中央）
	func _moon_point(t: float, radius: float) -> Dictionary:
		var a := deg_to_rad(SPAN_DEG) * (t - 0.5)
		var tip := absf(t - 0.5) * 2.0  # 0 中央 → 1 尖端
		var taper := sqrt(maxf(1.0 - tip * tip, 0.0))  # 轮廓收窄
		var lateral := sin(a) * radius
		var depth := cos(a) * radius - TIP_SWEEP * tip * tip  # 尖端后掠
		return {
			"bottom": Vector3(lateral, H_MIN + (1.0 - taper) * 0.9, depth),
			"top": Vector3(lateral, H_MIN + (H_MAX - H_MIN) * maxf(taper, 0.1), depth),
			"alpha": 0.35 + 0.65 * taper,
		}

	func _make_ribbon(mat: StandardMaterial3D, radius: float) -> MeshInstance3D:
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
		var segments := 12
		var prev: Dictionary = _moon_point(0.0, radius)
		for i in range(1, segments + 1):
			var cur: Dictionary = _moon_point(float(i) / segments, radius)
			var pb: Vector3 = prev["bottom"]
			var pt: Vector3 = prev["top"]
			var cb: Vector3 = cur["bottom"]
			var ct: Vector3 = cur["top"]
			mesh.surface_set_color(Color(1, 1, 1, prev["alpha"]))
			mesh.surface_add_vertex(pb)
			mesh.surface_set_color(Color(1, 1, 1, cur["alpha"]))
			mesh.surface_add_vertex(cb)
			mesh.surface_set_color(Color(1, 1, 1, cur["alpha"]))
			mesh.surface_add_vertex(ct)
			mesh.surface_set_color(Color(1, 1, 1, prev["alpha"]))
			mesh.surface_add_vertex(pb)
			mesh.surface_set_color(Color(1, 1, 1, cur["alpha"]))
			mesh.surface_add_vertex(ct)
			mesh.surface_set_color(Color(1, 1, 1, prev["alpha"]))
			mesh.surface_add_vertex(pt)
			prev = cur
		mesh.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.rotation.z = randf_range(-0.14, 0.14)  # 轻微侧倾，像挥砍的弧
		return mi

	func _process(delta: float) -> void:
		_t += delta
		var p := clampf(_t / DUR, 0.0, 1.0)
		global_position = _origin + _dir * (p * wind_range)
		# 残影落在主刃后方一段距离
		_echo.position = Vector3(0.0, 0.0, -0.2 * p * wind_range)
		_main_mat.albedo_color.a = 0.75 * (1.0 - p)
		_echo_mat.albedo_color.a = 0.34 * (1.0 - p)
		if _t > DUR + 0.04:
			queue_free()
