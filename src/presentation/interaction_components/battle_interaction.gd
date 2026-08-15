class_name BattleInteraction
extends InteractionComponent

var _actor_id: String = ""
var _combatants: Array[InteractionRequestValue.Combatant] = []
var _inspected_index: int = -1
var _inspected_label: Label
var _mode_panels: Array[Control] = []
var _targeting_status_label: Label
var _targeting_confirm_button: Button
var _targeting_controls: VBoxContainer
var _targeting_active: bool = false
var _spell_casts: Array[InteractionRequestValue.CastOption] = []
var _fast_spells: Array[InteractionRequestValue.FastSpell] = []
var _spell_panel: VBoxContainer


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.CombatRequestBody
	if body == null: return
	var actor_id := body.actor_id
	_actor_id = actor_id
	_mode_panels.clear()
	_targeting_status_label = null
	_targeting_confirm_button = null
	_targeting_controls = null
	_targeting_active = false
	_read_combatants(body.combatants)
	var action_ids: Array[String] = body.actions
	var weapon_mode := String(body.weapon_mode)
	var targets := body.targets
	var target_panel := VBoxContainer.new()
	var spell_panel := VBoxContainer.new()
	_spell_panel = spell_panel
	var scroll_panel := VBoxContainer.new()
	var item_panel := VBoxContainer.new()
	var bandage_panel := VBoxContainer.new()
	var mode_panels: Array[Control] = [target_panel, spell_panel, scroll_panel, item_panel, bandage_panel]
	_mode_panels.assign(mode_panels)
	var overview := VBoxContainer.new()
	overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_theme_constant_override("separation", 8)
	add_child(overview)
	_build_combatant_information(body, targets, overview)
	_add_primary_action_row(body, actor_id, action_ids, targets, target_panel, spell_panel, scroll_panel, item_panel, bandage_panel, mode_panels, overview)
	for panel: Control in mode_panels:
		panel.visible = false
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_constant_override("separation", 6)
		add_child(panel)
		_add_mode_back_button(panel, overview, mode_panels)
	if action_ids.has("attack"):
		var candidate_ids: Array[String] = []
		for target: InteractionRequestValue.CombatTarget in targets:
			if not target.id.is_empty(): candidate_ids.append(target.id)
		_add_targeting_button(target_panel, "Choose Fire target on battlefield" if weapon_mode == "missile" else "Choose attack target on battlefield", {
			"mode": "combatant",
			"responsePayload": {"actorId": actor_id, "action": "attack", "targetId": ""},
			"candidateIds": candidate_ids,
		})
	elif weapon_mode == "melee" and not body.melee_attack_reason.is_empty():
		_add_hint_to(target_panel, body.melee_attack_reason)
	if weapon_mode == "missile" and not action_ids.has("attack"):
		add_response_to(target_panel, "Fire unavailable", {}, false, body.ranged_attack.reason)
	_spell_casts = body.spell_casts
	_fast_spells = body.fast_spells
	if action_ids.has("cast_spell") and not body.spell_casts.is_empty():
		var spell_picker := OptionButton.new()
		spell_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for option: InteractionRequestValue.CastOption in body.spell_casts:
			var label := "%s • P%d • %d SP → %s" % [option.spell_name, option.power, option.cost, option.target_name]
			if option.target_current_health >= 0: label += " (%d/%d HP)" % [option.target_current_health, option.target_maximum_health]
			spell_picker.add_item(label)
			spell_picker.set_item_metadata(spell_picker.item_count - 1, option)
		spell_panel.add_child(spell_picker)
		var cast_button := Button.new()
		cast_button.name = "ChooseSpellTarget"
		cast_button.disabled = spell_picker.item_count == 0
		var refresh_cast_button := func(_index: int) -> void:
			if _targeting_active:
				presentation_action_requested.emit(&"cancel_battlefield_targeting", {})
			var selected := spell_picker.get_selected_metadata() as InteractionRequestValue.CastOption
			var mode := String(selected.target_mode) if selected != null else "combatant"
			cast_button.text = "Cast selected spell" if mode == "automatic" else "Choose spell target on battlefield"
		spell_picker.item_selected.connect(refresh_cast_button)
		cast_button.pressed.connect(func() -> void:
			var option := spell_picker.get_selected_metadata() as InteractionRequestValue.CastOption
			if option == null: return
			var payload := {"actorId": actor_id, "action": "cast_spell", "targetId": "", "spellId": option.spell_id, "power": option.power}
			var mode := String(option.target_mode)
			if mode == "automatic":
				payload_submitted.emit(payload)
				return
			var configuration := _spell_targeting_configuration(body.spell_casts, option, payload)
			_start_targeting(configuration, spell_panel)
		)
		spell_panel.add_child(cast_button)
		refresh_cast_button.call(spell_picker.selected)
	elif not body.spell_cast_reason.is_empty():
		add_response_to(spell_panel, "Cast unavailable", {}, false, body.spell_cast_reason)
	if action_ids.has("use_scroll") and not body.scroll_casts.is_empty():
		var scroll_picker := OptionButton.new()
		scroll_picker.name = "CombatScrollPicker"
		scroll_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for option: InteractionRequestValue.CastOption in body.scroll_casts:
			var label := "Slot %d • %s • P%d → %s" % [option.scroll_slot + 1, option.spell_name, option.power, option.target_name]
			if option.target_current_health >= 0: label += " (%d/%d HP)" % [option.target_current_health, option.target_maximum_health]
			scroll_picker.add_item(label)
			scroll_picker.set_item_metadata(scroll_picker.item_count - 1, option)
		scroll_panel.add_child(scroll_picker)
		var use_scroll_button := Button.new()
		use_scroll_button.name = "ChooseScrollTarget"
		use_scroll_button.disabled = scroll_picker.item_count == 0
		var refresh_scroll_button := func(_index: int) -> void:
			if _targeting_active:
				presentation_action_requested.emit(&"cancel_battlefield_targeting", {})
			var selected := scroll_picker.get_selected_metadata() as InteractionRequestValue.CastOption
			var mode := String(selected.target_mode) if selected != null else "combatant"
			use_scroll_button.text = "Use selected scroll" if mode == "automatic" else "Choose scroll target on battlefield"
		scroll_picker.item_selected.connect(refresh_scroll_button)
		use_scroll_button.pressed.connect(func() -> void:
			var option := scroll_picker.get_selected_metadata() as InteractionRequestValue.CastOption
			if option == null: return
			var payload := {"actorId": actor_id, "action": "use_scroll", "targetId": "", "scrollSlot": option.scroll_slot}
			var mode := String(option.target_mode)
			if mode == "automatic":
				payload_submitted.emit(payload)
				return
			var configuration := _spell_targeting_configuration(body.scroll_casts, option, payload)
			_start_targeting(configuration, scroll_panel)
		)
		scroll_panel.add_child(use_scroll_button)
		refresh_scroll_button.call(scroll_picker.selected)
	elif not body.scroll_cast_reason.is_empty():
		add_response_to(scroll_panel, "Use scroll unavailable", {}, false, body.scroll_cast_reason)
	if action_ids.has("use_item") and not body.item_casts.is_empty():
		var item_row := HBoxContainer.new()
		item_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_panel.add_child(item_row)
		var item_picker := OptionButton.new()
		item_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for option: InteractionRequestValue.CastOption in body.item_casts:
			var charge_label := "∞" if option.charges < 0 else str(option.charges)
			var label := "%s (%s) • %s P%d → %s" % [option.item_name, charge_label, option.spell_name, option.power, option.target_name]
			if option.target_current_health >= 0: label += " (%d/%d HP)" % [option.target_current_health, option.target_maximum_health]
			item_picker.add_item(label)
			item_picker.set_item_metadata(item_picker.item_count - 1, option)
		item_row.add_child(item_picker)
		var use_button := Button.new()
		use_button.text = "Use selected item"
		use_button.disabled = item_picker.item_count == 0
		use_button.pressed.connect(func() -> void:
			var option := item_picker.get_selected_metadata() as InteractionRequestValue.CastOption
			if option == null: return
			var payload := {"actorId": actor_id, "action": "use_item", "targetId": "", "itemInstanceId": option.item_instance_id}
			if option.target_mode == &"automatic":
				payload_submitted.emit(payload)
				return
			var candidate_ids: Array[String] = []
			for candidate: InteractionRequestValue.CastOption in body.item_casts:
				if candidate.item_instance_id == option.item_instance_id and not candidate.target_id.is_empty(): candidate_ids.append(candidate.target_id)
			_start_targeting({"mode": "combatant", "responsePayload": payload, "candidateIds": candidate_ids}, item_panel)
		)
		item_row.add_child(use_button)
	elif not body.item_cast_reason.is_empty():
		add_response_to(item_panel, "Use item unavailable", {}, false, body.item_cast_reason)


