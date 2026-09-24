## Binds the shared targeting card to request-owned action and selection facts.

class_name BattleTargetingControls
extends VBoxContainer

signal confirm_requested
signal rotate_requested
signal cancel_requested

var _combatants: Array[InteractionRequestValue.Combatant] = []
var _prompt := "Click a target on the battlefield."


func configure(request: CombatTargetingRequest, body: CombatRequestBody, weapon_ability: bool = false) -> void:
	_combatants = body.combatants
	var action := request.response_body.action
	var action_label := "Cast Spell"
	if action == &"attack": action_label = "Fire Weapon" if body.weapon_mode == &"missile" else "Attack"
	elif action != &"cast_spell": action_label = "Use Scroll" if action == &"use_scroll" else "Use Item"
	if weapon_ability: action_label = "Use Weapon"
	var title := action_label
	var facts := _combatant_name(body.actor_id)
	if action == &"attack":
		facts += " • %d attack units remaining" % body.attack_units_remaining
		for combatant: InteractionRequestValue.Combatant in _combatants:
			if combatant.id == body.actor_id:
				title += " • %s" % combatant.weapon if not combatant.weapon.is_empty() else ""
				if combatant.has_weapon_charges and combatant.weapon_charges >= 0: facts += " • %d charges" % combatant.weapon_charges
	else:
		var options := body.spell_casts if action == &"cast_spell" else body.item_casts if action == &"use_item" else body.scroll_casts
		for option: InteractionRequestValue.CastOption in options:
			if _matches_option(action, option, request.response_body):
				title = "%s • %s" % [option.item_name, option.spell_name] if action == &"use_item" and option.item_name != option.spell_name else option.spell_name
				facts += " • Power %d" % option.power
				if action == &"cast_spell": facts += " • Cost %d SP" % option.cost
				elif action == &"use_item" and option.charges >= 0: facts += " • %d charges" % option.charges
				break
	(%TargetingTitle as Label).text = title
	(%TargetingFacts as Label).text = facts
	var confirm := %ConfirmBattleTarget as Button
	confirm.text = action_label
	confirm.pressed.connect(func() -> void: confirm_requested.emit())
	var rotate := %RotateBattleTarget as Button
	rotate.visible = request.supports_rotation()
	rotate.pressed.connect(func() -> void: rotate_requested.emit())
	(%CancelBattleTarget as Button).pressed.connect(func() -> void: cancel_requested.emit())
	if request.mode in [&"sequence", &"coordinate_sequence"]:
		_prompt = "Choose up to %d %s on the battlefield." % [request.maximum_targets, "spaces" if request.mode == &"coordinate_sequence" else "targets"]
	elif request.mode == &"area":
		_prompt = "Click an area center on the battlefield."
	(%TargetingStatus as Label).text = _prompt


func set_compact(compact: bool) -> void:
	(%TargetingHeader as BoxContainer).vertical = compact


func update_selection(selection: CombatTargetingState) -> void:
	var names: PackedStringArray = []
	for id: String in selection.selected_ids:
		var name := _combatant_name(id)
		for combatant: InteractionRequestValue.Combatant in _combatants:
			if combatant.id == id and combatant.has_position_facts and combatant.range >= 0:
				name += " · Range %d" % combatant.range
		names.append(name)
	var status := selection.status_text
	if status == "Choose a target on the battlefield.": status = _prompt
	(%TargetingStatus as Label).text = "%s • %s" % [", ".join(names), status] if not names.is_empty() else status
	(%TargetingStatus as Label).tooltip_text = status
	(%ConfirmBattleTarget as Button).disabled = not selection.can_confirm()


func show_unavailable(reason: String) -> void:
	_prompt = reason
	(%TargetingStatus as Label).text = reason


func _matches_option(action: StringName, option: InteractionRequestValue.CastOption, response: InteractionResponse.CombatBody) -> bool:
	match action:
		&"cast_spell": return option.spell_id == response.spell_id and option.power == response.power
		&"use_item": return option.item_instance_id == response.item_instance_id
		&"use_scroll": return option.scroll_slot == response.scroll_slot
	return false


func _combatant_name(id: String) -> String:
	for combatant: InteractionRequestValue.Combatant in _combatants:
		if combatant.id == id: return combatant.name
	return id
