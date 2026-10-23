class_name SpellLoadout
extends RefCounted
## 法术装备配置：玩家勾选当前可施放的法术，同时最多 MAX_EQUIPPED 个（暂定 5）。
## 数据源是 SpellCodex.entries()（单一来源）；本类只存"勾了哪些 spell_id"。
## 持久化 user://spell_loadout.json（RuneSamples 范式：版本化 + 任何损坏/缺失
## 一律静默降级回"默认全装备"，绝不弹错——存档坏了也得能玩）。
## 施法闸消费方：GestureFSM._release / _quick_shot / battlefield_3d 数字键直放。
## loadout 为 null 时视为全装备（旧调用方/旧测试零改动兼容）。


const SAVE_PATH := "user://spell_loadout.json"
const FORMAT_VERSION := 1
const MAX_EQUIPPED := 5  # 同时可施放的法术上限（暂定，后续池子变大时调这里）

signal changed

var save_path := SAVE_PATH
## 生效上限（实例字段，默认取 MAX_EQUIPPED）：做成实例字段才能在单测里调小
## 验证"超上限拒绝"路径（当前池子恰好 5 个=上限，const 触发不了），日后难度
## 模式要差异化上限也走这里
var max_equipped: int = MAX_EQUIPPED
var equipped: Array[String] = []


func _init() -> void:
	reset_default()


## 全部法术 id（来自 SpellCodex 单一数据源）
static func all_spell_ids() -> Array:
	var out: Array = []
	for e in SpellCodex.entries():
		out.append(str(e["id"]))
	return out


static func is_valid_id(spell_id: String) -> bool:
	return all_spell_ids().has(spell_id)


## 默认 = 全装备（无存档/存档损坏时的语义，现役玩法零变化）
func reset_default() -> void:
	equipped.clear()
	for id in all_spell_ids():
		equipped.append(str(id))
	changed.emit()


func is_equipped(spell_id: String) -> bool:
	return equipped.has(spell_id)


func count() -> int:
	return equipped.size()


## 勾选。返回 "ok" / "full"（超上限拒绝）/ "unknown"（非法 id）。
func equip(spell_id: String) -> String:
	if not is_valid_id(spell_id):
		return "unknown"
	if is_equipped(spell_id):
		return "ok"
	if equipped.size() >= max_equipped:
		return "full"
	equipped.append(spell_id)
	changed.emit()
	return "ok"


func unequip(spell_id: String) -> void:
	var had := equipped.has(spell_id)
	equipped.erase(spell_id)
	if had:
		changed.emit()


## 装备中的法术条目（SpellCodex 子集，保持 entries 顺序），图鉴/法术栏过滤用
func equipped_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in SpellCodex.entries():
		if is_equipped(str(e["id"])):
			out.append(e)
	return out


func load() -> bool:
	equipped.clear()
	if not FileAccess.file_exists(save_path):
		reset_default()
		return false
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		reset_default()
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != FORMAT_VERSION:
		reset_default()
		return false
	var data = parsed.get("equipped", [])
	if typeof(data) != TYPE_ARRAY:
		reset_default()
		return false
	for id in data:
		var sid := str(id)
		if is_valid_id(sid) and not equipped.has(sid):
			equipped.append(sid)
	if equipped.is_empty():
		# 空装备 = 存档内容异常（全不勾没法玩），按无存档处理
		reset_default()
		return false
	return true


func save() -> bool:
	var data := {"version": FORMAT_VERSION, "equipped": equipped}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	return true
