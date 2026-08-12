class_name BattleInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	var actor_id := String(request.payload.get("actorId", ""))
	var actions: Variant = request.payload.get("actions", [])
	var action_ids: Array = actions if actions is Array else []
	var weapon_mode := String(request.payload.get("weaponMode", "melee"))
	var targets: Variant = request.payload.get("targets", [])
	add_hint("%d attack%s • %d movement • %s" % [int(request.payload.get("attackUnitsRemaining", 0)), "" if int(request.payload.get("attackUnitsRemaining", 0)) == 1 else "s", int(request.payload.get("movementRemaining", 0)), weapon_mode.capitalize()])
	var target_panel := VBoxContainer.new()
	var spell_panel := VBoxContainer.new()
	var item_panel := VBoxContainer.new()
	var mode_panels: Array[Control] = [target_panel, spell_panel, item_panel]
	_add_primary_action_row(request, actor_id, action_ids, targets, target_panel, spell_panel, item_panel, mode_panels)
	for panel: Control in mode_panels:
		panel.visible = false
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(panel)
	if action_ids.has("attack") and targets is Array:
		var attack_row := HFlowContainer.new()
		attack_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target_panel.add_child(attack_row)
		for target: Variant in targets:
			if target is Dictionary:
				var verb := "Fire at" if weapon_mode == "missile" else "Attack"
				add_response_to(attack_row, "%s %s • HP %d/%d" % [verb, target.get("name", "Enemy"), int(target.get("currentHealth", 0)), int(target.get("maximumHealth", 0))], {"actorId": actor_id, "action": "attack", "targetId": String(target.get("id", ""))})
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
		var has_area_spell := false
		var has_sequence_spell := false
		for option: Variant in spell_casts:
			if option is Dictionary:
				has_area_spell = has_area_spell or option.get("targetMode", "combatant") == "area"
				has_sequence_spell = has_sequence_spell or option.get("targetMode", "combatant") == "sequence"
				var target_health := int(option.get("targetCurrentHealth", -1))
				var target_label := String(option.get("targetName", "Target"))
				var label := "%s • P%d • %d SP → %s" % [option.get("spellName", "Spell"), int(option.get("power", 1)), int(option.get("cost", 0)), target_label]
				if target_health >= 0:
					label += " (%d/%d HP)" % [target_health, int(option.get("targetMaximumHealth", 0))]
				spell_picker.add_item(label)
				spell_picker.set_item_metadata(spell_picker.item_count - 1, option.duplicate(true))
		spell_panel.add_child(spell_picker)
		var cast_button := Button.new()
		cast_button.text = "Cast selected spell"
		cast_button.disabled = spell_picker.item_count == 0
		var target_x := SpinBox.new()
		var target_y := SpinBox.new()
		if has_area_spell:
			_add_hint_to(spell_panel, "Area center uses validated battlefield coordinates. A viewport pointer/highlight is still presentation work.")
			var coordinate_row := HBoxContainer.new()
			target_x.min_value = 0
			target_x.max_value = BattlefieldState.SIZE - 1
			target_x.prefix = "X "
			target_y.min_value = 0
			target_y.max_value = BattlefieldState.SIZE - 1
			target_y.prefix = "Y "
			coordinate_row.add_child(target_x)
			coordinate_row.add_child(target_y)
			spell_panel.add_child(coordinate_row)
			var update_area_controls := func(index: int) -> void:
				var selected: Variant = spell_picker.get_item_metadata(index)
				var area_selected: bool = selected is Dictionary and selected.get("targetMode", "combatant") == "area"
				target_x.editable = area_selected
				target_y.editable = area_selected
				if area_selected:
					var coordinate: Variant = selected.get("defaultTargetCoordinate", [])
					if coordinate is Array and coordinate.size() == 2:
						target_x.value = int(coordinate[0])
						target_y.value = int(coordinate[1])
			spell_picker.item_selected.connect(update_area_controls)
			update_area_controls.call(spell_picker.selected)
		var sequence_target_picker := OptionButton.new()
		var sequence_selected_picker := OptionButton.new()
		var sequence_add_button := Button.new()
		var sequence_remove_button := Button.new()
		var sequence_target_ids: Array[String] = []
		if has_sequence_spell:
			_add_hint_to(spell_panel, "Repeated spells preserve the order selected. Cast may begin after one target, up to the chosen power.")
			sequence_target_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sequence_selected_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sequence_add_button.text = "Add target"
			sequence_remove_button.text = "Remove selected target"
			spell_panel.add_child(sequence_target_picker)
			spell_panel.add_child(sequence_add_button)
			spell_panel.add_child(sequence_selected_picker)
			spell_panel.add_child(sequence_remove_button)
			var refresh_sequence_controls := func(index: int) -> void:
				sequence_target_ids.clear()
				sequence_target_picker.clear()
				sequence_selected_picker.clear()
				var selected: Variant = spell_picker.get_item_metadata(index)
				var sequence_selected: bool = selected is Dictionary and selected.get("targetMode", "combatant") == "sequence"
				sequence_target_picker.visible = sequence_selected
				sequence_selected_picker.visible = sequence_selected
				sequence_add_button.visible = sequence_selected
				sequence_remove_button.visible = sequence_selected
				if sequence_selected:
					var candidates: Variant = selected.get("targetCandidates", [])
					if candidates is Array:
						for candidate: Variant in candidates:
							if candidate is Dictionary:
								sequence_target_picker.add_item("%s • HP %d/%d" % [candidate.get("name", "Target"), int(candidate.get("currentHealth", 0)), int(candidate.get("maximumHealth", 0))])
								sequence_target_picker.set_item_metadata(sequence_target_picker.item_count - 1, candidate.duplicate(true))
				cast_button.disabled = spell_picker.item_count == 0 or (sequence_selected and sequence_target_ids.is_empty())
			spell_picker.item_selected.connect(refresh_sequence_controls)
			sequence_add_button.pressed.connect(func() -> void:
				var option: Variant = spell_picker.get_selected_metadata()
				var candidate: Variant = sequence_target_picker.get_selected_metadata()
				if not option is Dictionary or not candidate is Dictionary:
					return
				var target_id := String(candidate.get("id", ""))
				if target_id.is_empty() or sequence_target_ids.has(target_id) or sequence_target_ids.size() >= int(option.get("maximumTargets", 1)):
					return
				sequence_target_ids.append(target_id)
				sequence_selected_picker.add_item(String(candidate.get("name", "Target")))
				sequence_selected_picker.set_item_metadata(sequence_selected_picker.item_count - 1, target_id)
				cast_button.disabled = false
			)
			sequence_remove_button.pressed.connect(func() -> void:
				var index := sequence_selected_picker.selected
				if index < 0 or index >= sequence_target_ids.size():
					return
				sequence_target_ids.remove_at(index)
				sequence_selected_picker.remove_item(index)
				cast_button.disabled = sequence_target_ids.is_empty()
			)
			refresh_sequence_controls.call(spell_picker.selected)
		cast_button.pressed.connect(func() -> void:
			var option: Variant = spell_picker.get_selected_metadata()
			if option is Dictionary:
				var payload := {"actorId": actor_id, "action": "cast_spell", "targetId": String(option.get("targetId", "")), "spellId": String(option.get("spellId", "")), "power": int(option.get("power", 1))}
				if option.get("targetMode", "combatant") == "sequence":
					if sequence_target_ids.is_empty():
						return
					payload["targetIds"] = sequence_target_ids.duplicate()
				if option.get("targetMode", "combatant") == "area":
					payload["targetCoordinate"] = [int(target_x.value), int(target_y.value)]
					payload["rotation"] = 0
				payload_submitted.emit(payload)
		)
		spell_panel.add_child(cast_button)
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
				payload_submitted.emit({"actorId": actor_id, "action": "use_item", "targetId": String(option.get("targetId", "")), "itemInstanceId": String(option.get("itemInstanceId", ""))})
		)
		item_row.add_child(use_button)
	elif not String(request.payload.get("itemCastReason", "")).is_empty():
		add_response_to(item_panel, "Use item unavailable", {}, false, String(request.payload.get("itemCastReason")))
	add_hint("Move with arrows, WASD, keypad, or a neighboring battlefield tile • hold Shift to show movement costs")


