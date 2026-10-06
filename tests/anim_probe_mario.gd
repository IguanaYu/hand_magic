extends Node
## --anim-probe-mario：马里奥素材验证（headless 可跑）。
## 逐个实例化 assets3d/mario/*.glb，列出动画片段名（确认 idle/move 命名约定）
## 并输出模型包围盒尺寸（校准 UNIT_STATS scale 用）。
## 结果写 tests/anim_probe_mario.txt，进程码 0=PASS / 1=FAIL。

const UNITS := ["goomba", "koopa", "shell", "bowser", "boo", "coin", "pipe", "qblock", "brick"]

var _lines: Array[String] = []
var _pass := true


func _ready() -> void:
	_run()


func _run() -> void:
	for key in UNITS:
		var path := "res://assets3d/mario/%s.glb" % key
		if not ResourceLoader.exists(path):
			_fail("%s GLB 未导入: %s" % [key, path])
			continue
		var ps: PackedScene = load(path)
		var inst := ps.instantiate()
		add_child(inst)
		var ap := _find_anim_player(inst)
		if ap != null:
			var anims: Array = ap.get_animation_list()
			_lines.append("%s 动画(%d): %s" % [key, anims.size(), ", ".join(PackedStringArray(anims))])
		else:
			_lines.append("%s 动画: 无（纯静态）" % key)
		# 包围盒（世界空间，原点在节点根部）
		_aabb_size = Vector3.ZERO
		_accum_aabb(inst)
		_lines.append("%s 尺寸: %s" % [key, _aabb_size])
		inst.queue_free()
	_lines.append("verdict=" + ("PASS" if _pass else "FAIL"))
	_write()
	get_tree().quit(0 if _pass else 1)


var _aabb_size := Vector3.ZERO


func _accum_aabb(root: Node3D) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		_aabb_size = _aabb_size.max(box.size.abs())
	for c in root.get_children():
		if c is Node3D:
			_accum_aabb(c)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r: AnimationPlayer = _find_anim_player(c)
		if r != null:
			return r
	return null


func _fail(msg: String) -> void:
	_pass = false
	_lines.append("FAIL: " + msg)
	push_error("anim-probe-mario: " + msg)


func _write() -> void:
	var f := FileAccess.open("res://tests/anim_probe_mario.txt", FileAccess.WRITE)
	if f:
		for line in _lines:
			f.store_string(line + "\n")
		f.flush()
