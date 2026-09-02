class_name BattleInteraction
extends InteractionComponent

const MAX_VISIBLE_TURNS := 6
const COMMAND_HEIGHT := 30.0
const SUMMARY_HEIGHT := 58.0
const PRESENTATION_COMMAND_HEIGHT := 24.0
const COMMAND_FONT_SIZE := 14.0
const COMMAND_GROUP_HEIGHT := 100.0
const COMMAND_GROUP_SEPARATION := 10.0
const COMMAND_COLUMN_SEPARATION := 4.0
const COMMAND_ROW_SEPARATION := 5.0
const COMMAND_BASE_SIZE_META: StringName = &"battle_command_base_size"
const PRIMARY_COMMAND_COLOR := Color("f0ce59")
const VIEW_COMMAND_COLOR := Color("63d8e7")
const TURN_COMMAND_COLOR := Color("8fe080")

var _actor_id: String = ""
var _combatants: Array[InteractionRequestValue.Combatant] = []
var _inspected_index: int = -1
var _inspected_label: Label
var _mode_panels: Array[Control] = []
var _targeting_status_label: Label
var _targeting_confirm_button: Button
var _targeting_controls: VBoxContainer
var _targeting_active: bool = false
var _targeting_setup_controls: Array[Control] = []
var _targeting_parent: Control
var _targeting_parent_was_visible: bool = false
var _spell_casts: Array[InteractionRequestValue.CastOption] = []
var _fast_spells: Array[InteractionRequestValue.FastSpell] = []
var _spell_panel: VBoxContainer
var _combatant_icons: Dictionary = {}
var _overview: Control
var _inspected_icon: TextureRect
var _inspection_panel: VBoxContainer
var _inspection_title: Label
var _inspection_content: Label
var _inspection_section: StringName = &"attacks"
var _inspection_buttons: Dictionary = {}
var _command_scale: float = 1.0
var _command_shelf: HBoxContainer
var _scaled_command_panels: Array[Control] = []
var _scaled_command_columns: Array[VBoxContainer] = []
var _scaled_command_headings: Array[Label] = []
var _scaled_command_rows: Array[HBoxContainer] = []
var _scaled_command_buttons: Array[Button] = []


func configure(combatant_icons: Dictionary, command_scale: float = 1.0) -> void:
	_combatant_icons = combatant_icons.duplicate()
	set_command_scale(command_scale)


func set_command_scale(command_scale: float) -> void:
	_command_scale = clampf(command_scale, 1.0, 2.0)
	_apply_command_scale()


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.CombatRequestBody
	if body == null: return
	var actor_id := body.actor_id
	_actor_id = actor_id
	_reset_command_scale_targets()
	_mode_panels.clear()
	_targeting_status_label = null
	_targeting_confirm_button = null
	_targeting_controls = null
	_targeting_active = false
	_targeting_parent = null
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
	var inspection_panel := VBoxContainer.new()
	inspection_panel.name = "BattleCombatantInspection"
	_inspection_panel = inspection_panel
	var mode_panels: Array[Control] = [target_panel, spell_panel, scroll_panel, item_panel, bandage_panel, inspection_panel]
	_mode_panels.assign(mode_panels)
	_spell_casts = body.spell_casts
	_fast_spells = body.fast_spells
	var overview := VBoxContainer.new()
	overview.name = "BattleOverview"
	_overview = overview
	overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_theme_constant_override("separation", 3)
	add_child(overview)
	_build_combatant_information(body, targets, overview)
	_build_command_shelf(body, actor_id, action_ids, targets, target_panel, spell_panel, scroll_panel, item_panel, bandage_panel, mode_panels, overview)
	for panel: Control in mode_panels:
		panel.visible = false
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_constant_override("separation", 6)
		add_child(panel)
		_add_mode_back_button(panel, overview, mode_panels)
	_build_attack_panel(body, actor_id, action_ids, targets, target_panel, weapon_mode)
	_build_spell_panel(body, actor_id, action_ids, spell_panel)
	_build_combatant_inspection(inspection_panel)
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
				combat_targeting_cancel_requested.emit()
			var selected := scroll_picker.get_selected_metadata() as InteractionRequestValue.CastOption
			var mode := String(selected.target_mode) if selected != null else "combatant"
			use_scroll_button.text = "Use selected scroll" if mode == "automatic" else "Choose scroll target on battlefield"
		scroll_picker.item_selected.connect(refresh_scroll_button)
		use_scroll_button.pressed.connect(func() -> void:
			var option := scroll_picker.get_selected_metadata() as InteractionRequestValue.CastOption
			if option == null: return
			var response_body := InteractionResponse.CombatBody.new(&"use_scroll", actor_id)
			response_body.scroll_slot = option.scroll_slot
			var mode := String(option.target_mode)
			if mode == "automatic":
				response_body_submitted.emit(response_body)
				return
			var configuration := _spell_targeting_configuration(body.scroll_casts, option, response_body)
			_start_targeting(configuration, scroll_panel)
		)
		scroll_panel.add_child(use_scroll_button)
		refresh_scroll_button.call(scroll_picker.selected)
	elif not body.scroll_cast_reason.is_empty():
		add_response_to(scroll_panel, "Use scroll unavailable", InteractionResponse.CombatBody.new(&"use_scroll", actor_id), false, body.scroll_cast_reason)
	if action_ids.has("use_item") and not body.item_casts.is_empty():
		var item_row := HBoxContainer.new()
		item_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_panel.add_child(item_row)
		var item_picker := OptionButton.new()
		item_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for option: InteractionRequestValue.CastOption in body.item_casts:
			var charge_label := "∞" if option.charges < 0 else str(option.charges)
			var power_label := "Random power" if option.target_mode == &"random_power" else "Rolled P%d" % option.power if option.power_staged else "P%d" % option.power
			var label := "%s (%s) • %s %s → %s" % [option.item_name, charge_label, option.spell_name, power_label, option.target_name]
			if option.target_current_health >= 0: label += " (%d/%d HP)" % [option.target_current_health, option.target_maximum_health]
			item_picker.add_item(label)
			item_picker.set_item_metadata(item_picker.item_count - 1, option)
		item_row.add_child(item_picker)
		var use_button := Button.new()
		use_button.name = "ChooseItemTarget"
		use_button.text = "Use selected item"
		use_button.disabled = item_picker.item_count == 0
		use_button.pressed.connect(func() -> void:
			var option := item_picker.get_selected_metadata() as InteractionRequestValue.CastOption
			if option == null: return
			var response_body := InteractionResponse.CombatBody.new(&"use_item", actor_id)
			response_body.item_instance_id = option.item_instance_id
			if option.target_mode in [&"automatic", &"random_power"]:
				response_body_submitted.emit(response_body)
				return
			_start_targeting(_spell_targeting_configuration(body.item_casts, option, response_body), item_panel)
		)
		item_row.add_child(use_button)
		var refresh_item_button := func(_index: int) -> void:
			var option := item_picker.get_selected_metadata() as InteractionRequestValue.CastOption
			use_button.text = "Roll item power" if option != null and option.target_mode == &"random_power" else "Choose item target" if option != null and option.target_mode != &"automatic" else "Use selected item"
		item_picker.item_selected.connect(refresh_item_button)
		refresh_item_button.call(item_picker.selected)
	elif not body.item_cast_reason.is_empty():
		add_response_to(item_panel, "Use item unavailable", InteractionResponse.CombatBody.new(&"use_item", actor_id), false, body.item_cast_reason)


