## Stores mutable encounter progress and authored scenario redirects.

class_name ScenarioEncounterState
extends RefCounted

var _timed_overrides: Dictionary = {}
var _eliminated_simple_options: Dictionary = {}
var _eliminated_complex_results: Dictionary = {}
var _attempts: Dictionary = {}
var _thief_type_flags: Dictionary = {}
var _program_overrides: Dictionary = {}


func set_timed_override(encounter_id: int, value: Dictionary) -> void:
	_timed_overrides[encounter_id] = value.duplicate(true)


func timed_override(encounter_id: int) -> Dictionary:
	return (_timed_overrides.get(encounter_id, {}) as Dictionary).duplicate(true)


func eliminate_simple_option(encounter_id: int, option_index: int) -> bool:
	if encounter_id < 0 or option_index < 0 or option_index > 3:
		return false
	_eliminated_simple_options["%d:%d" % [encounter_id, option_index]] = true
	return true


func simple_option_is_eliminated(encounter_id: int, option_index: int) -> bool:
	return _eliminated_simple_options.has("%d:%d" % [encounter_id, option_index])


func eliminate_complex_result(encounter_id: int, result_index: int) -> bool:
	if encounter_id < 0 or result_index < 0 or result_index > 3:
		return false
	_eliminated_complex_results["%d:%d" % [encounter_id, result_index]] = true
	return true


func complex_result_is_eliminated(encounter_id: int, result_index: int) -> bool:
	return _eliminated_complex_results.has("%d:%d" % [encounter_id, result_index])


func attempts(kind: StringName, encounter_id: int) -> int:
	return int(_attempts.get("%s:%d" % [String(kind), encounter_id], 0))


func record_attempt(kind: StringName, encounter_id: int) -> int:
	var key := "%s:%d" % [String(kind), encounter_id]
	var next := mini(32_767, int(_attempts.get(key, 0)) + 1)
	_attempts[key] = next
	return next


func thief_type_flags(encounter: ThiefEncounterDefinition) -> Array[bool]:
	var key := str(encounter.id)
	if not _thief_type_flags.has(key):
		return encounter.type_flags()
	var result: Array[bool] = []
	for value: Variant in _thief_type_flags[key]:
		result.append(bool(value))
	return result


func set_thief_type_flags(encounter: ThiefEncounterDefinition, flags: Array[bool]) -> bool:
	if encounter == null or flags.size() != 10:
		return false
	_thief_type_flags[str(encounter.id)] = flags.duplicate()
	return true


func set_program_override(source_program_id: String, target_program_id: String) -> bool:
	if source_program_id.is_empty() or target_program_id.is_empty():
		return false
	_program_overrides[source_program_id] = target_program_id
	return true


func program_id(source_program_id: String) -> String:
	return str(_program_overrides.get(source_program_id, source_program_id))


func write_to(data: Dictionary) -> void:
	data["timedEncounterOverrides"] = _timed_overrides_for_save()
	data["eliminatedSimpleOptions"] = _sorted_string_keys(_eliminated_simple_options)
	data["eliminatedComplexResults"] = _sorted_string_keys(_eliminated_complex_results)
	data["encounterAttempts"] = _sorted_dictionary(_attempts)
	data["thiefEncounterTypeFlags"] = _sorted_dictionary(_thief_type_flags)
	data["scenarioProgramOverrides"] = _sorted_dictionary(_program_overrides)


func restore_collections(data: Dictionary) -> bool:
	for field: String in ["timedEncounterOverrides", "eliminatedSimpleOptions", "encounterAttempts", "thiefEncounterTypeFlags", "scenarioProgramOverrides"]:
		if not data.has(field):
			return false
	return _restore_timed_overrides(data["timedEncounterOverrides"]) \
		and _restore_eliminated_results(data) \
		and _restore_attempts(data["encounterAttempts"]) \
		and _restore_thief_flags(data["thiefEncounterTypeFlags"]) \
		and _restore_program_overrides(data["scenarioProgramOverrides"])


func _restore_timed_overrides(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		if not key is String or not key.is_valid_int() or not value[key] is Dictionary:
			return false
		_timed_overrides[String(key).to_int()] = value[key].duplicate(true)
	return true


func _restore_eliminated_results(data: Dictionary) -> bool:
	if not data["eliminatedSimpleOptions"] is Array:
		return false
	for key: Variant in data["eliminatedSimpleOptions"]:
		if not _restore_eliminated_key(key, _eliminated_simple_options):
			return false
	if not data.has("eliminatedComplexResults"):
		return true
	if not data["eliminatedComplexResults"] is Array:
		return false
	for key: Variant in data["eliminatedComplexResults"]:
		if not _restore_eliminated_key(key, _eliminated_complex_results, true):
			return false
	return true


func _restore_eliminated_key(value: Variant, destination: Dictionary, strict: bool = false) -> bool:
	if not value is String or value.is_empty():
		return false
	if strict:
		var parts := String(value).split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or parts[0].to_int() < 0 or parts[1].to_int() < 0 or parts[1].to_int() > 3:
			return false
	destination[value] = true
	return true


func _restore_attempts(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		var count := _integer(value[key])
		if not key is String or key.is_empty() or count < 0 or count > 32_767:
			return false
		_attempts[key] = count
	return true


func _restore_thief_flags(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		var flags: Variant = value[key]
		if not key is String or not String(key).is_valid_int() or not flags is Array or flags.size() != 10:
			return false
		var copied: Array[bool] = []
		for flag: Variant in flags:
			if not flag is bool:
				return false
			copied.append(flag)
		_thief_type_flags[key] = copied
	return true


func _restore_program_overrides(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		var target: Variant = value[key]
		if not key is String or key.is_empty() or not target is String or target.is_empty():
			return false
		_program_overrides[key] = target
	return true


func _timed_overrides_for_save() -> Dictionary:
	var result: Dictionary = {}
	var encounter_ids: Array = _timed_overrides.keys()
	encounter_ids.sort()
	for encounter_id: Variant in encounter_ids:
		result[str(encounter_id)] = (_timed_overrides[encounter_id] as Dictionary).duplicate(true)
	return result


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in source:
		result.append(String(key))
	result.sort()
	return result


static func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = source.keys()
	keys.sort()
	for key: Variant in keys:
		result[key] = source[key]
	return result
