class_name EnemyBullet3D
extends Node3D
## M1.2 敌方曳光弹：直线飞向目标点，接近玩家胸口即命中。
## 失准弹的目标点带横向偏移，会擦过相机飞过（演出感）。

signal delivered(dmg: float)

var damage := 4.0
var big := false          # 掠夺者大弹
var blockable := true     # M1.3 护盾格挡
var life := 4.0

var _velocity := Vector3.ZERO
var _player_chest := Vector3.ZERO


func setup(from: Vector3, target: Vector3, p_damage: float, speed: float, p_big: bool, player_chest: Vector3) -> void:
	global_position = from
	_player_chest = player_chest
	damage = p_damage
	big = p_big
	_velocity = (target - from).normalized() * speed


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.28, 0.28, 1.1) if big else Vector3(0.07, 0.07, 0.5)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.15) if big else Color(1.0, 0.9, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.1) if big else Color(1.0, 0.85, 0.25)
	mat.emission_energy_multiplier = 3.0
	mesh.material_override = mat
	add_child(mesh)
	# 沿速度方向拉伸朝向
	look_at(global_position + _velocity, Vector3.UP)


func _process(delta: float) -> void:
	global_position += _velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if global_position.distance_to(_player_chest) < (1.0 if big else 0.7):
		delivered.emit(damage)
		queue_free()
