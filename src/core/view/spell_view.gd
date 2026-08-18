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
var field_cast: ActionAvailabilityView = ActionAvailabilityView.new(&"cast_spell", false, "Field casting is unavailable.")
var power_levels: Array[int] = []
var make_scroll: ActionAvailabilityView = ActionAvailabilityView.new(&"cast_spell", false, "Scroll scribing is unavailable.")
var scroll_power_levels: Array[int] = []


func _init(definition: SpellDefinition) -> void:
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