func handle_fast_spell(slot_index: int, use_spell: bool) -> bool:
	if slot_index < 0 or slot_index >= _fast_spells.size():
		return false
	var binding := _fast_spells[slot_index]
	var shortcut := "0" if slot_index == 9 else str(slot_index + 1)
	if binding.spell_id.is_empty():
		presentation_action_requested.emit(&"fast_spell_status", {"text": "Fast Spell %s • Undefined Spell" % shortcut})
		presentation_action_requested.emit(&"play_sound", {"soundId": 143})
		return true
	var summary := "Fast Spell %s • %s P%d" % [shortcut, binding.spell_name, binding.power]
	if not use_spell:
		presentation_action_requested.emit(&"fast_spell_status", {"text": summary})
		presentation_action_requested.emit(&"play_sound", {"soundId": 145})
		return true
	if not binding.enabled:
		presentation_action_requested.emit(&"fast_spell_status", {"text": "%s • %s" % [summary, binding.reason], "error": true})
		presentation_action_requested.emit(&"play_sound", {"soundId": 143})
		return true
	for candidate: InteractionRequestValue.CastOption in _spell_casts:
		if candidate.spell_id == binding.spell_id and candidate.power == binding.power:
			var payload := {"actorId": _actor_id, "action": "cast_spell", "targetId": "", "spellId": binding.spell_id, "power": binding.power}
			if candidate.target_mode == &"automatic":
				payload_submitted.emit(payload)
				return true
			_start_targeting(_spell_targeting_configuration(_spell_casts, candidate, payload), _spell_panel)
			return true
	presentation_action_requested.emit(&"fast_spell_status", {"text": "%s • No legal target is available." % summary, "error": true})
	presentation_action_requested.emit(&"play_sound", {"soundId": 143})
	return true