func _build_attack_panel(body: InteractionRequest.CombatRequestBody, actor_id: String, action_ids: Array[String], targets: Array[InteractionRequestValue.CombatTarget], target_panel: VBoxContainer, weapon_mode: String) -> void:
	if action_ids.has("attack"):
		var candidate_ids: Array[String] = []
		for target: InteractionRequestValue.CombatTarget in targets:
			if not target.id.is_empty(): candidate_ids.append(target.id)
		var targeting := CombatTargetingRequest.new(&"combatant", InteractionResponse.CombatBody.new(&"attack", actor_id))
		targeting.candidate_ids = candidate_ids
		_add_targeting_button(target_panel, "Choose Fire target on battlefield" if weapon_mode == "missile" else "Choose attack target on battlefield", targeting)
	elif weapon_mode == "melee" and not body.melee_attack_reason.is_empty():
		_add_hint_to(target_panel, body.melee_attack_reason)
	if weapon_mode == "missile" and not action_ids.has("attack"):
		add_response_to(target_panel, "Fire unavailable", InteractionResponse.CombatBody.new(&"attack", actor_id), false, body.ranged_attack.reason)


func _build_spell_panel(body: InteractionRequest.CombatRequestBody, actor_id: String, action_ids: Array[String], spell_panel: VBoxContainer) -> void:
	if not action_ids.has("cast_spell") or body.spell_casts.is_empty():
		if not body.spell_cast_reason.is_empty():
			add_response_to(spell_panel, "Cast unavailable", InteractionResponse.CombatBody.new(&"cast_spell", actor_id), false, body.spell_cast_reason)
		return
	var status := _add_hint_to(spell_panel, "Choose a spell, power, and target from the spellbook at right.")
	status.name = "CombatSpellbookStatus"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func cast_spell_option(option: InteractionRequestValue.CastOption) -> void:
	if option == null or not _contains_spell_option(option):
		return
	_cancel_active_targeting()
	var response_body := InteractionResponse.CombatBody.new(&"cast_spell", _actor_id)
	response_body.spell_id = option.spell_id
	response_body.power = option.power
	if option.target_mode == &"automatic":
		response_body_submitted.emit(response_body)
		return
	_start_targeting(_spell_targeting_configuration(_spell_casts, option, response_body), _spell_panel)


func close_spellbook() -> void:
	_cancel_active_targeting()
	for panel: Control in _mode_panels:
		panel.visible = false
	if _overview != null:
		_overview.visible = true
	combat_spellbook_closed.emit()


