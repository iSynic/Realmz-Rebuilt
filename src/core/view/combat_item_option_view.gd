class_name CombatItemOptionView
extends RefCounted

var item_instance_id: String
var item_definition_id: String
var item_name: String
var charges: int
var spell_id: String
var spell_name: String
var power: int
var target_id: String
var target_name: String
var target_current_health: int
var target_maximum_health: int
var target_mode: StringName
var area_shape: int
var default_target_coordinate: Vector2i
var area_offsets: Array[Vector2i] = []
var area_rotation_offsets: Array = []
var legal_target_coordinates: Array[Vector2i] = []
var maximum_targets: int = 1
var target_candidates: Array[CombatSpellTargetView] = []
var power_staged: bool = false


func _init(instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition, power_level: int, target: CombatSpellTargetView = null, automatic_target_label: String = "", targeting_mode: StringName = &"combatant", shape: int = 0, default_coordinate: Vector2i = Vector2i(-100_000, -100_000), offsets: Array[Vector2i] = [], legal_coordinates: Array[Vector2i] = [], rotation_offsets: Array = [], maximum_target_count: int = 1, candidates: Array[CombatSpellTargetView] = [], staged: bool = false) -> void:
	item_instance_id = instance.id
	item_definition_id = item.id
	item_name = item.name if instance.identified else item.unidentified_name
	charges = instance.charges
	spell_id = spell.id if spell != null else ""
	spell_name = spell.name if spell != null else "Scenario action"
	power = power_level
	target_id = target.id if target != null else ""
	target_name = target.name if target != null else automatic_target_label
	target_current_health = target.current_health if target != null else -1
	target_maximum_health = target.maximum_health if target != null else -1
	target_mode = targeting_mode
	area_shape = shape
	default_target_coordinate = default_coordinate
	area_offsets = offsets.duplicate()
	legal_target_coordinates = legal_coordinates.duplicate()
	for rotation: Variant in rotation_offsets:
		if rotation is Array:
			area_rotation_offsets.append((rotation as Array).duplicate())
	maximum_targets = maximum_target_count
	target_candidates = candidates.duplicate()
	power_staged = staged
