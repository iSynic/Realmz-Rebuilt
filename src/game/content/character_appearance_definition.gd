class_name CharacterAppearanceDefinition
extends RefCounted

const PORTRAIT: StringName = &"portrait"
const COMBAT_ICON: StringName = &"combat-icon"

var id: String
var label: String
var kind: StringName
var classic_resource_id: int
var recommended_race_ids: Array[String] = []


func _init(definition_id: String, display_label: String, appearance_kind: StringName, resource_id: int, recommended_races: Array[String] = []) -> void:
	id = definition_id
	label = display_label
	kind = appearance_kind
	classic_resource_id = resource_id
	recommended_race_ids = recommended_races.duplicate()


func is_recommended_for(race_id: String) -> bool:
	return recommended_race_ids.has(race_id)
