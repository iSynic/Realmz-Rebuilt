class_name BattleInitiativePanelBuilder
extends RefCounted

## Builds the dynamic current-and-upcoming combatant strip for the battle command deck.

const PANEL_SCENE := preload("res://src/ui/interaction_components/battle_initiative_panel.tscn")


static func build(round_number: int, combatants: Array[InteractionRequestValue.Combatant], active_actor_id: String, combatant_icons: Dictionary, selected: Callable, maximum_visible_turns: int) -> PanelContainer:
	var panel := PANEL_SCENE.instantiate() as PanelContainer
	var heading := panel.get_node("%Heading") as Label
	heading.text = "Round %d • Turn order" % round_number
	var turns := panel.get_node("%BattleInitiativeOrder") as HBoxContainer
	var ordered := _ordered_from_active(combatants, active_actor_id)
	for index: int in mini(ordered.size(), maximum_visible_turns):
		var combatant := ordered[index]
		var button := Button.new()
		button.name = "Initiative%s" % combatant.id.to_pascal_case()
		var turn_label := "NOW" if index == 0 else "NEXT" if index == 1 else str(index + 1)
		var icon := combatant_icons.get(combatant.id) as Texture2D
		button.text = turn_label if icon != null else "%s %s" % [turn_label, combatant.name.left(8)]
		button.icon = icon
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 22)
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.tooltip_text = "%s • %s" % ["Current actor" if index == 0 else "Upcoming actor %d" % index, combatant.name]
		button.theme_type_variation = &"BattleCommandButton"
		button.custom_minimum_size.y = 28.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if index == 0:
			button.add_theme_color_override("font_color", Color("f8dc52"))
		button.pressed.connect(selected.bind(combatant.id))
		turns.add_child(button)
	return panel


static func _ordered_from_active(combatants: Array[InteractionRequestValue.Combatant], active_actor_id: String) -> Array[InteractionRequestValue.Combatant]:
	var result: Array[InteractionRequestValue.Combatant] = []
	if combatants.is_empty():
		return result
	var active_index := 0
	for index: int in combatants.size():
		if combatants[index].id == active_actor_id:
			active_index = index
			break
	for offset: int in combatants.size():
		result.append(combatants[(active_index + offset) % combatants.size()])
	return result
