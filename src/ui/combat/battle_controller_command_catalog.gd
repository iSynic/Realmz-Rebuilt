## Projects the existing battle controls into controller radial entries.

extends RefCounted


static func entries(command_buttons: Array[Button], fast_spells: Array[InteractionRequestValue.FastSpell]) -> Array[ControllerRadialEntry]:
	var result: Array[ControllerRadialEntry] = []
	for button: Button in command_buttons:
		if not is_instance_valid(button):
			continue
		var action_id := StringName(button.name.trim_prefix("CombatCommand").to_snake_case())
		result.append(ControllerRadialEntry.new(action_id, button.text, not button.disabled, button.tooltip_text))
	for slot_index: int in fast_spells.size():
		var spell: InteractionRequestValue.FastSpell = fast_spells[slot_index]
		var reason: String = spell.reason if not spell.enabled else ""
		result.append(ControllerRadialEntry.new(StringName("fast_spell_%d" % slot_index), "Fast: %s" % spell.spell_name, spell.enabled, reason))
	return result