func accepts_spatial_input() -> bool:
	for child: Node in get_children():
		if child is Control and (child as Control).visible and child is VBoxContainer and child != self:
			return false
	return true


func _add_primary_action_row(request: InteractionRequest, actor_id: String, action_ids: Array, targets: Variant, target_panel: Control, spell_panel: Control, item_panel: Control, mode_panels: Array[Control]) -> void:
	var weapon_switch: Variant = request.payload.get("weaponSwitch", {})
	var action_row := HFlowContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(action_row)
	if action_ids.has("switch_weapon") and weapon_switch is Dictionary:
		var target_mode := String(weapon_switch.get("targetMode", "melee"))
		add_response_to(action_row, "Weapon: %s" % target_mode.capitalize(), {"actorId": actor_id, "action": "switch_weapon", "targetId": ""})
	if action_ids.has("defend"):
		add_response_to(action_row, "Guard", {"actorId": actor_id, "action": "defend", "targetId": ""})
	var weapon_mode := String(request.payload.get("weaponMode", "melee"))
	var target_enabled: bool = action_ids.has("attack") and targets is Array and not (targets as Array).is_empty()
	var ranged: Variant = request.payload.get("rangedAttack", {})
	var target_reason := String(request.payload.get("meleeAttackReason", "No adjacent target.")) if weapon_mode == "melee" else String(ranged.get("reason", "Fire is unavailable.") if ranged is Dictionary else "Fire is unavailable.")
	_add_panel_toggle(action_row, "Fire" if weapon_mode == "missile" else "Attack", target_panel, mode_panels, target_enabled, target_reason)
	var spell_casts: Variant = request.payload.get("spellCasts", [])
	_add_panel_toggle(action_row, "Spells", spell_panel, mode_panels, action_ids.has("cast_spell") and spell_casts is Array and not spell_casts.is_empty(), String(request.payload.get("spellCastReason", "Spellcasting is unavailable.")))
	var item_casts: Variant = request.payload.get("itemCasts", [])
	_add_panel_toggle(action_row, "Items", item_panel, mode_panels, action_ids.has("use_item") and item_casts is Array and not item_casts.is_empty(), String(request.payload.get("itemCastReason", "Item use is unavailable.")))
	if action_ids.has("finish"):
		add_response_to(action_row, "Finish", {"actorId": actor_id, "action": "finish", "targetId": ""})
	var retreat: Variant = request.payload.get("retreat", {})
	var retreat_enabled := action_ids.has("retreat") and retreat is Dictionary and bool(retreat.get("enabled", false))
	var retreat_reason := String(retreat.get("reason", "Retreat is unavailable.") if retreat is Dictionary else "Retreat is unavailable.")
	add_response_to(action_row, "Escape", {"actorId": actor_id, "action": "retreat", "targetId": ""}, retreat_enabled, retreat_reason)


func _add_panel_toggle(parent: Container, label: String, panel: Control, panels: Array[Control], enabled: bool, reason: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 36.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not enabled
	button.tooltip_text = reason if not enabled else ""
	button.pressed.connect(func() -> void:
		var show := not panel.visible
		for candidate: Control in panels:
			candidate.visible = show and candidate == panel
	)
	parent.add_child(button)
	return button


func _add_hint_to(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("d5b45d"))
	parent.add_child(label)
	return label