func update_battlefield_targeting(selection: Dictionary) -> void:
	if not _targeting_active or _targeting_status_label == null or _targeting_confirm_button == null:
		return
	_targeting_status_label.text = String(selection.get("status", "Choose a target on the battlefield."))
	_targeting_confirm_button.disabled = not bool(selection.get("canConfirm", false))


func battlefield_targeting_cancelled() -> void:
	_targeting_active = false
	if _targeting_status_label != null:
		_targeting_status_label.text = "Targeting cancelled. Choose an action to try again."
	if _targeting_confirm_button != null:
		_targeting_confirm_button.disabled = true


func _spell_targeting_configuration(spell_casts: Array[InteractionRequestValue.CastOption], selected: InteractionRequestValue.CastOption, response_payload: Dictionary) -> Dictionary:
	var mode := String(selected.target_mode)
	var candidate_ids: Array[String] = []
	if mode == "sequence":
		for candidate: InteractionRequestValue.CombatTarget in selected.target_candidates:
			if not candidate.id.is_empty(): candidate_ids.append(candidate.id)
	elif mode == "combatant":
		for candidate: InteractionRequestValue.CastOption in spell_casts:
			if candidate.spell_id == selected.spell_id and candidate.power == selected.power and candidate.scroll_slot == selected.scroll_slot and candidate.target_mode == &"combatant" and not candidate.target_id.is_empty(): candidate_ids.append(candidate.target_id)
	return {
		"mode": mode,
		"responsePayload": response_payload,
		"candidateIds": candidate_ids,
		"maximumTargets": selected.maximum_targets,
		"areaOffsets": selected.area_offsets.map(func(value: Vector2i) -> Array[int]: return [value.x, value.y]),
		"defaultTargetCoordinate": [selected.default_target_coordinate.x, selected.default_target_coordinate.y],
		"legalTargetCoordinates": selected.legal_target_coordinates.map(func(value: Vector2i) -> Array[int]: return [value.x, value.y]),
	}


