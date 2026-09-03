class_name GroupSpellResolution
extends RefCounted

var cast: bool
var cost: int
var duration: int
var base_damage: int
var target_ids: Array[String] = []
var selected_target_ids: Array[String] = []
var target_kinds: Array[StringName] = []
var reflected_targets: Array[bool] = []
var resolutions: Array[SpellResolution] = []


func _init(was_cast: bool, spell_cost: int, effect_duration: int, rolled_damage: int) -> void:
	cast = was_cast
	cost = spell_cost
	duration = effect_duration
	base_damage = rolled_damage


func append_target(target_id: String, target_kind: StringName, resolution: SpellResolution, selected_target_id: String = "", reflected: bool = false) -> void:
	target_ids.append(target_id)
	selected_target_ids.append(target_id if selected_target_id.is_empty() else selected_target_id)
	target_kinds.append(target_kind)
	reflected_targets.append(reflected)
	resolutions.append(resolution)