func _contains_spell_option(option: InteractionRequestValue.CastOption) -> bool:
	for candidate: InteractionRequestValue.CastOption in _spell_casts:
		if candidate.spell_id == option.spell_id and candidate.power == option.power and candidate.target_mode == option.target_mode:
			return true
	return false


func _cancel_active_targeting() -> void:
	if _targeting_active:
		combat_targeting_cancel_requested.emit()


func handle_fast_spell(slot_index: int, use_spell: bool) -> bool:
	if slot_index < 0 or slot_index >= _fast_spells.size():
		return false
	var binding := _fast_spells[slot_index]
	var shortcut := "0" if slot_index == 9 else str(slot_index + 1)
	if binding.spell_id.is_empty():
		presentation_status_requested.emit("Fast Spell %s • Undefined Spell" % shortcut, false)
		presentation_sound_requested.emit(143)
		return true
	var summary := "Fast Spell %s • %s P%d" % [shortcut, binding.spell_name, binding.power]
	if not use_spell:
		presentation_status_requested.emit(summary, false)
		presentation_sound_requested.emit(145)
		return true
	if not binding.enabled:
		presentation_status_requested.emit("%s • %s" % [summary, binding.reason], true)
		presentation_sound_requested.emit(143)
		return true
	for candidate: InteractionRequestValue.CastOption in _spell_casts:
		if candidate.spell_id == binding.spell_id and candidate.power == binding.power:
			var response_body := InteractionResponse.CombatBody.new(&"cast_spell", _actor_id)
			response_body.spell_id = binding.spell_id
			response_body.power = binding.power
			if candidate.target_mode == &"automatic":
				response_body_submitted.emit(response_body)
				return true
			_start_targeting(_spell_targeting_configuration(_spell_casts, candidate, response_body), _spell_panel)
			return true
	presentation_status_requested.emit("%s • No legal target is available." % summary, true)
	presentation_sound_requested.emit(143)
	return true


func update_battlefield_targeting(selection: CombatTargetingState) -> void:
	if not _targeting_active or _targeting_status_label == null or _targeting_confirm_button == null:
		return
	_targeting_status_label.text = "Targeting • %s" % selection.status_text
	_targeting_status_label.tooltip_text = selection.status_text
	_targeting_confirm_button.disabled = not selection.can_confirm()


func battlefield_targeting_cancelled() -> void:
	var return_to_overview := _targeting_parent != null and not _targeting_parent_was_visible
	var target_parent := _targeting_parent
	_targeting_active = false
	_restore_targeting_setup()
	if return_to_overview and target_parent != null:
		target_parent.visible = false
		_overview.visible = true


func _spell_targeting_configuration(spell_casts: Array[InteractionRequestValue.CastOption], selected: InteractionRequestValue.CastOption, response_body: InteractionResponse.CombatBody) -> CombatTargetingRequest:
	var mode := selected.target_mode
	var candidate_ids: Array[String] = []
	if mode == &"sequence":
		for candidate: InteractionRequestValue.CombatTarget in selected.target_candidates:
			if not candidate.id.is_empty(): candidate_ids.append(candidate.id)
	elif mode == &"combatant":
		for candidate: InteractionRequestValue.CastOption in spell_casts:
			if candidate.spell_id == selected.spell_id and candidate.power == selected.power and candidate.scroll_slot == selected.scroll_slot and candidate.target_mode == &"combatant" and not candidate.target_id.is_empty(): candidate_ids.append(candidate.target_id)
	if candidate_ids.is_empty() and response_body.action == &"cast_spell" and mode in [&"combatant", &"sequence"]:
		for combatant: InteractionRequestValue.Combatant in _combatants:
			if not combatant.id.is_empty(): candidate_ids.append(combatant.id)
	var result := CombatTargetingRequest.new(mode, response_body)
	result.candidate_ids = candidate_ids
	result.maximum_targets = selected.maximum_targets
	result.area_offsets = selected.area_offsets.duplicate()
	result.area_rotation_offsets = selected.area_rotation_offsets.duplicate(true)
	result.default_target_coordinate = selected.default_target_coordinate
	result.legal_coordinates = selected.legal_target_coordinates.duplicate()
	result.validation_deferred = response_body.action == &"cast_spell" and mode in [&"combatant", &"sequence", &"coordinate_sequence"] or mode == &"area" and (result.legal_coordinates.is_empty() or result.supports_rotation())
	return result


func _add_targeting_button(parent: Container, text: String, configuration: CombatTargetingRequest) -> void:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"BattleCommandButton"
	button.custom_minimum_size.y = COMMAND_HEIGHT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: _start_targeting(configuration, parent))
	parent.add_child(button)