func _add_targeting_button(parent: Container, text: String, configuration: Dictionary) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: _start_targeting(configuration, parent))
	parent.add_child(button)


func _start_targeting(configuration: Dictionary, parent: Container) -> void:
	_targeting_active = true
	if _targeting_controls != null and is_instance_valid(_targeting_controls):
		_targeting_controls.queue_free()
	_targeting_controls = VBoxContainer.new()
	_targeting_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_targeting_controls)
	_targeting_status_label = _add_hint_to(_targeting_controls, "Choose a target on the battlefield.")
	var target_actions := HBoxContainer.new()
	target_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_targeting_confirm_button = Button.new()
	_targeting_confirm_button.text = "Confirm target"
	_targeting_confirm_button.disabled = true
	_targeting_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_targeting_confirm_button.pressed.connect(func() -> void: presentation_action_requested.emit(&"confirm_battlefield_targeting", {}))
	target_actions.add_child(_targeting_confirm_button)
	var cancel := Button.new()
	cancel.text = "Cancel targeting"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void: presentation_action_requested.emit(&"cancel_battlefield_targeting", {}))
	target_actions.add_child(cancel)
	_targeting_controls.add_child(target_actions)
	presentation_action_requested.emit(&"begin_battlefield_targeting", configuration.duplicate(true))


func inspect_combatant(combatant_id: String) -> void:
	for index: int in _combatants.size():
		if _combatants[index].id == combatant_id:
			_inspected_index = index
			_refresh_inspected_label()
			return


func _read_combatants(value: Array[InteractionRequestValue.Combatant]) -> void:
	_combatants.clear()
	for combatant: InteractionRequestValue.Combatant in value:
		if not combatant.id.is_empty(): _combatants.append(combatant)


func _build_combatant_information(body: InteractionRequest.CombatRequestBody, targets: Array[InteractionRequestValue.CombatTarget], parent: Container) -> void:
	var information := HBoxContainer.new()
	information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.add_theme_constant_override("separation", 16)
	var active_label := Label.new()
	active_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	active_label.text = "Active • %s\n%d attack%s • %d movement • %s\nEnemies left • %d" % [_combatant_name(_actor_id), body.attack_units_remaining, "" if body.attack_units_remaining == 1 else "s", body.movement_remaining, String(body.weapon_mode).capitalize(), body.enemies_remaining]
	information.add_child(active_label)
	_inspected_label = Label.new()
	_inspected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	information.add_child(_inspected_label)
	parent.add_child(information)
	var default_id := _actor_id
	if not targets.is_empty(): default_id = targets[0].id
	inspect_combatant(default_id)
	if _inspected_index < 0 and not _combatants.is_empty():
		_inspected_index = 0
	_refresh_inspected_label()
	var navigation := HFlowContainer.new()
	navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(navigation)
	_add_presentation_button(navigation, "Previous", &"inspect_previous")
	_add_presentation_button(navigation, "Center Active", &"center_active")
	_add_presentation_button(navigation, "Next", &"inspect_next")
	_add_presentation_button(navigation, "Reveal Friends", &"reveal_friends")


func _add_presentation_button(parent: Container, text: String, action: StringName) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 30.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: _perform_presentation_action(action))
	parent.add_child(button)


func _perform_presentation_action(action: StringName) -> void:
	if action in [&"inspect_previous", &"inspect_next"] and not _combatants.is_empty():
		var delta := -1 if action == &"inspect_previous" else 1
		_inspected_index = posmod(_inspected_index + delta, _combatants.size())
		_refresh_inspected_label()
		presentation_action_requested.emit(&"focus_combatant", {"combatantId": _combatants[_inspected_index].id, "playSound": true})
		return
	if action == &"center_active":
		inspect_combatant(_actor_id)
		presentation_action_requested.emit(&"focus_combatant", {"combatantId": _actor_id, "playSound": true})
		return
	if action == &"reveal_friends":
		presentation_action_requested.emit(&"toggle_reveal_friends", {})


