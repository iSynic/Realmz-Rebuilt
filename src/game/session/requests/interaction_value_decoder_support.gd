## Provides strict shared wire-shape validation for feature-owned interaction value decoders.

class_name InteractionValueDecoderSupport
extends RefCounted


static func exact(data: Dictionary, allowed: Array, required: Array = []) -> bool:
	for key: Variant in data:
		if not key is String or not allowed.has(key):
			return false
	for key: Variant in required:
		if not data.has(key):
			return false
	return true


static func strings(data: Dictionary, fields: Array) -> bool:
	for field: Variant in fields:
		if not data.get(field) is String:
			return false
	return true


static func ints(data: Dictionary, fields: Array) -> bool:
	for field: Variant in fields:
		if not whole(data.get(field)):
			return false
	return true


static func bools(data: Dictionary, fields: Array) -> bool:
	for field: Variant in fields:
		if not data.get(field) is bool:
			return false
	return true


static func optional_string(data: Dictionary, field: String) -> bool:
	return not data.has(field) or data[field] is String


static func optional_int(data: Dictionary, field: String) -> bool:
	return not data.has(field) or whole(data[field])


static func optional_strings(data: Dictionary, fields: Array) -> bool:
	for field: Variant in fields:
		if not optional_string(data, field):
			return false
	return true


static func optional_ints(data: Dictionary, fields: Array) -> bool:
	for field: Variant in fields:
		if not optional_int(data, field):
			return false
	return true


static func optional_bools(data: Dictionary, fields: Array) -> bool:
	for field: Variant in fields:
		if data.has(field) and not data[field] is bool:
			return false
	return true


static func optional_resource_key(data: Dictionary) -> bool:
	if data.has("iconResourceType") != data.has("iconId"):
		return false
	if not data.has("iconId"):
		return true
	return data["iconResourceType"] is String and not String(data["iconResourceType"]).is_empty() and whole(data["iconId"]) and int(data["iconId"]) > 0


static func whole(value: Variant) -> bool:
	return value is int or value is float and is_finite(value) and value == floor(value)


static func coordinate(value: Variant) -> bool:
	return value is Array and value.size() == 2 and whole(value[0]) and whole(value[1])


static func vector(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


static func string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry: Variant in value:
		if not entry is String:
			return false
	return true


static func string_values(value: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in value:
		result.append(entry)
	return result
