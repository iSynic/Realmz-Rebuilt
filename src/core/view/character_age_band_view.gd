class_name CharacterAgeBandView
extends RefCounted

var group: int
var name: String
var minimum_age: int
var maximum_age: int
var active: bool
var changes: Array[CharacterMetricView] = []


func _init(group_index: int, display_name: String, age_range: Vector2i, is_active: bool, authored_changes: PackedInt32Array, change_names: Array[String]) -> void:
	group = group_index
	name = display_name
	minimum_age = age_range.x
	maximum_age = age_range.y
	active = is_active
	for index: int in mini(authored_changes.size(), change_names.size()):
		changes.append(CharacterMetricView.new(StringName("age-change-%d" % index), index, change_names[index], authored_changes[index]))
