## Encodes bounded Safe Scenario Action values with explicit type tags so JSON saves preserve int, float and structure.

class_name ScenarioValueCodec
extends RefCounted


static func is_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value == null or value is bool or value is int or value is String:
		return true
	if value is float:
		var number: float = value
		return not is_nan(number) and not is_inf(number)
	if value is Array:
		var items: Array = value
		if items.size() > 256:
			return false
		for child: Variant in items:
			if not is_safe(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		var record: Dictionary = value
		if record.size() > 256:
			return false
		for key: Variant in record.keys():
			if not key is String or not is_safe(record[key], depth + 1):
				return false
		return true
	return false


static func encode(value: Variant, decimal_integers: bool = false) -> Dictionary:
	if value == null:
		return {"type": "null"}
	if value is bool:
		return {"type": "bool", "value": value}
	if value is int:
		# JSON numbers pass through a double. Decimal text retains all 64 bits.
		return {"type": "int", "value": str(value) if decimal_integers else value}
	if value is float:
		return {"type": "float", "value": value}
	if value is String or value is StringName:
		var text: String = value
		return {"type": "string", "value": text}
	if value is Array:
		var entries: Array[Dictionary] = []
		for child: Variant in value:
			entries.append(encode(child, decimal_integers))
		return {"type": "array", "value": entries}
	if not value is Dictionary:
		push_error("Safe Action value of type %s cannot be encoded; it is saved as null." % type_string(typeof(value)))
		return {"type": "null"}
	var record: Dictionary = value
	var fields: Dictionary = {}
	var keys: Array = record.keys()
	keys.sort()
	for key: Variant in keys:
		fields[key] = encode(record[key], decimal_integers)
	return {"type": "record", "value": fields}


## Returns {"ok": bool, "value": Variant}; depth is bounded at 32.
static func decode(value: Variant, depth: int = 0, decimal_integers: bool = false) -> Dictionary:
	if depth > 32 or not value is Dictionary:
		return {"ok": false}
	var data: Dictionary = value
	if not data.get("type") is String:
		return {"ok": false}
	match data["type"]:
		"null":
			return {"ok": data.size() == 1, "value": null}
		"bool":
			return {"ok": data.size() == 2 and data.get("value") is bool, "value": data.get("value")}
		"int":
			var integer: Variant = _integer(data.get("value"), decimal_integers)
			return {"ok": data.size() == 2 and integer != null, "value": integer}
		"float":
			var number: Variant = data.get("value")
			var numeric := number is int or number is float
			var as_float: float = number if numeric else 0.0
			return {"ok": data.size() == 2 and numeric and not is_nan(as_float) and not is_inf(as_float), "value": as_float}
		"string":
			return {"ok": data.size() == 2 and data.get("value") is String, "value": data.get("value")}
		"array":
			if data.size() != 2 or not data.get("value") is Array:
				return {"ok": false}
			var items: Array = data["value"]
			if items.size() > 256:
				return {"ok": false}
			var entries: Array = []
			for child: Variant in items:
				var decoded := decode(child, depth + 1, decimal_integers)
				if not decoded["ok"]:
					return {"ok": false}
				entries.append(decoded["value"])
			return {"ok": true, "value": entries}
		"record":
			if data.size() != 2 or not data.get("value") is Dictionary:
				return {"ok": false}
			var record: Dictionary = data["value"]
			if record.size() > 256:
				return {"ok": false}
			var fields: Dictionary = {}
			for key: Variant in record.keys():
				if not key is String:
					return {"ok": false}
				var decoded := decode(record[key], depth + 1, decimal_integers)
				if not decoded["ok"]:
					return {"ok": false}
				fields[key] = decoded["value"]
			return {"ok": true, "value": fields}
	return {"ok": false}


static func _integer(value: Variant, decimal_integers: bool) -> Variant:
	if value is String and decimal_integers:
		var text: String = value
		if text.length() > 20 or not text.is_valid_int():
			return null
		var number := text.to_int()
		return number if str(number) == text else null
	if decimal_integers:
		return null
	if value is int:
		return value
	if value is float:
		var number: float = value
		# Numeric payloads are the schema-4 representation, retained for reading.
		return int(number) if is_equal_approx(number, roundf(number)) else null
	return null
