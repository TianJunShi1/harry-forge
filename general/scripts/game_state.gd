extends Node

## 跨场景持久数据（autoload）。
## 注意：不能用 class_name —— autoload 名 GameState 已是全局标识符。

signal flag_changed(key: StringName, value: Variant)
signal clue_collected(clue_id: StringName)

var flags: Dictionary = {}
var clues: Array[StringName] = []
var inventory: Array[StringName] = []


func set_flag(key: StringName, value: Variant) -> void:
	flags[key] = value
	flag_changed.emit(key, value)


func get_flag(key: StringName, default: Variant = null) -> Variant:
	return flags.get(key, default)


## 收集线索。首次收集返回 true，重复收集返回 false。
func collect_clue(clue_id: StringName) -> bool:
	if clues.has(clue_id):
		return false
	clues.append(clue_id)
	clue_collected.emit(clue_id)
	return true


func has_clue(clue_id: StringName) -> bool:
	return clues.has(clue_id)
