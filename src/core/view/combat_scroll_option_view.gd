class_name CombatScrollOptionView
extends CombatSpellOptionView

var scroll_slot: int


func _init(slot_index: int, spell: SpellDefinition, power_level: int, target: CombatSpellTargetView = null, automatic_target_label: String = "", targeting_mode: StringName = &"combatant", shape: int = 0, default_coordinate: Vector2i = Vector2i(-100_000, -100_000), offsets: Array[Vector2i] = [], maximum_target_count: int = 1, candidates: Array[CombatSpellTargetView] = [], legal_coordinates: Array[Vector2i] = [], rotation_offsets: Array = []) -> void:
	super(spell, power_level, target, automatic_target_label, targeting_mode, shape, default_coordinate, offsets, maximum_target_count, candidates, legal_coordinates, rotation_offsets)
	scroll_slot = slot_index
