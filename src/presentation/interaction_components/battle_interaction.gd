class_name BattleInteraction
extends InteractionComponent

var _actor_id: String = ""
var _combatants: Array[Dictionary] = []
var _inspected_index: int = -1
var _inspected_label: Label
var _mode_panels: Array[Control] = []
var _targeting_status_label: Label
var _targeting_confirm_button: Button
var _targeting_controls: VBoxContainer
var _targeting_active: bool = false


func build(request: InteractionRequest) -> void:
	var actor_id := String(request.payload.get("actorId", ""))
	_actor_id = actor_id
	_mode_panels.clear()
	_targeting_status_label = null
	_targeting_confirm_button = null
	_targeting_controls = null
	_targeting_active = false
	_read_combatants(request.payload.get("combatants", []))
	var actions: Variant = request.payload.get("actions", [])
	var action_ids: Array = actions if actions is Array else []
	var weapon_mode := String(request.payload.get("weaponMode", "melee"))
	var targets: Variant = request.payload.get("targets", [])
	var target_panel := VBoxContainer.new()
	var spell_panel := VBoxContainer.new()
	var item_panel := VBoxContainer.new()
	var mode_panels: Array[Control] = [target_panel, spell_panel, item_panel]
	_mode_panels.assign(mode_panels)
	var overview := VBoxContainer.new()
	overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_theme_constant_override("separation", 8)
	add_child(overview)
	_build_combatant_information(request, targets, overview)
	_add_primary_action_row(request, actor_id, action_ids, targets, target_panel, spell_panel, item_panel, mode_panels, overview)
	for panel: Control in mode_panels:
		panel.visible = false
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_constant_override("separation", 6)
		add_child(panel)
		_add_mode_back_button(panel, overview, mode_panels)
	if action_ids.has("attack") and targets is Array:
		var candidate_ids: Array[String] = []
		for target: Variant in targets:
			if target is Dictionary and not String(target.get("id", "")).is_empty():
				candidate_ids.append(String(target.get("id")))
		_add_targeting_button(target_panel, "Choose Fire target on battlefield" if weapon_mode == "missile" else "Choose attack target on battlefield", {
			"mode": "combatant",
			"responsePayload": {"actorId": actor_id, "action": "attack", "targetId": ""},
			"candidateIds": candidate_ids,
		})
	elif weapon_mode == "melee" and not String(request.payload.get("meleeAttackReason", "")).is_empty():
		_add_hint_to(target_panel, String(request.payload.get("meleeAttackReason", "No adjacent melee target.")))
	if weapon_mode == "missile" and not action_ids.has("attack"):
		var ranged: Variant = request.payload.get("rangedAttack", {})
		var ranged_reason := String(ranged.get("reason", "Missile attacks are unavailable.") if ranged is Dictionary else "Missile attacks are unavailable.")
		add_response_to(target_panel, "Fire unavailable", {}, false, ranged_reason)
	var spell_casts: Variant = request.payload.get("spellCasts", [])
	if action_ids.has("cast_spell") and spell_casts is Array and not spell_casts.is_empty():
		var spell_picker := OptionButton.new()
		spell_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for option: Variant in spell_casts:
			if option is Dictionary:
				var target_health := int(option.get("targetCurrentHealth", -1))
				var target_label := String(option.get("targetName", "Target"))
				var label := "%s • P%d • %d SP → %s" % [option.get("spellName", "Spell"), int(option.get("power", 1)), int(option.get("cost", 0)), target_label]
				if target_health >= 0:
					label += " (%d/%d HP)" % [target_health, int(option.get("targetMaximumHealth", 0))]
				spell_picker.add_item(label)
				spell_picker.set_item_metadata(spell_picker.item_count - 1, option.duplicate(true))
		spell_panel.add_child(spell_picker)
		var cast_button := Button.new()
		cast_button.name = "ChooseSpellTarget"
		cast_button.disabled = spell_picker.item_count == 0
		var refresh_cast_button := func(_index: int) -> void:
			if _targeting_active:
				presentation_action_requested.emit(&"cancel_battlefield_targeting", {})
			var selected: Variant = spell_picker.get_selected_metadata()
			var mode := String(selected.get("targetMode", "combatant")) if selected is Dictionary else "combatant"
			cast_button.text = "Cast selected spell" if mode == "automatic" else "Choose spell target on battlefield"
		spell_picker.item_selected.connect(refresh_cast_button)
		cast_button.pressed.connect(func() -> void:
			var option: Variant = spell_picker.get_selected_metadata()
			if not option is Dictionary:
				return
			var payload := {"actorId": actor_id, "action": "cast_spell", "targetId": "", "spellId": String(option.get("spellId", "")), "power": int(option.get("power", 1))}
			var mode := String(option.get("targetMode", "combatant"))
			if mode == "automatic":
				payload_submitted.emit(payload)
				return
			var configuration := _spell_targeting_configuration(spell_casts, option, payload)
			_start_targeting(configuration, spell_panel)
		)
		spell_panel.add_child(cast_button)
		refresh_cast_button.call(spell_picker.selected)
	elif not String(request.payload.get("spellCastReason", "")).is_empty():
		add_response_to(spell_panel, "Cast unavailable", {}, false, String(request.payload.get("spellCastReason")))
	var item_casts: Variant = request.payload.get("itemCasts", [])
	if action_ids.has("use_item") and item_casts is Array and not item_casts.is_empty():
		var item_row := HBoxContainer.new()
		item_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_panel.add_child(item_row)
		var item_picker := OptionButton.new()
		item_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for option: Variant in item_casts:
			if not option is Dictionary:
				continue
			var charge_label := "∞" if int(option.get("charges", 0)) < 0 else str(int(option.get("charges", 0)))
			var target_label := String(option.get("targetName", "Automatic"))
			var label := "%s (%s) • %s P%d → %s" % [option.get("itemName", "Item"), charge_label, option.get("spellName", "Effect"), int(option.get("power", 1)), target_label]
			var target_health := int(option.get("targetCurrentHealth", -1))
			if target_health >= 0:
				label += " (%d/%d HP)" % [target_health, int(option.get("targetMaximumHealth", 0))]
			item_picker.add_item(label)
			item_picker.set_item_metadata(item_picker.item_count - 1, option.duplicate(true))
		item_row.add_child(item_picker)
		var use_button := Button.new()
		use_button.text = "Use selected item"
		use_button.disabled = item_picker.item_count == 0
		use_button.pressed.connect(func() -> void:
			var option: Variant = item_picker.get_selected_metadata()
			if option is Dictionary:
				var payload := {"actorId": actor_id, "action": "use_item", "targetId": "", "itemInstanceId": String(option.get("itemInstanceId", ""))}
				if String(option.get("targetMode", "combatant")) == "automatic":
					payload_submitted.emit(payload)
					return
				var candidate_ids: Array[String] = []
				for candidate: Variant in item_casts:
					if candidate is Dictionary and candidate.get("itemInstanceId") == option.get("itemInstanceId") and not String(candidate.get("targetId", "")).is_empty():
						candidate_ids.append(String(candidate.get("targetId")))
				_start_targeting({"mode": "combatant", "responsePayload": payload, "candidateIds": candidate_ids}, item_panel)
		)
		item_row.add_child(use_button)
	elif not String(request.payload.get("itemCastReason", "")).is_empty():
		add_response_to(item_panel, "Use item unavailable", {}, false, String(request.payload.get("itemCastReason")))


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


