class_name MonsterPolymorphContext
extends RefCounted

var content: RealmzContent
var monster_set: int
var difficulty: int
var realmz_day: int


func _init(source_content: RealmzContent, active_monster_set: int, active_difficulty: int, active_realmz_day: int) -> void:
	content = source_content
	monster_set = active_monster_set
	difficulty = active_difficulty
	realmz_day = active_realmz_day


func definition_for_classic_roll(classic_roll: int) -> MonsterDefinition:
	return content.monster_by_classic_id_for_set(classic_roll, monster_set) if content != null and classic_roll >= 1 and classic_roll <= 200 else null


func has_eligible_definition(size: int) -> bool:
	for classic_roll: int in range(1, 201):
		var definition := definition_for_classic_roll(classic_roll)
		if definition != null and definition.size == size and definition.hit_dice > 0 and definition.can_summon == 1:
			return true
	return false
