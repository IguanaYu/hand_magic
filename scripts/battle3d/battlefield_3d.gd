class_name Battlefield3D
extends Node3D
## M1.0 3D 战场骨架：地面/天空/光照/相机站位/城堡布景/环境点缀。
## 后续里程碑在此扩展：敌人层(M1.1) 战斗(M1.2) 手势(M1.3) 波次(M1.4)。

const PLAYER_POS := Vector3(0.0, 1.65, 8.0)
const GROUND_SIZE := 160.0
const GROUND_COLOR := Color(0.36, 0.52, 0.30)
const BUILDING_SCALE := 2.5
## 布景随机种子（固定 → 每局布局一致）
const PROP_SEED := 20261005

const PATH_UNITS := "res://assets3d/units/%s.glb"
const PATH_BUILDINGS := "res://assets3d/buildings/%s.glb"
const PATH_ENV := "res://assets3d/env/%s.glb"

var camera: Camera3D
var ui_layer: CanvasLayer
var enemy_layer: Node3D
var bullet_layer: Node3D
var fx_layer: Node3D


func _ready() -> void:
	_build_environment()
	_build_lights()
	_build_ground()
	_build_castle()
	_scatter_props()
	_build_layers()
	_setup_camera()


func restart() -> void:
	pass  # M1.4 实现：清场 + 重置波次/得分


# ---------- 场景搭建 ----------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.56, 0.85)
	sky_mat.sky_horizon_color = Color(0.76, 0.86, 0.93)
	sky_mat.ground_bottom_color = Color(0.20, 0.30, 0.18)
	sky_mat.ground_horizon_color = Color(0.64, 0.74, 0.60)
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	# 城堡方向暖色补光
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 4.0, 22.0)
	fill.light_color = Color(1.0, 0.85, 0.7)
	fill.light_energy = 0.5
	fill.omni_range = 28.0
	add_child(fill)


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROUND_COLOR
	mat.roughness = 1.0
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.material_override = mat
	add_child(ground)


func _build_castle() -> void:
	# 指挥中心在玩家身后（逻辑上的大本营，画面外）；地堡/导弹塔前移到
	# 玩家前方两翼画面边缘，营造"驻守阵地"的第一人称构图（模型面朝 +Y，转 PI 朝 -Z 战场）
	_instance_glb(PATH_BUILDINGS % "b_command_center", Vector3(0.0, 0.0, 30.0), PI, BUILDING_SCALE * 1.6)
	_instance_glb(PATH_BUILDINGS % "b_bunker", Vector3(-11.0, 0.0, -2.0), PI, BUILDING_SCALE)
	_instance_glb(PATH_BUILDINGS % "b_bunker", Vector3(11.0, 0.0, -2.0), PI, BUILDING_SCALE)
	_instance_glb(PATH_BUILDINGS % "b_missile_turret", Vector3(-16.0, 0.0, -8.0), PI, BUILDING_SCALE * 0.9)
	_instance_glb(PATH_BUILDINGS % "b_missile_turret", Vector3(16.0, 0.0, -8.0), PI, BUILDING_SCALE * 0.9)


func _scatter_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PROP_SEED
	var props := ["e_rock", "e_tree", "e_mineral", "e_bush"]
	for i in 26:
		# 只布两翼（|x|>22 留空中路走廊），纵深覆盖战场
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * rng.randf_range(22.0, 46.0)
		var z := rng.randf_range(-42.0, 14.0)
		var key: String = props[rng.randi() % props.size()]
		var s := rng.randf_range(1.2, 2.8)
		_instance_glb(PATH_ENV % key, Vector3(x, 0.0, z), rng.randf() * TAU, s)
	# 城堡两侧矿场点缀
	_instance_glb(PATH_ENV % "e_mineral", Vector3(-16.0, 0.0, 14.0), 0.6, 2.2)
	_instance_glb(PATH_ENV % "e_mineral", Vector3(-17.5, 0.0, 12.0), 2.1, 1.8)
	_instance_glb(PATH_ENV % "e_mineral", Vector3(16.0, 0.0, 14.0), 0.6, 2.2)
	_instance_glb(PATH_ENV % "e_mineral", Vector3(17.5, 0.0, 12.0), 2.1, 1.8)


func _build_layers() -> void:
	enemy_layer = Node3D.new()
	enemy_layer.name = "Enemies"
	add_child(enemy_layer)
	bullet_layer = Node3D.new()
	bullet_layer.name = "Bullets"
	add_child(bullet_layer)
	fx_layer = Node3D.new()
	fx_layer.name = "FX"
	add_child(fx_layer)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.position = PLAYER_POS
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 300.0
	camera.current = true
	add_child(camera)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	ui_layer.layer = 10
	add_child(ui_layer)


func _instance_glb(path: String, pos: Vector3, rot_y: float, scl: float) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("GLB 未导入: " + path)
		return null
	var ps: PackedScene = load(path)
	var node := ps.instantiate()
	node.position = pos
	node.rotation.y = rot_y
	node.scale = Vector3.ONE * scl
	add_child(node)
	return node
