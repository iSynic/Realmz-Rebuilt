class_name SpellScrollView
extends RefCounted

var slot_index: int
var spell_id: String
var spell_name: String
var power: int
var use: ActionAvailabilityView = ActionAvailabilityView.new(&"cast_spell", false, "This scroll slot is empty.")
var discard: ActionAvailabilityView = ActionAvailabilityView.new(&"cast_spell", false, "This scroll does not need to be discarded.")


func _init(index: int, scroll: SpellScrollState, spell: SpellDefinition = null) -> void:
	slot_index = index
	spell_id = scroll.spell_id if scroll != null else ""
	spell_name = spell.name if spell != null else "Empty"
	power = scroll.power if scroll != null else 0
