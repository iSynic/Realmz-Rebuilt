class_name ProjectileAttackProfile
extends RefCounted

var available: bool = false
var error_code: StringName = &"projectile_unavailable"
var error_message: String = "No source-backed projectile is available."
var item: ItemDefinition
var item_instance_id: String = ""
var spell: SpellDefinition
var power_level: int = 0
var maximum_range: int = 0


static func permitted(projectile_item: ItemDefinition, instance_id: String, projectile_spell: SpellDefinition, power: int, range_value: int) -> ProjectileAttackProfile:
	var result := ProjectileAttackProfile.new()
	result.available = true
	result.error_code = &""
	result.error_message = ""
	result.item = projectile_item
	result.item_instance_id = instance_id
	result.spell = projectile_spell
	result.power_level = power
	result.maximum_range = range_value
	return result


static func blocked(code: StringName, message: String) -> ProjectileAttackProfile:
	var result := ProjectileAttackProfile.new()
	result.error_code = code
	result.error_message = message
	return result
