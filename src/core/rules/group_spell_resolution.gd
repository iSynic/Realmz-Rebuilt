class_name GroupSpellResolution
extends RefCounted

var cast: bool
var cost: int
var duration: int
var base_damage: int
var target_ids: Array[String] = []
var target_kinds: Array[StringName] = []
var resolutions: Array[SpellResolution] = []


func _init(was_cast: bool, spell_cost: int, effect_duration: int, rolled_damage: int) -> void:
	cast = was_cast
	cost = spell_cost
	duration = effect_duration
	base_damage = rolled_damage


func append_target(target_id: String, target_kind: StringName, resolution: SpellResolution) -> void:
	target_ids.append(target_id)
	target_kinds.append(target_kind)
	resolutions.append(resolution)