func _start_targeting(configuration: CombatTargetingRequest, parent: Container) -> void:
	_restore_targeting_setup()
	_targeting_parent = parent
	_targeting_parent_was_visible = parent.visible
	_targeting_active = true
	if _mode_panels.has(parent):
		for panel: Control in _mode_panels:
			panel.visible = panel == parent
		_overview.visible = false
	for child: Node in parent.get_children():
		if child is Control and child.name not in ["BattleModeBack", "BattleTargetingControls"]:
			(child as Control).visible = false
			_targeting_setup_controls.append(child as Control)
	_targeting_controls = VBoxContainer.new()
	_targeting_controls.name = "BattleTargetingControls"
	_targeting_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_targeting_controls.add_theme_constant_override("separation", 3)
	parent.add_child(_targeting_controls)
	_targeting_status_label = _add_hint_to(_targeting_controls, "Targeting • Aim with the pointer; T marks or cycles a target; Space casts.")
	_targeting_status_label.add_theme_font_size_override("font_size", 12)
	_targeting_status_label.max_lines_visible = 1
	_targeting_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var target_actions := HBoxContainer.new()
	target_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_actions.add_theme_constant_override("separation", 3)
	_targeting_confirm_button = Button.new()
	_targeting_confirm_button.name = "ConfirmBattleTarget"
	_targeting_confirm_button.text = "Cast spell" if configuration.response_body.action == &"cast_spell" else "Confirm target"
	_targeting_confirm_button.tooltip_text = "Press Space to confirm the selected target."
	_targeting_confirm_button.disabled = true
	_targeting_confirm_button.theme_type_variation = &"BattleCommandButton"
	_targeting_confirm_button.custom_minimum_size.y = COMMAND_HEIGHT
	_targeting_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_targeting_confirm_button.pressed.connect(func() -> void: combat_targeting_confirm_requested.emit())
	target_actions.add_child(_targeting_confirm_button)
	if configuration.supports_rotation():
		var rotate := Button.new()
		rotate.name = "RotateBattleTarget"
		rotate.text = "Rotate area"
		rotate.tooltip_text = "Cycle the source-authored area orientations."
		rotate.theme_type_variation = &"BattleCommandButton"
		rotate.custom_minimum_size.y = COMMAND_HEIGHT
		rotate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rotate.pressed.connect(func() -> void: combat_targeting_rotate_requested.emit())
		target_actions.add_child(rotate)
	var cancel := Button.new()
	cancel.name = "CancelBattleTarget"
	cancel.text = "Cancel targeting"
	cancel.theme_type_variation = &"BattleCommandButton"
	cancel.custom_minimum_size.y = COMMAND_HEIGHT
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void: combat_targeting_cancel_requested.emit())
	target_actions.add_child(cancel)
	_targeting_controls.add_child(target_actions)
	combat_targeting_requested.emit(configuration)


func _restore_targeting_setup() -> void:
	for control: Control in _targeting_setup_controls:
		if is_instance_valid(control):
			control.visible = true
	_targeting_setup_controls.clear()
	if _targeting_controls != null and is_instance_valid(_targeting_controls):
		_targeting_controls.visible = false
		_targeting_controls.queue_free()
	_targeting_controls = null
	_targeting_status_label = null
	_targeting_confirm_button = null
	_targeting_parent = null
	_targeting_parent_was_visible = false


func inspect_combatant(combatant_id: String) -> bool:
	for index: int in _combatants.size():
		if _combatants[index].id == combatant_id:
			_inspected_index = index
			_refresh_inspected_label()
			return true
	return false


func open_combatant_inspection(combatant_id: String) -> bool:
	if not inspect_combatant(combatant_id) or _inspection_panel == null:
		return false
	_cancel_active_targeting()
	for panel: Control in _mode_panels:
		panel.visible = panel == _inspection_panel
	if _overview != null:
		_overview.visible = false
	_inspection_section = &"attacks"
	_refresh_combatant_inspection()
	return true


func _read_combatants(value: Array[InteractionRequestValue.Combatant]) -> void:
	_combatants.clear()
	for combatant: InteractionRequestValue.Combatant in value:
		if not combatant.id.is_empty(): _combatants.append(combatant)


