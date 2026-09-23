## Describes one preserved legacy reference whose target is unavailable during package loading.

class_name ScenarioCompatibilityWarning
extends RefCounted

var source_kind: StringName
var source_id: String
var field: String
var slot: int
var target_kind: StringName
var target_id: String
var reason: String
var native_path: String
var native_offset: int


func _init(
		warning_source_kind: StringName,
		warning_source_id: String,
		warning_field: String,
		warning_slot: int,
		warning_target_kind: StringName,
		warning_target_id: Variant,
		warning_reason: String,
		warning_native_path: String = "",
		warning_native_offset: int = -1
) -> void:
	source_kind = warning_source_kind
	source_id = warning_source_id
	field = warning_field
	slot = warning_slot
	target_kind = warning_target_kind
	target_id = str(warning_target_id)
	reason = warning_reason
	native_path = warning_native_path
	native_offset = warning_native_offset


func summary() -> String:
	var location := "%s '%s'" % [String(source_kind).replace("-", " ").capitalize(), source_id]
	if slot >= 0:
		location += " slot %d" % slot
	elif not field.is_empty():
		location += " field %s" % field
	return "%s references unavailable %s '%s'." % [location, String(target_kind).replace("-", " "), target_id]


func to_data() -> Dictionary:
	return {
		"sourceKind": String(source_kind),
		"sourceId": source_id,
		"field": field,
		"slot": slot,
		"targetKind": String(target_kind),
		"targetId": target_id,
		"reason": reason,
		"nativePath": native_path,
		"nativeOffset": native_offset,
	}
