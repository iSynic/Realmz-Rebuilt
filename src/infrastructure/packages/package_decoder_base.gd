class_name PackageDecoderBase
extends RefCounted

var _diagnostic: Dictionary

func _init(diagnostic: Dictionary = {}) -> void:
	_diagnostic = diagnostic
	if not _diagnostic.has("message"):
		_diagnostic["message"] = ""

func clear_error() -> void:
	_diagnostic["message"] = ""

func error_message() -> String:
	return String(_diagnostic.get("message", ""))

func _has_fields(value: Dictionary, fields: Array[String], label: String) -> bool:
	for field: String in fields:
		if not value.has(field):
			return _reject("%s is missing required field '%s'." % [label, field])
	return true

func _is_sha256(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true

func _exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true

func _string_array(value: Variant, label: String) -> Variant:
	if not value is Array:
		_reject("%s must be an array." % label)
		return null
	var strings: Array[String] = []
	for item: Variant in value:
		if not item is String or item.is_empty() or strings.has(item):
			_reject("%s contains an invalid or duplicate ID." % label)
			return null
		strings.append(item)
	return strings

func _string_list(value: Variant, label: String, allow_empty: bool = false) -> Variant:
	if not value is Array or value.size() > 4096:
		_reject("%s must be a bounded array." % label)
		return null
	var strings: Array[String] = []
	for item: Variant in value:
		if not item is String or not allow_empty and item.is_empty():
			_reject("%s contains an invalid ID." % label)
			return null
		strings.append(item)
	return strings

func _fixed_string_list(value: Variant, expected_size: int, maximum_length: int, label: String) -> Variant:
	if not value is Array or value.size() != expected_size:
		_reject("%s must contain %d strings." % [label, expected_size])
		return null
	var strings: Array[String] = []
	for item: Variant in value:
		if not item is String or item.length() > maximum_length:
			_reject("%s contains an invalid string." % label)
			return null
		strings.append(item)
	return strings

func _fixed_or_empty_string_list(value: Variant, expected_size: int, maximum_length: int, label: String) -> Variant:
	if value is Array and value.is_empty():
		var empty_slots: Array[String] = []
		empty_slots.resize(expected_size)
		empty_slots.fill("")
		return empty_slots
	return _fixed_string_list(value, expected_size, maximum_length, label)

func _boolean_array(value: Variant, expected_size: int, label: String) -> Variant:
	if not value is Array or value.size() != expected_size:
		_reject("%s must contain %d booleans." % [label, expected_size])
		return null
	var booleans: Array[bool] = []
	for item: Variant in value:
		if not item is bool:
			_reject("%s contains a non-boolean." % label)
			return null
		booleans.append(item)
	return booleans

func _validated_integer_fields(record: Dictionary, fields: Array[String], label: String) -> Variant:
	var result: Dictionary = {}
	for field: String in fields:
		if not record.has(field) or not _is_integer(record[field]):
			_reject("%s field '%s' must be an integer." % [label, field])
			return null
		result[field] = _integer(record[field])
	return result

func _integers_in_range(values: Dictionary, fields: Array[String], minimum: int, maximum: int) -> bool:
	for field: String in fields:
		var value := int(values[field])
		if value < minimum or value > maximum:
			return false
	return true

func _array_values_in_range(values: Array[int], minimum: int, maximum: int) -> bool:
	for value: int in values:
		if value < minimum or value > maximum:
			return false
	return true

func _definition_identity(record: Dictionary, ids: Dictionary, _label: String, requires_name: bool = true) -> bool:
	if not record.get("id") is String or record["id"].is_empty() or requires_name and (not record.get("name") is String or record["name"].is_empty()) or ids.has(record["id"]):
		return false
	ids[record["id"]] = true
	return true

func _definition_ids(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value: Variant in values:
		result[value.id] = true
	return result

func _integer_array(value: Variant, expected_size: int, label: String) -> Variant:
	if not value is Array or value.size() != expected_size:
		_reject("%s must contain %d integers." % [label, expected_size])
		return null
	var integers: Array[int] = []
	for item: Variant in value:
		if not _is_integer(item):
			_reject("%s contains a non-integer." % label)
			return null
		integers.append(_integer(item))
	return integers

func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1

func _is_integer(value: Variant) -> bool:
	return value is int or value is float and is_equal_approx(value, round(value))

func _safe_identifier(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		var lower := code >= 97 and code <= 122
		var digit := code >= 48 and code <= 57
		if not lower and not (digit and index > 0) and not (code == 95 and index > 0):
			return false
	return true

func _json_safe(value: Variant, depth: int) -> bool:
	if depth > 64:
		return false
	if value == null or value is bool or value is int or value is float or value is String:
		return true
	if value is Array:
		if value.size() > 4096:
			return false
		for child: Variant in value:
			if not _json_safe(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		if value.size() > 4096:
			return false
		for key: Variant in value.keys():
			if not key is String or not _json_safe(value[key], depth + 1):
				return false
		return true
	return false

func _reject(message: String) -> bool:
	_diagnostic["message"] = message
	return false
