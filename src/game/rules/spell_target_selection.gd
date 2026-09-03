class_name SpellTargetSelection
extends RefCounted

var id: String
var original_target_id: String
var kind: StringName
var character: CharacterState
var monster: MonsterState
var monster_definition: MonsterDefinition
var reflected: bool


static func for_character(target: CharacterState, selected_target_id: String = "", was_reflected: bool = false) -> SpellTargetSelection:
	var selection := SpellTargetSelection.new()
	selection.id = target.id
	selection.original_target_id = target.id if selected_target_id.is_empty() else selected_target_id
	selection.kind = &"character"
	selection.character = target
	selection.reflected = was_reflected
	return selection


static func for_monster(target: MonsterState, definition: MonsterDefinition, selected_target_id: String = "", was_reflected: bool = false) -> SpellTargetSelection:
	var selection := SpellTargetSelection.new()
	selection.id = target.id
	selection.original_target_id = target.id if selected_target_id.is_empty() else selected_target_id
	selection.kind = &"monster"
	selection.monster = target
	selection.monster_definition = definition
	selection.reflected = was_reflected
	return selection
