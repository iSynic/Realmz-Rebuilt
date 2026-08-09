class_name CharacterCombatEquipment
extends RefCounted

var valid: bool = true
var error_code: StringName = &""
var error_message: String = ""
var melee_weapon: ItemDefinition
var melee_weapon_instance_id: String = ""
var missile_weapon: ItemDefinition
var missile_weapon_instance_id: String = ""
var missile_ammunition: ItemDefinition
var missile_ammunition_instance_id: String = ""
var equipped_damage_bonus: int = 0
var effective_damage_bonus: int = 0
var effective_luck: int = 0
var effective_armor: int = 0


func reject(code: StringName, message: String) -> void:
	valid = false
	error_code = code
	error_message = message


func is_armed() -> bool:
	return melee_weapon != null


func has_missile_weapon() -> bool:
	return missile_weapon != null