func _refresh_inspected_label() -> void:
	if _inspected_label == null:
		return
	if _inspected_index < 0 or _inspected_index >= _combatants.size():
		_inspected_label.text = "Shown • No combatant selected"
		return
	var combatant := _combatants[_inspected_index]
	var details: Array[String] = ["HP %d/%d" % [combatant.current_health, combatant.maximum_health]]
	if combatant.maximum_spell_points > 0: details.append("SP %d/%d" % [combatant.spell_points, combatant.maximum_spell_points])
	details.append("AR %d" % combatant.armor)
	details.append("MR %d" % combatant.magic_resistance)
	if combatant.has_hit_dice: details.append("HD %d" % combatant.hit_dice)
	if combatant.has_position_facts: details.append("Range %d%s" % [combatant.range, " • Blocked" if combatant.blocked else ""])
	var secondary: Array[String] = []
	if not combatant.weapon.is_empty(): secondary.append("%s%s" % [combatant.weapon, " (%d)" % combatant.weapon_charges if combatant.has_weapon_charges and combatant.weapon_charges >= 0 else ""])
	secondary.append("Attacks %s" % combatant.attacks)
	secondary.append("Move %d" % combatant.maximum_movement)
	if not combatant.conditions.is_empty(): secondary.append("Conditions: %s" % ", ".join(combatant.conditions))
	var defenses: Array[String] = []
	if not combatant.immunities.is_empty(): defenses.append("Immune: %s" % ", ".join(combatant.immunities))
	if not combatant.vulnerabilities.is_empty(): defenses.append("Vulnerable: %s" % ", ".join(combatant.vulnerabilities))
	var defense_line := "\n%s" % " • ".join(defenses) if not defenses.is_empty() else ""
	_inspected_label.text = "Shown • %s\n%s\n%s%s" % [combatant.name, " • ".join(details), " • ".join(secondary), defense_line]


func _combatant_name(combatant_id: String) -> String:
	for combatant: InteractionRequestValue.Combatant in _combatants:
		if combatant.id == combatant_id: return combatant.name
	return combatant_id


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value:
			result.append(String(entry))
	return result


func accepts_spatial_input() -> bool:
	for panel: Control in _mode_panels:
		if panel.visible:
			return false
	return true


func _add_primary_action_row(body: InteractionRequest.CombatRequestBody, actor_id: String, action_ids: Array[String], targets: Array[InteractionRequestValue.CombatTarget], target_panel: Control, spell_panel: Control, scroll_panel: Control, item_panel: Control, bandage_panel: Control, mode_panels: Array[Control], overview: Control) -> void:
	var action_row := HFlowContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_child(action_row)
	if action_ids.has("switch_weapon"):
		var target_mode := String(body.weapon_switch.target_mode)
		add_response_to(action_row, "Weapon: %s" % target_mode.capitalize(), {"actorId": actor_id, "action": "switch_weapon", "targetId": ""})
	if action_ids.has("defend"):
		add_response_to(action_row, "Guard", {"actorId": actor_id, "action": "defend", "targetId": ""})
	var weapon_mode := String(body.weapon_mode)
	var target_enabled: bool = action_ids.has("attack") and not targets.is_empty()
	var target_reason := body.melee_attack_reason if weapon_mode == "melee" else body.ranged_attack.reason
	_add_panel_toggle(action_row, "Fire" if weapon_mode == "missile" else "Attack", target_panel, mode_panels, overview, target_enabled, target_reason)
	_add_panel_toggle(action_row, "Spells", spell_panel, mode_panels, overview, action_ids.has("cast_spell") and not body.spell_casts.is_empty(), body.spell_cast_reason)
	_add_panel_toggle(action_row, "Scrolls", scroll_panel, mode_panels, overview, action_ids.has("use_scroll") and not body.scroll_casts.is_empty(), body.scroll_cast_reason, 647)
	_add_panel_toggle(action_row, "Items", item_panel, mode_panels, overview, action_ids.has("use_item") and not body.item_casts.is_empty(), body.item_cast_reason)
	if action_ids.has("finish"):
		add_response_to(action_row, "Finish", {"actorId": actor_id, "action": "finish", "targetId": ""})
	var retreat_enabled := action_ids.has("retreat") and body.retreat.enabled
	var retreat_reason := body.retreat.reason
	add_response_to(action_row, "Escape", {"actorId": actor_id, "action": "retreat", "targetId": ""}, retreat_enabled, retreat_reason)
	_add_classic_turn_commands(action_row, body, actor_id, bandage_panel, mode_panels, overview)


