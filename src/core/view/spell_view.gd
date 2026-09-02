class_name SpellView
extends RefCounted

var id: String
var classic_id: int
var name: String
var cost: int
var description: String
var spell_class: int
var range_min: int
var range_max: int
var duration_min: int
var duration_max: int
var damage_min: int
var damage_max: int
var power_damage_min: int
var power_damage_max: int
var power_duration_min: int
var power_duration_max: int
var target_type: int
var fixed_target_count: int
var target_size: int
var can_rotate: bool
var damage_type: int
var save_bonus: int
var save_adjust: int
var resistance_adjust: int
var cannot: int
var castable_in_combat: bool
var castable_in_camp: bool
var icon_id: int
var icon_resource_type: String = "cicn"
var animation_resource_type: String = "cicn"
var animation_resource_ids: Array[int] = []
var combat_cast: ActionAvailabilityView = ActionAvailabilityView.new(&"cast_spell", false, "Combat casting requires an active battle.")
var field_cast: ActionAvailabilityView = ActionAvailabilityView.new(&"cast_spell", false, "Field casting is unavailable.")
var power_levels: Array[int] = []
var structural_power_levels: Array[int] = []
var make_scroll: ActionAvailabilityView = ActionAvailabilityView.new(&"cast_spell", false, "Scroll scribing is unavailable.")
var scroll_power_levels: Array[int] = []
var structural_scroll_power_levels: Array[int] = []


func _init(definition: SpellDefinition, reusable: SpellView = null) -> void:
	if reusable != null:
		id = reusable.id; classic_id = reusable.classic_id; name = reusable.name; cost = reusable.cost; description = reusable.description; spell_class = reusable.spell_class
		range_min = reusable.range_min; range_max = reusable.range_max; duration_min = reusable.duration_min; duration_max = reusable.duration_max
		damage_min = reusable.damage_min; damage_max = reusable.damage_max; power_damage_min = reusable.power_damage_min; power_damage_max = reusable.power_damage_max
		power_duration_min = reusable.power_duration_min; power_duration_max = reusable.power_duration_max; target_type = reusable.target_type; fixed_target_count = reusable.fixed_target_count
		target_size = reusable.target_size; can_rotate = reusable.can_rotate; damage_type = reusable.damage_type; save_bonus = reusable.save_bonus; save_adjust = reusable.save_adjust
		resistance_adjust = reusable.resistance_adjust; cannot = reusable.cannot; castable_in_combat = reusable.castable_in_combat; castable_in_camp = reusable.castable_in_camp
		icon_id = reusable.icon_id; icon_resource_type = reusable.icon_resource_type; animation_resource_type = reusable.animation_resource_type; animation_resource_ids = reusable.animation_resource_ids
		combat_cast = reusable.combat_cast; field_cast = reusable.field_cast; make_scroll = reusable.make_scroll
		power_levels = reusable.power_levels.duplicate()
		structural_power_levels = reusable.structural_power_levels.duplicate()
		scroll_power_levels = reusable.scroll_power_levels.duplicate()
		structural_scroll_power_levels = reusable.structural_scroll_power_levels.duplicate()
		return
	id = definition.id
	classic_id = definition.classic_id
	name = definition.name
	cost = definition.cost
	description = definition.description
	spell_class = definition.spell_class
	range_min = definition.range_min
	range_max = definition.range_max
	duration_min = definition.duration_min
	duration_max = definition.duration_max
	damage_min = definition.damage_min
	damage_max = definition.damage_max
	power_damage_min = definition.power_damage_min
	power_damage_max = definition.power_damage_max
	power_duration_min = definition.power_duration_min
	power_duration_max = definition.power_duration_max
	target_type = definition.target_type
	fixed_target_count = definition.fixed_target_count
	target_size = definition.size
	can_rotate = definition.can_rotate
	damage_type = definition.damage_type
	save_bonus = definition.save_bonus
	save_adjust = definition.save_adjust
	resistance_adjust = definition.resistance_adjust
	cannot = definition.cannot
	castable_in_combat = definition.in_combat
	castable_in_camp = definition.in_camp
	icon_id = definition.queue_icon
	var first_animation_resource_id := 12_032 if definition.look_end == 0 else 11_992 + definition.look_end * 8
	for frame_offset: int in 8:
		animation_resource_ids.append(first_animation_resource_id + frame_offset)
