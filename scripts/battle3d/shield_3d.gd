class_name Shield3D
extends Node3D
## M1.3 魔法护盾：玩家正面半透明半球，格挡进入范围的敌方子弹。
## 触发/法力消耗由 battlefield 决定，这里只负责视觉与挡弹几何。

const RADIUS := 1.6
const CENTER_OFFSET := Vector3(0.0, 0.0, -1.1)  # 相机前方（-Z）

var active := false:
	set(v):
		active = v
		visible = v

var _t := 0.0
var _mesh: MeshInstance3D


func setup(player_pos: Vector3) -> void:
	position = player_pos + CENTER_OFFSET
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	_mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.22)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.75, 1.0)
	mat.emission_energy_multiplier = 1.6
	_mesh.material_override = mat
	add_child(_mesh)
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	# 呼吸感微缩放
	_mesh.scale = Vector3.ONE * (1.0 + 0.02 * sin(_t * 6.0))


## 子弹是否进入护盾范围（由 battlefield 每帧询问）
func blocks(bullet_pos: Vector3) -> bool:
	if not active:
		return false
	return bullet_pos.distance_to(global_position) <= RADIUS


## 被击闪一下
func flash() -> void:
	var mat: StandardMaterial3D = _mesh.get_active_material(0)
	var col: Color = mat.albedo_color
	mat.albedo_color = Color(0.7, 0.95, 1.0, 0.5)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color", col, 0.18)