func _add_classic_turn_commands(parent: Container, body: InteractionRequest.CombatRequestBody, actor_id: String, bandage_panel: Control, mode_panels: Array[Control], overview: Control) -> void:
	add_response_to(parent, "Auto", {"actorId": actor_id, "action": "auto", "targetId": ""}, body.auto_turn.enabled, body.auto_turn.reason)

	add_response_to(parent, "Delay", {"actorId": actor_id, "action": "delay", "targetId": ""}, body.delay.enabled, body.delay.reason)

	var bandage_enabled := body.bandage.enabled and not body.bandage_targets.is_empty()
	var bandage_reason := body.bandage.reason
	if body.bandage_targets.is_empty() and body.bandage.enabled:
		bandage_reason = "No legal Bandage recipient is available."
	_add_bandage_panel(bandage_panel, actor_id, body.bandage_targets)
	_add_panel_toggle(parent, "Bandage", bandage_panel, mode_panels, overview, bandage_enabled, bandage_reason)

	var turn_label := "Turn Undead"
	if body.turn_undead.enabled: turn_label = "Turn Undead (%d)" % body.turn_undead_targets.size()
	add_response_to(parent, turn_label, {"actorId": actor_id, "action": "turn_undead", "targetId": ""}, body.turn_undead.enabled, body.turn_undead.reason)

	add_response_to(parent, "Undo", {"actorId": actor_id, "action": "undo", "targetId": ""}, body.undo.enabled, body.undo.reason)


func _add_bandage_panel(parent: Control, actor_id: String, targets: Array[InteractionRequestValue.CombatTarget]) -> void:
	_add_hint_to(parent, "Choose one bleeding party member.")
	var picker := OptionButton.new()
	picker.name = "BandageRecipient"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.tooltip_text = "Choose one supplied legal Bandage recipient."
	for target: InteractionRequestValue.CombatTarget in targets:
		if not target.id.is_empty():
			picker.add_item("%s • %d HP" % [target.name, target.current_health])
			picker.set_item_metadata(picker.item_count - 1, target.id)
	picker.disabled = picker.item_count == 0
	parent.add_child(picker)
	var submit := Button.new()
	submit.name = "Bandage"
	submit.text = "Bandage selected character"
	submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	submit.disabled = picker.item_count == 0
	submit.tooltip_text = "Bandage the selected party member."
	submit.pressed.connect(func() -> void:
		var target_id := String(picker.get_selected_metadata())
		if target_id.is_empty():
			return
		payload_submitted.emit({"actorId": actor_id, "action": "bandage", "targetId": target_id})
	)
	parent.add_child(submit)


func _add_panel_toggle(parent: Container, label: String, panel: Control, panels: Array[Control], overview: Control, enabled: bool, reason: String, presentation_sound_id: int = 0) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 36.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not enabled
	button.tooltip_text = reason if not enabled else ""
	button.pressed.connect(func() -> void:
		var should_show := not panel.visible
		for candidate: Control in panels:
			candidate.visible = should_show and candidate == panel
		overview.visible = not should_show
		if should_show and presentation_sound_id > 0:
			presentation_action_requested.emit(&"play_sound", {"soundId": presentation_sound_id})
	)
	parent.add_child(button)
	return button


func _add_mode_back_button(panel: Container, overview: Control, panels: Array[Control]) -> void:
	var back := Button.new()
	back.text = "Back to battle"
	back.custom_minimum_size.y = 30.0
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void:
		if _targeting_active:
			presentation_action_requested.emit(&"cancel_battlefield_targeting", {})
		for candidate: Control in panels:
			candidate.visible = false
		overview.visible = true
	)
	panel.add_child(back)
	panel.move_child(back, 0)


func _add_hint_to(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("d5b45d"))
	parent.add_child(label)
	return label
