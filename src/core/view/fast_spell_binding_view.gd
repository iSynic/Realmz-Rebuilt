class_name FastSpellBindingView
extends RefCounted

var slot_index: int
var shortcut_label: String
var spell_id: String
var spell_name: String
var power: int
var cost: int
var activation: ActionAvailabilityView


func _init(index: int, binding: FastSpellBindingState, spell: SpellDefinition = null) -> void:
	slot_index = index
	shortcut_label = "0" if index == 9 else str(index + 1)
	spell_id = binding.spell_id if binding != null else ""
	spell_name = spell.name if spell != null else "Undefined Spell"
	power = binding.power if binding != null else 0
	cost = absi(spell.cost * power) if spell != null else 0
	activation = ActionAvailabilityView.new(&"cast_spell", false, "This Fast Spell slot is undefined.")
