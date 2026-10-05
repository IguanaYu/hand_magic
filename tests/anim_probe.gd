extends Node
## --anim-probe：M1.0 动画资产验证（headless 可跑）。
## 实例化 marine/marauder，断言 idle/move/attack 三段动画存在且能播放，
## 结果写 tests/anim_probe_result.txt，进程码 0=PASS / 1=FAIL。

const UNITS := ["marine", "marauder"]
const CLIPS := ["idle", "move", "attack"]

var _lines: Array[String] = []
var _pass := true


func _ready() -> void:
	_run()


func _run() -> void:
	for key in UNITS:
		var path := "res://assets3d/units/%s.glb" % key
		if not ResourceLoader.exists(path):
			_fail("%s GLB 未导入: %s" % [key, path])
			continue
		var ps: PackedScene = load(path)
		var inst := ps.instantiate()
		add_child(inst)
		var ap := _find_anim_player(inst)
		if ap == null:
			_fail("%s 场景内无 AnimationPlayer" % key)
			inst.queue_free()
			continue
		var anims: Array = ap.get_animation_list()
		_lines.append("%s 动画清单(%d): %s" % [key, anims.size(), ", ".join(PackedStringArray(anims))])
		for clip in CLIPS:
			var anim_name := "%s_%s" % [key, clip]
			if not ap.has_animation(anim_name):
				_fail("%s 缺动画 %s" % [key, anim_name])
				continue
			var anim: Animation = ap.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR
			ap.play(anim_name)
			await get_tree().create_timer(0.5).timeout
			if not ap.is_playing():
				_fail("%s %s 播放失败" % [key, anim_name])
			else:
				_lines.append("%s %s OK (%.2fs, %d 轨道)" % [key, anim_name, anim.length, anim.get_track_count()])
			ap.stop()
		inst.queue_free()
	_lines.append("verdict=" + ("PASS" if _pass else "FAIL"))
	_write()
	get_tree().quit(0 if _pass else 1)


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
	push_error("anim-probe: " + msg)


func _write() -> void:
	var f := FileAccess.open("res://tests/anim_probe_result.txt", FileAccess.WRITE)
	if f:
		for line in _lines:
			f.store_string(line + "\n")
		f.flush()
