class_name SpellTargetSelection
extends RefCounted

var id: String
var kind: StringName
var character: CharacterState
var monster: MonsterState
var monster_definition: MonsterDefinition


static func for_character(target: CharacterState) -> SpellTargetSelection:
	var selection := SpellTargetSelection.new()
	selection.id = target.id
	selection.kind = &"character"
	selection.character = target
	return selection


static func for_monster(target: MonsterState, definition: MonsterDefinition) -> SpellTargetSelection:
	var selection := SpellTargetSelection.new()
	selection.id = target.id
	selection.kind = &"monster"
	selection.monster = target
	selection.monster_definition = definition
	return selection