func _build_combatant_information(body: InteractionRequest.CombatRequestBody, targets: Array[InteractionRequestValue.CombatTarget], parent: Container) -> void:
	var information := HBoxContainer.new()
	information.name = "BattleTurnSummary"
	information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.custom_minimum_size.y = SUMMARY_HEIGHT
	information.add_theme_constant_override("separation", 4)
	var active_panel := _summary_panel("ActiveCombatant", 0.8)
	active_panel.custom_minimum_size.x = 200.0
	var active_content := HBoxContainer.new()
	active_content.add_theme_constant_override("separation", 5)
	var active_icon := _combatant_icon(_actor_id, 40.0)
	active_icon.name = "ActiveCombatantIcon"
	active_content.add_child(active_icon)
	var active_label := Label.new()
	active_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	active_label.add_theme_font_size_override("font_size", 12)
	active_label.max_lines_visible = 2
	active_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	active_label.text = "Active • %s\n%d AT • %d MP • %s • %d enemies" % [_combatant_name(_actor_id), body.attack_units_remaining, body.movement_remaining, String(body.weapon_mode).capitalize(), body.enemies_remaining]
	active_label.tooltip_text = "%s\n%d attack%s • %d movement • %s\nEnemies left • %d" % [_combatant_name(_actor_id), body.attack_units_remaining, "" if body.attack_units_remaining == 1 else "s", body.movement_remaining, String(body.weapon_mode).capitalize(), body.enemies_remaining]
	active_label.add_theme_color_override("font_color", Color("f8dc52"))
	active_content.add_child(active_label)
	active_panel.add_child(active_content)
	information.add_child(active_panel)
	information.add_child(_build_initiative_panel(body.round_number))
	var inspected_panel := _summary_panel("InspectedCombatant", 0.95)
	inspected_panel.custom_minimum_size.x = 250.0
	var inspected_content := HBoxContainer.new()
	inspected_content.add_theme_constant_override("separation", 5)
	_inspected_icon = _combatant_icon("", 40.0)
	_inspected_icon.name = "InspectedCombatantIcon"
	inspected_content.add_child(_inspected_icon)
	_inspected_label = Label.new()
	_inspected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspected_label.add_theme_font_size_override("font_size", 12)
	_inspected_label.max_lines_visible = 2
	_inspected_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inspected_content.add_child(_inspected_label)
	inspected_panel.add_child(inspected_content)
	information.add_child(inspected_panel)
	parent.add_child(information)
	var default_id := _actor_id
	if not targets.is_empty(): default_id = targets[0].id
	inspect_combatant(default_id)
	if _inspected_index < 0 and not _combatants.is_empty():
		_inspected_index = 0
	_refresh_inspected_label()
func _add_presentation_button(parent: Container, text: String, action: StringName) -> void:
	var button := Button.new()
	button.name = "CombatPresentation%s" % String(action).to_pascal_case()
	button.text = text
	button.theme_type_variation = &"BattleCommandButton"
	_register_scaled_command_button(button, Vector2(0.0, PRESENTATION_COMMAND_HEIGHT))
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if action == &"reveal_friends":
		_color_command(button, VIEW_COMMAND_COLOR)
	button.pressed.connect(func() -> void: _perform_presentation_action(action))
	parent.add_child(button)


func _perform_presentation_action(action: StringName) -> void:
	if action in [&"inspect_previous", &"inspect_next"] and not _combatants.is_empty():
		var delta := -1 if action == &"inspect_previous" else 1
		_inspected_index = posmod(_inspected_index + delta, _combatants.size())
		_refresh_inspected_label()
		combatant_focus_requested.emit(_combatants[_inspected_index].id, true)
		return
	if action == &"center_active":
		inspect_combatant(_actor_id)
		combatant_focus_requested.emit(_actor_id, true)
		return
	if action == &"reveal_friends":
		reveal_friends_requested.emit()


func _refresh_inspected_label() -> void:
	if _inspected_label == null:
		return
	if _inspected_index < 0 or _inspected_index >= _combatants.size():
		_inspected_label.text = "Shown • No combatant selected"
		_inspected_icon.texture = null
		_inspected_icon.visible = false
		return
	var combatant := _combatants[_inspected_index]
	_inspected_icon.texture = _combatant_icons.get(combatant.id) as Texture2D
	_inspected_icon.visible = _inspected_icon.texture != null
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
	_inspected_label.text = "Shown • %s\n%s • %s" % [combatant.name, " • ".join(details), " • ".join(secondary)]
	_inspected_label.tooltip_text = "Shown • %s\n%s\n%s%s" % [combatant.name, " • ".join(details), " • ".join(secondary), defense_line]
	_refresh_combatant_inspection()


func _build_combatant_inspection(parent: VBoxContainer) -> void:
	var heading := HBoxContainer.new()
	heading.name = "BattleInspectionHeading"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 4)
	_inspection_title = Label.new()
	_inspection_title.name = "BattleInspectionTitle"
	_inspection_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspection_title.add_theme_color_override("font_color", VIEW_COMMAND_COLOR)
	heading.add_child(_inspection_title)
	_inspection_buttons.clear()
	for section: StringName in [&"items", &"conditions", &"attacks"]:
		var button := Button.new()
		button.name = "BattleInspection%s" % String(section).to_pascal_case()
		button.text = String(section).capitalize()
		button.toggle_mode = true
		button.theme_type_variation = &"BattleCommandButton"
		_register_scaled_command_button(button, Vector2(0.0, PRESENTATION_COMMAND_HEIGHT))
		button.pressed.connect(func() -> void:
			_inspection_section = section
			_refresh_combatant_inspection()
		)
		heading.add_child(button)
		_inspection_buttons[section] = button
	parent.add_child(heading)
	var frame := _summary_panel("BattleInspectionRecord", 1.0)
	frame.custom_minimum_size.y = 58.0
	var scroll := ScrollContainer.new()
	scroll.name = "BattleInspectionScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspection_content = Label.new()
	_inspection_content.name = "BattleInspectionContent"
	_inspection_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspection_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspection_content.add_theme_font_size_override("font_size", 12)
	scroll.add_child(_inspection_content)
	frame.add_child(scroll)
	parent.add_child(frame)
	_refresh_combatant_inspection()


