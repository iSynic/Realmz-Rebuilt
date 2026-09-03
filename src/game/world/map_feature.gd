class_name MapFeature
extends RefCounted

var id: String
var kind: StringName
var initial_state: StringName
var orientation: StringName


func _init(feature_id: String, feature_kind: StringName, state: StringName = &"", feature_orientation: StringName = &"") -> void:
	id = feature_id
	kind = feature_kind
	initial_state = state
	orientation = feature_orientation
