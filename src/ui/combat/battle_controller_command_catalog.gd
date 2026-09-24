## Projects the existing battle controls into controller radial entries.

extends RefCounted

const SYMBOLS := {
	&"attack": "⚔", &"fire_weapon": "➶", &"use_weapon": "✦", &"guard": "◇",
	&"spells": "✧", &"scrolls": "▤", &"items": "▣", &"finish": "✓",
	&"move_to": "✥", &"auto_turn": "↻", &"delay": "◷", &"bandage": "+",
	&"turn_undead": "☼", &"undo": "↶", &"escape": "↗",
}

static func entries(command_buttons: Array[Button], fast_spells: Array[InteractionRequestValue.FastSpell]) -> Array[ControllerRadialEntry]:
	var result: Array[ControllerRadialEntry] = []
	var ordered := command_buttons.filter(func(button: Button) -> bool: return is_instance_valid(button) and not String(button.name).begins_with("CombatPresentation"))
	ordered.append_array(command_buttons.filter(func(button: Button) -> bool: return is_instance_valid(button) and String(button.name).begins_with("CombatPresentation")))
	for button: Button in ordered:
		if not is_instance_valid(button):
			continue
		var action_id := StringName(button.name.trim_prefix("CombatCommand").trim_prefix("CombatPresentation").to_snake_case())
		result.append(ControllerRadialEntry.new(action_id, button.text, not button.disabled, button.tooltip_text, button.icon, String(SYMBOLS.get(action_id, "◇"))))
	for slot_index: int in fast_spells.size():
		var spell: InteractionRequestValue.FastSpell = fast_spells[slot_index]
		var reason: String = spell.reason if not spell.enabled else ""
		result.append(ControllerRadialEntry.new(StringName("fast_spell_%d" % slot_index), "Fast: %s" % spell.spell_name, spell.enabled, reason, null, "✧"))
	return result