func _refresh_combatant_inspection() -> void:
	if _inspection_title == null or _inspection_content == null:
		return
	if _inspected_index < 0 or _inspected_index >= _combatants.size():
		_inspection_title.text = "Inspect combatant"
		_inspection_content.text = "No combatant selected."
		return
	var combatant := _combatants[_inspected_index]
	_inspection_title.text = "%s • %s" % [combatant.name, String(_inspection_section).capitalize()]
	var rows: Array[String] = []
	match _inspection_section:
		&"items": rows.assign(combatant.items)
		&"conditions": rows.assign(combatant.conditions)
		_: rows.assign(combatant.attack_rows)
	if rows.is_empty():
		rows.append("None")
	_inspection_content.text = "\n".join(rows)
	_inspection_content.tooltip_text = _inspection_content.text
	for section: StringName in _inspection_buttons:
		(_inspection_buttons[section] as Button).set_pressed_no_signal(section == _inspection_section)


func _combatant_icon(combatant_id: String, extent: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = _combatant_icons.get(combatant_id) as Texture2D
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(extent, extent)
	icon.visible = icon.texture != null
	return icon


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


func _build_command_shelf(body: InteractionRequest.CombatRequestBody, actor_id: String, action_ids: Array[String], targets: Array[InteractionRequestValue.CombatTarget], target_panel: Control, spell_panel: Control, scroll_panel: Control, item_panel: Control, bandage_panel: Control, mode_panels: Array[Control], overview: Control) -> void:
	var shelf_center := CenterContainer.new()
	shelf_center.name = "BattleCommandShelfCenter"
	shelf_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.add_child(shelf_center)
	var shelf := HBoxContainer.new()
	shelf.name = "BattleCommandShelf"
	shelf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_command_shelf = shelf
	shelf.add_theme_constant_override("separation", roundi(COMMAND_GROUP_SEPARATION * _command_scale))
	shelf_center.add_child(shelf)
	var inspection := _command_group(shelf, "BattleInspectionCommands", "View", VIEW_COMMAND_COLOR)
	var inspection_rows := _command_rows(inspection, "BattleInspection")
	_add_presentation_button(inspection_rows[0], "Previous", &"inspect_previous")
	_add_presentation_button(inspection_rows[0], "Center", &"center_active")
	_add_presentation_button(inspection_rows[0], "Next", &"inspect_next")
	_add_presentation_button(inspection_rows[1], "Reveal Friends", &"reveal_friends")
	var primary := _command_group(shelf, "BattlePrimaryCommands", "Action", PRIMARY_COMMAND_COLOR)
	var primary_rows := _command_rows(primary, "BattlePrimary")
	var can_switch := action_ids.has("switch_weapon") and body.weapon_switch.enabled
	var shown_weapon_mode := String(body.weapon_switch.target_mode) if can_switch else String(body.weapon_mode)
	_add_fixed_response(primary_rows[0], "Weapon", "Weapon: %s" % shown_weapon_mode.capitalize(), InteractionResponse.CombatBody.new(&"switch_weapon", actor_id), can_switch, body.weapon_switch.reason)
	_color_command(_add_fixed_response(primary_rows[0], "Guard", "Guard", InteractionResponse.CombatBody.new(&"defend", actor_id), action_ids.has("defend"), "Guard is unavailable during this activation."), TURN_COMMAND_COLOR)
	var weapon_mode := String(body.weapon_mode)
	var target_enabled: bool = action_ids.has("attack") and not targets.is_empty()
	var target_reason := body.melee_attack_reason if weapon_mode == "melee" else body.ranged_attack.reason
	var attack_button := _add_panel_toggle(primary_rows[0], "Fire" if weapon_mode == "missile" else "Attack", target_panel, mode_panels, overview, target_enabled, target_reason)
	_name_command(attack_button, "Attack")
	_accent_command(attack_button)
	var finish_button := _add_fixed_response(primary_rows[0], "Finish", "Finish", InteractionResponse.CombatBody.new(&"finish", actor_id), action_ids.has("finish"), "Finish is unavailable during this activation.")
	_accent_command(finish_button)
	var spell_button := _add_panel_toggle(primary_rows[1], "Spells", spell_panel, mode_panels, overview, action_ids.has("cast_spell") and not body.spell_casts.is_empty(), body.spell_cast_reason)
	_name_command(spell_button, "Spells")
	_color_command(spell_button, VIEW_COMMAND_COLOR)
	spell_button.pressed.connect(func() -> void:
		if spell_panel.visible:
			combat_spellbook_requested.emit(actor_id, _spell_casts)
		else:
			combat_spellbook_closed.emit()
	)
	var scroll_button := _add_panel_toggle(primary_rows[1], "Scrolls", scroll_panel, mode_panels, overview, action_ids.has("use_scroll") and not body.scroll_casts.is_empty(), body.scroll_cast_reason, 647)
	_name_command(scroll_button, "Scrolls")
	_color_command(scroll_button, VIEW_COMMAND_COLOR)
	var item_button := _add_panel_toggle(primary_rows[1], "Items", item_panel, mode_panels, overview, action_ids.has("use_item") and not body.item_casts.is_empty(), body.item_cast_reason)
	_name_command(item_button, "Items")
	_color_command(item_button, VIEW_COMMAND_COLOR)
	var turn := _command_group(shelf, "BattleTurnCommands", "Tactics", TURN_COMMAND_COLOR)
	var turn_rows := _command_rows(turn, "BattleTurn")
	_add_classic_turn_commands(turn_rows[0], turn_rows[1], body, actor_id, bandage_panel, mode_panels, overview)
	var retreat_enabled := action_ids.has("retreat") and body.retreat.enabled
	_accent_command(_add_fixed_response(turn_rows[1], "Escape", "Escape", InteractionResponse.CombatBody.new(&"retreat", actor_id), retreat_enabled, body.retreat.reason))


func _add_classic_turn_commands(first_row: Container, second_row: Container, body: InteractionRequest.CombatRequestBody, actor_id: String, bandage_panel: Control, mode_panels: Array[Control], overview: Control) -> void:
	_color_command(_add_fixed_response(first_row, "AutoTurn", "Auto Turn", InteractionResponse.CombatBody.new(&"auto", actor_id), body.auto_turn.enabled, body.auto_turn.reason), TURN_COMMAND_COLOR)
	_color_command(_add_fixed_response(first_row, "Delay", "Delay", InteractionResponse.CombatBody.new(&"delay", actor_id), body.delay.enabled, body.delay.reason), TURN_COMMAND_COLOR)
	var bandage_enabled := body.bandage.enabled and not body.bandage_targets.is_empty()
	var bandage_reason := body.bandage.reason
	if body.bandage_targets.is_empty() and body.bandage.enabled:
		bandage_reason = "No legal Bandage recipient is available."
	_add_bandage_panel(bandage_panel, actor_id, body.bandage_targets)
	var bandage_button := _add_panel_toggle(first_row, "Bandage", bandage_panel, mode_panels, overview, bandage_enabled, bandage_reason)
	_name_command(bandage_button, "Bandage")
	_color_command(bandage_button, VIEW_COMMAND_COLOR)
	_accent_command(_add_fixed_response(second_row, "TurnUndead", "Turn Undead", InteractionResponse.CombatBody.new(&"turn_undead", actor_id), body.turn_undead.enabled, body.turn_undead.reason))
	_color_command(_add_fixed_response(second_row, "Undo", "Undo", InteractionResponse.CombatBody.new(&"undo", actor_id), body.undo.enabled, body.undo.reason), VIEW_COMMAND_COLOR)


func _command_group(parent: Container, group_name: String, heading_text: String, heading_color: Color) -> VBoxContainer:
	var panel := _summary_panel("%sInset" % group_name, 1.0)
	panel.custom_minimum_size.y = COMMAND_GROUP_HEIGHT * _command_scale
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_scaled_command_panels.append(panel)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.name = group_name
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", roundi(COMMAND_COLUMN_SEPARATION * _command_scale))
	_scaled_command_columns.append(column)
	var heading := Label.new()
	heading.text = heading_text.to_upper()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", roundi(COMMAND_FONT_SIZE * _command_scale))
	heading.add_theme_color_override("font_color", heading_color)
	_scaled_command_headings.append(heading)
	column.add_child(heading)
	var divider := HSeparator.new()
	divider.name = "%sDivider" % group_name
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(divider)
	panel.add_child(column)
	return column


func _command_rows(parent: Container, name_prefix: String) -> Array[HBoxContainer]:
	var rows: Array[HBoxContainer] = []
	for suffix: String in ["Primary", "Secondary"]:
		var center := CenterContainer.new()
		center.name = "%s%sCenter" % [name_prefix, suffix]
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(center)
		var row := HBoxContainer.new()
		row.name = "%s%s" % [name_prefix, suffix]
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.add_theme_constant_override("separation", roundi(COMMAND_ROW_SEPARATION * _command_scale))
		_scaled_command_rows.append(row)
		center.add_child(row)
		rows.append(row)
	return rows


func _summary_panel(panel_name: String, stretch_ratio: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.theme_type_variation = &"BattleSummaryInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = stretch_ratio
	panel.clip_contents = true
	return panel


func _build_initiative_panel(round_number: int) -> PanelContainer:
	var panel := _summary_panel("BattleInitiative", 1.55)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	var heading := Label.new()
	heading.text = "Round %d • Turn order" % round_number
	heading.add_theme_color_override("font_color", Color("63d8e7"))
	heading.add_theme_font_size_override("font_size", 10)
	column.add_child(heading)
	var turns := HBoxContainer.new()
	turns.name = "BattleInitiativeOrder"
	turns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turns.add_theme_constant_override("separation", 3)
	column.add_child(turns)
	panel.add_child(column)
	var ordered := _ordered_combatants_from_active()
	for index: int in mini(ordered.size(), MAX_VISIBLE_TURNS):
		var combatant := ordered[index]
		var button := Button.new()
		button.name = "Initiative%s" % combatant.id.to_pascal_case()
		var turn_label := "NOW" if index == 0 else "NEXT" if index == 1 else str(index + 1)
		var icon := _combatant_icons.get(combatant.id) as Texture2D
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
		var combatant_id := combatant.id
		button.pressed.connect(func() -> void:
			inspect_combatant(combatant_id)
			combatant_focus_requested.emit(combatant_id, true)
		)
		turns.add_child(button)
	return panel


func _ordered_combatants_from_active() -> Array[InteractionRequestValue.Combatant]:
	var result: Array[InteractionRequestValue.Combatant] = []
	if _combatants.is_empty():
		return result
	var active_index := 0
	for index: int in _combatants.size():
		if _combatants[index].id == _actor_id:
			active_index = index
			break
	for offset: int in _combatants.size():
		result.append(_combatants[(active_index + offset) % _combatants.size()])
	return result


func _add_fixed_response(parent: Container, command_name: String, label: String, body: InteractionResponse.Body, enabled: bool, reason: String) -> Button:
	var button := add_response_to(parent, label, body, enabled, reason)
	_name_command(button, command_name)
	return button


func _name_command(button: Button, command_name: String) -> void:
	button.name = "CombatCommand%s" % command_name
	button.theme_type_variation = &"BattleCommandButton"
	_register_scaled_command_button(button, Vector2(0.0, COMMAND_HEIGHT))
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _accent_command(button: Button) -> void:
	_color_command(button, PRIMARY_COMMAND_COLOR)


func _color_command(button: Button, color: Color) -> void:
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color.lightened(0.22))


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
		response_body_submitted.emit(InteractionResponse.CombatBody.new(&"bandage", actor_id, target_id))
	)
	parent.add_child(submit)


