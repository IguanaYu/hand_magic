class_name RuneSamples
extends RefCounted
## 玩家录制的符文样本存取（user://rune_samples.json）。
## 设计原则（GDD §3.4 宽容）：文件缺失/损坏/版本不符一律按无样本处理，
## 不录制也能玩——内置模板始终参与识别，玩家样本只是附加。
## key 用 spell_id（fireball/...），存取时经 GestureFSM.RUNE_TO_SPELL 反查符文名。


const SAVE_PATH := "user://rune_samples.json"
const FORMAT_VERSION := 1
const MAX_PER_SPELL := 10
const MIN_POINTS := 8        # 与 DollarRecognizer.recognize 的最低门槛一致
const MIN_PATH_LEN := 0.08   # 同上：归一化坐标下的最小路径长

## 实例化时可覆盖存档路径（单测用，避免覆盖玩家真实存档）
var save_path := SAVE_PATH
var samples := {}  # spell_id -> Array（每项为 Array[Vector2] 轨迹）


func load() -> bool:
	samples.clear()
	if not FileAccess.file_exists(save_path):
		return false
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != FORMAT_VERSION:
		return false
	var data = parsed.get("samples", {})
	if typeof(data) != TYPE_DICTIONARY:
		return false
	for spell_id in data:
		if GestureFSM.RUNE_TO_SPELL.values().has(spell_id) == false:
			continue
		var arr: Array = data[spell_id]
		if typeof(arr) != TYPE_ARRAY:
			continue
		var strokes: Array = []
		for s in arr:
			var pts := _decode_points(s)
			if valid_stroke(pts):
				strokes.append(pts)
		if strokes.size() > 0:
			samples[spell_id] = strokes
	return samples.size() > 0


func save() -> bool:
	var data := {"version": FORMAT_VERSION, "samples": {}}
	for spell_id in samples:
		var strokes: Array = []
		for pts in samples[spell_id]:
			strokes.append(_encode_points(pts))
		data["samples"][spell_id] = strokes
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	return true


## 追加一笔样本（带校验与上限）。返回 "ok" / "invalid" / "full"
func add(spell_id: String, pts: Array) -> String:
	if not valid_stroke(pts):
		return "invalid"
	if not samples.has(spell_id):
		samples[spell_id] = []
	var strokes: Array = samples[spell_id]
	if strokes.size() >= MAX_PER_SPELL:
		return "full"
	strokes.append(pts)
	return "ok"


func clear_spell(spell_id: String) -> void:
	samples.erase(spell_id)


func clear_all() -> void:
	samples.clear()


func count(spell_id: String) -> int:
	return samples[spell_id].size() if samples.has(spell_id) else 0


func all_counts() -> Dictionary:
	var out := {}
	for spell_id in samples:
		out[spell_id] = samples[spell_id].size()
	return out


## spell_id → 符文名（fireball→circle），面板与识别器注入共用
static func rune_of(spell_id: String) -> String:
	for rune_name in GestureFSM.RUNE_TO_SPELL:
		if GestureFSM.RUNE_TO_SPELL[rune_name] == spell_id:
			return rune_name
	return ""


## 轨迹有效性：点数与路径长都过识别器最低门槛
static func valid_stroke(pts: Array) -> bool:
	if pts.size() < MIN_POINTS:
		return false
	var total := 0.0
	for i in range(pts.size() - 1):
		total += (pts[i + 1] - pts[i]).length()
	return total >= MIN_PATH_LEN


static func _encode_points(pts: Array) -> Array:
	var out: Array = []
	for p in pts:
		out.append([float(p.x), float(p.y)])
	return out


static func _decode_points(arr) -> Array:
	var out: Array = []
	if typeof(arr) != TYPE_ARRAY:
		return out
	for e in arr:
		if typeof(e) == TYPE_ARRAY and e.size() == 2:
			out.append(Vector2(float(e[0]), float(e[1])))
	return out
