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
	if not _json_safe(value, 0):
		return false
	_values[key] = value
	return true


func to_data() -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = _values.keys()
	keys.sort()
	for key: Variant in keys:
		result[key] = _encode(_values[key])
	return result


static func from_data(data: Variant) -> ScenarioActionState:
	if not data is Dictionary or data.size() > MAX_ENTRIES:
		return null
	var state := ScenarioActionState.new()
	for key: Variant in data.keys():
		if not key is String or key.is_empty():
			return null
		var decoded := _decode(data[key], 0)
		if not decoded["ok"]:
			return null
		state._values[key] = decoded["value"]
	return state


static func _key(state_scope: String, owner_id: String, name: String) -> String:
	return "%s:%s:%s" % [state_scope, owner_id, name]


static func _json_safe(value: Variant, depth: int) -> bool:
	if depth > 32:
		return false
	if value == null or value is bool or value is int or value is String:
		return true
	if value is float:
		return not is_nan(value) and not is_inf(value)
	if value is Array:
		if value.size() > 256:
			return false
		for child: Variant in value:
			if not _json_safe(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		if value.size() > 256:
			return false
		for key: Variant in value.keys():
			if not key is String or not _json_safe(value[key], depth + 1):
				return false
		return true
	return false


static func _encode(value: Variant) -> Dictionary:
	if value == null:
		return {"type": "null"}
	if value is bool:
		return {"type": "bool", "value": value}
	if value is int:
		return {"type": "int", "value": value}
	if value is float:
		return {"type": "float", "value": value}
	if value is String:
		return {"type": "string", "value": value}
	if value is Array:
		var entries: Array[Dictionary] = []
		for child: Variant in value:
			entries.append(_encode(child))
		return {"type": "array", "value": entries}
	var fields: Dictionary = {}
	var keys: Array = value.keys()
	keys.sort()
	for key: Variant in keys:
		fields[key] = _encode(value[key])
	return {"type": "record", "value": fields}


static func _decode(value: Variant, depth: int) -> Dictionary:
	if depth > 32 or not value is Dictionary or not value.get("type") is String:
		return {"ok": false}
	match value["type"]:
		"null":
			return {"ok": value.size() == 1, "value": null}
		"bool":
			return {"ok": value.size() == 2 and value.get("value") is bool, "value": value.get("value")}
		"int":
			var integer: Variant = _integer(value.get("value"))
			return {"ok": value.size() == 2 and integer != null, "value": integer}
		"float":
			var number: Variant = value.get("value")
			return {"ok": value.size() == 2 and (number is int or number is float) and not is_nan(float(number)) and not is_inf(float(number)), "value": float(number) if number is int or number is float else 0.0}
		"string":
			return {"ok": value.size() == 2 and value.get("value") is String, "value": value.get("value")}
		"array":
			if value.size() != 2 or not value.get("value") is Array or value["value"].size() > 256:
				return {"ok": false}
			var entries: Array = []
			for child: Variant in value["value"]:
				var decoded := _decode(child, depth + 1)
				if not decoded["ok"]:
					return {"ok": false}
				entries.append(decoded["value"])
			return {"ok": true, "value": entries}
		"record":
			if value.size() != 2 or not value.get("value") is Dictionary or value["value"].size() > 256:
				return {"ok": false}
			var fields: Dictionary = {}
			for key: Variant in value["value"].keys():
				if not key is String:
					return {"ok": false}
				var decoded := _decode(value["value"][key], depth + 1)
				if not decoded["ok"]:
					return {"ok": false}
				fields[key] = decoded["value"]
			return {"ok": true, "value": fields}
	return {"ok": false}


static func _integer(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return null