func _add_panel_toggle(parent: Container, label: String, panel: Control, panels: Array[Control], overview: Control, enabled: bool, reason: String, presentation_sound_id: int = 0) -> Button:
	var button := Button.new()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not enabled
	button.tooltip_text = reason if not enabled else ""
	button.pressed.connect(func() -> void:
		var should_show := not panel.visible
		for candidate: Control in panels:
			candidate.visible = should_show and candidate == panel
		overview.visible = not should_show
		if should_show and presentation_sound_id > 0:
			presentation_sound_requested.emit(presentation_sound_id)
	)
	parent.add_child(button)
	return button


func _add_mode_back_button(panel: Container, overview: Control, panels: Array[Control]) -> void:
	var back := Button.new()
	back.name = "BattleModeBack"
	back.text = "Back to battle"
	back.theme_type_variation = &"BattleCommandButton"
	_register_scaled_command_button(back, Vector2(180.0, COMMAND_HEIGHT))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void:
		if _targeting_active:
			combat_targeting_cancel_requested.emit()
		for candidate: Control in panels:
			candidate.visible = false
		overview.visible = true
		if panel == _spell_panel:
			combat_spellbook_closed.emit()
	)
	panel.add_child(back)
	panel.move_child(back, 0)


func _reset_command_scale_targets() -> void:
	_command_shelf = null
	_scaled_command_panels.clear()
	_scaled_command_columns.clear()
	_scaled_command_headings.clear()
	_scaled_command_rows.clear()
	_scaled_command_buttons.clear()


