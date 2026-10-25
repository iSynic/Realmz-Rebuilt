## Defines the scenario action state contract for scenario execution.

class_name ScenarioActionState
extends RefCounted

const MAX_ENTRIES: int = 4096

var _values: Dictionary = {}


func read(state_scope: String, owner_id: String, name: String, default_value: Variant = null) -> Variant:
	return _values.get(_key(state_scope, owner_id, name), default_value)


func write(state_scope: String, owner_id: String, name: String, value: Variant) -> bool:
	var key := _key(state_scope, owner_id, name)
	if not _values.has(key) and _values.size() >= MAX_ENTRIES:
		return false
	if not ScenarioValueCodec.is_safe(value):
		return false
	_values[key] = value
	return true


func to_data(decimal_integers: bool = true) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = _values.keys()
	keys.sort()
	for key: Variant in keys:
		result[key] = ScenarioValueCodec.encode(_values[key], decimal_integers)
	return result


static func from_data(data: Variant, decimal_integers: bool = true) -> ScenarioActionState:
	if not data is Dictionary:
		return null
	var entries: Dictionary = data
	if entries.size() > MAX_ENTRIES:
		return null
	var state := ScenarioActionState.new()
	for key: Variant in entries.keys():
		if not key is String:
			return null
		var key_text: String = key
		if key_text.is_empty():
			return null
		var decoded := ScenarioValueCodec.decode(entries[key], 0, decimal_integers)
		if not decoded["ok"]:
			return null
		state._values[key] = decoded["value"]
	return state


static func _key(state_scope: String, owner_id: String, name: String) -> String:
	return "%s:%s:%s" % [state_scope, owner_id, name]
