class_name CharacterAppearanceOptionView
extends RefCounted

var id: String
var label: String
var kind: StringName
var classic_resource_id: int
var recommended_race_ids: Array[String] = []


func _init(definition: CharacterAppearanceDefinition) -> void:
	id = definition.id
	label = definition.label
	kind = definition.kind
	classic_resource_id = definition.classic_resource_id
	recommended_race_ids = definition.recommended_race_ids.duplicate()


func is_recommended_for(race_id: String) -> bool:
	return recommended_race_ids.has(race_id)