func _register_scaled_command_button(button: Button, base_size: Vector2) -> void:
	button.set_meta(COMMAND_BASE_SIZE_META, base_size)
	if not _scaled_command_buttons.has(button):
		_scaled_command_buttons.append(button)
	_apply_scaled_command_button(button)


func _apply_scaled_command_button(button: Button) -> void:
	if button == null or not is_instance_valid(button) or not button.has_meta(COMMAND_BASE_SIZE_META):
		return
	var base_size := button.get_meta(COMMAND_BASE_SIZE_META) as Vector2
	button.custom_minimum_size = base_size * _command_scale
	button.add_theme_font_size_override("font_size", roundi(COMMAND_FONT_SIZE * _command_scale))


func _apply_command_scale() -> void:
	if _command_shelf != null and is_instance_valid(_command_shelf):
		_command_shelf.add_theme_constant_override("separation", roundi(COMMAND_GROUP_SEPARATION * _command_scale))
	for panel: Control in _scaled_command_panels:
		if is_instance_valid(panel):
			panel.custom_minimum_size.y = COMMAND_GROUP_HEIGHT * _command_scale
	for column: VBoxContainer in _scaled_command_columns:
		if is_instance_valid(column):
			column.add_theme_constant_override("separation", roundi(COMMAND_COLUMN_SEPARATION * _command_scale))
	for heading: Label in _scaled_command_headings:
		if is_instance_valid(heading):
			heading.add_theme_font_size_override("font_size", roundi(COMMAND_FONT_SIZE * _command_scale))
	for row: HBoxContainer in _scaled_command_rows:
		if is_instance_valid(row):
			row.add_theme_constant_override("separation", roundi(COMMAND_ROW_SEPARATION * _command_scale))
	for button: Button in _scaled_command_buttons:
		_apply_scaled_command_button(button)


func _add_hint_to(parent: Container, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("d5b45d"))
	parent.add_child(label)
	return label