func _spell_targeting_configuration(spell_casts: Array, selected: Dictionary, response_payload: Dictionary) -> Dictionary:
	var mode := String(selected.get("targetMode", "combatant"))
	var candidate_ids: Array[String] = []
	if mode == "sequence":
		for candidate: Variant in selected.get("targetCandidates", []):
			if candidate is Dictionary and not String(candidate.get("id", "")).is_empty():
				candidate_ids.append(String(candidate.get("id")))
	elif mode == "combatant":
		for candidate: Variant in spell_casts:
			if candidate is Dictionary and candidate.get("spellId") == selected.get("spellId") and int(candidate.get("power", 0)) == int(selected.get("power", 0)) and candidate.get("targetMode", "combatant") == "combatant" and not String(candidate.get("targetId", "")).is_empty():
				candidate_ids.append(String(candidate.get("targetId")))
	return {
		"mode": mode,
		"responsePayload": response_payload,
		"candidateIds": candidate_ids,
		"maximumTargets": int(selected.get("maximumTargets", 1)),
		"areaOffsets": selected.get("areaOffsets", []),
		"defaultTargetCoordinate": selected.get("defaultTargetCoordinate", []),
		"legalTargetCoordinates": selected.get("legalTargetCoordinates", []),
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
		if String(_combatants[index].get("id", "")) == combatant_id:
			_inspected_index = index
			_refresh_inspected_label()
			return


func _read_combatants(value: Variant) -> void:
	_combatants.clear()
	if value is Array:
		for combatant: Variant in value:
			if combatant is Dictionary and not String(combatant.get("id", "")).is_empty():
				_combatants.append((combatant as Dictionary).duplicate(true))


func _build_combatant_information(request: InteractionRequest, targets: Variant, parent: Container) -> void:
	var information := HBoxContainer.new()
	information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.add_theme_constant_override("separation", 16)
	var active_label := Label.new()
	active_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	active_label.text = "Active • %s\n%d attack%s • %d movement • %s\nEnemies left • %d" % [_combatant_name(_actor_id), int(request.payload.get("attackUnitsRemaining", 0)), "" if int(request.payload.get("attackUnitsRemaining", 0)) == 1 else "s", int(request.payload.get("movementRemaining", 0)), String(request.payload.get("weaponMode", "melee")).capitalize(), int(request.payload.get("enemiesRemaining", 0))]
	information.add_child(active_label)
	_inspected_label = Label.new()
	_inspected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	information.add_child(_inspected_label)
	parent.add_child(information)
	var default_id := _actor_id
	if targets is Array and not targets.is_empty() and targets[0] is Dictionary:
		default_id = String(targets[0].get("id", default_id))
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
		presentation_action_requested.emit(&"focus_combatant", {"combatantId": String(_combatants[_inspected_index].get("id", "")), "playSound": true})
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
	var details: Array[String] = ["HP %d/%d" % [int(combatant.get("currentHealth", 0)), int(combatant.get("maximumHealth", 0))]]
	if int(combatant.get("maximumSpellPoints", 0)) > 0:
		details.append("SP %d/%d" % [int(combatant.get("spellPoints", 0)), int(combatant.get("maximumSpellPoints", 0))])
	details.append("AR %d" % int(combatant.get("armor", 0)))
	details.append("MR %d" % int(combatant.get("magicResistance", 0)))
	if combatant.has("hitDice"):
		details.append("HD %d" % int(combatant.get("hitDice", 0)))
	if int(combatant.get("range", -1)) >= 0:
		details.append("Range %d%s" % [int(combatant.get("range", -1)), " • Blocked" if bool(combatant.get("blocked", false)) else ""])
	var secondary: Array[String] = []
	var weapon := String(combatant.get("weapon", ""))
	if not weapon.is_empty():
		var charges := int(combatant.get("weaponCharges", -1))
		secondary.append("%s%s" % [weapon, " (%d)" % charges if charges >= 0 else ""])
	secondary.append("Attacks %s" % String(combatant.get("attacks", "0")))
	secondary.append("Move %d" % int(combatant.get("maximumMovement", combatant.get("movement", 0))))
	var conditions := _string_array(combatant.get("conditions", []))
	if not conditions.is_empty():
		secondary.append("Conditions: %s" % ", ".join(conditions))
	var defenses: Array[String] = []
	var immunities := _string_array(combatant.get("immunities", []))
	var vulnerabilities := _string_array(combatant.get("vulnerabilities", []))
	if not immunities.is_empty():
		defenses.append("Immune: %s" % ", ".join(immunities))
	if not vulnerabilities.is_empty():
		defenses.append("Vulnerable: %s" % ", ".join(vulnerabilities))
	var defense_line := "\n%s" % " • ".join(defenses) if not defenses.is_empty() else ""
	_inspected_label.text = "Shown • %s\n%s\n%s%s" % [String(combatant.get("name", "Combatant")), " • ".join(details), " • ".join(secondary), defense_line]


func _combatant_name(combatant_id: String) -> String:
	for combatant: Dictionary in _combatants:
		if String(combatant.get("id", "")) == combatant_id:
			return String(combatant.get("name", combatant_id))
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


func _add_primary_action_row(request: InteractionRequest, actor_id: String, action_ids: Array, targets: Variant, target_panel: Control, spell_panel: Control, item_panel: Control, mode_panels: Array[Control], overview: Control) -> void:
	var weapon_switch: Variant = request.payload.get("weaponSwitch", {})
	var action_row := HFlowContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_child(action_row)
	if action_ids.has("switch_weapon") and weapon_switch is Dictionary:
		var target_mode := String(weapon_switch.get("targetMode", "melee"))
		add_response_to(action_row, "Weapon: %s" % target_mode.capitalize(), {"actorId": actor_id, "action": "switch_weapon", "targetId": ""})
	if action_ids.has("defend"):
		add_response_to(action_row, "Guard", {"actorId": actor_id, "action": "defend", "targetId": ""})
	var weapon_mode := String(request.payload.get("weaponMode", "melee"))
	var target_enabled: bool = action_ids.has("attack") and targets is Array and not (targets as Array).is_empty()
	var ranged: Variant = request.payload.get("rangedAttack", {})
	var target_reason := String(request.payload.get("meleeAttackReason", "No adjacent target.")) if weapon_mode == "melee" else String(ranged.get("reason", "Fire is unavailable.") if ranged is Dictionary else "Fire is unavailable.")
	_add_panel_toggle(action_row, "Fire" if weapon_mode == "missile" else "Attack", target_panel, mode_panels, overview, target_enabled, target_reason)
	var spell_casts: Variant = request.payload.get("spellCasts", [])
	_add_panel_toggle(action_row, "Spells", spell_panel, mode_panels, overview, action_ids.has("cast_spell") and spell_casts is Array and not spell_casts.is_empty(), String(request.payload.get("spellCastReason", "Spellcasting is unavailable.")))
	var item_casts: Variant = request.payload.get("itemCasts", [])
	_add_panel_toggle(action_row, "Items", item_panel, mode_panels, overview, action_ids.has("use_item") and item_casts is Array and not item_casts.is_empty(), String(request.payload.get("itemCastReason", "Item use is unavailable.")))
	if action_ids.has("finish"):
		add_response_to(action_row, "Finish", {"actorId": actor_id, "action": "finish", "targetId": ""})
	var retreat: Variant = request.payload.get("retreat", {})
	var retreat_enabled := action_ids.has("retreat") and retreat is Dictionary and bool(retreat.get("enabled", false))
	var retreat_reason := String(retreat.get("reason", "Retreat is unavailable.") if retreat is Dictionary else "Retreat is unavailable.")
	add_response_to(action_row, "Escape", {"actorId": actor_id, "action": "retreat", "targetId": ""}, retreat_enabled, retreat_reason)
	_add_unavailable_classic_commands(action_row)


func _add_unavailable_classic_commands(parent: Container) -> void:
	add_response_to(parent, "Auto", {}, false, "Classic Auto Character Move and the separately saved per-character Auto toggle require a typed automation workflow.")
	add_response_to(parent, "Delay", {}, false, "Classic Delay changes initiative ordering; its save-owned turn contract is not implemented yet.")
	add_response_to(parent, "Undo", {}, false, "Classic Undo requires an explicit reversible combat transaction boundary.")
	add_response_to(parent, "Bandage", {}, false, "Classic Bandage clears bleeding. Bleeding is not yet represented in typed character state, so this cannot safely mutate combat.")
	add_response_to(parent, "Turn Undead", {}, false, "Turn Undead will appear when its caste ability, target, and resolution workflow are source-backed.")


func _add_panel_toggle(parent: Container, label: String, panel: Control, panels: Array[Control], overview: Control, enabled: bool, reason: String) -> Button:
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
