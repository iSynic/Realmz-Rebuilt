## Encodes bounded Safe Scenario Action values with explicit type tags so JSON saves preserve int, float and structure.

class_name ScenarioValueCodec
extends RefCounted


static func is_safe(value: Variant, depth: int = 0) -> bool:
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
			if not is_safe(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		if value.size() > 256:
			return false
		for key: Variant in value.keys():
			if not key is String or not is_safe(value[key], depth + 1):
				return false
		return true
	return false


static func encode(value: Variant) -> Dictionary:
	if value == null:
		return {"type": "null"}
	if value is bool:
		return {"type": "bool", "value": value}
	if value is int:
		return {"type": "int", "value": value}
	if value is float:
		return {"type": "float", "value": value}
	if value is String or value is StringName:
		return {"type": "string", "value": String(value)}
	if value is Array:
		var entries: Array[Dictionary] = []
		for child: Variant in value:
			entries.append(encode(child))
		return {"type": "array", "value": entries}
	if not value is Dictionary:
		push_error("Safe Action value of type %s cannot be encoded; it is saved as null." % type_string(typeof(value)))
		return {"type": "null"}
	var fields: Dictionary = {}
	var keys: Array = value.keys()
	keys.sort()
	for key: Variant in keys:
		fields[key] = encode(value[key])
	return {"type": "record", "value": fields}


## Returns {"ok": bool, "value": Variant}; depth is bounded at 32.
static func decode(value: Variant, depth: int = 0) -> Dictionary:
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
				var decoded := decode(child, depth + 1)
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
				var decoded := decode(value["value"][key], depth + 1)
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
