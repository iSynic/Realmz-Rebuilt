## Presents the dynamic battle interaction without owning gameplay state.

class_name BattleInteraction
extends InteractionComponent

## Presents one typed battle request and emits typed combat responses.

const MAX_VISIBLE_TURNS := 6
const COMMAND_HEIGHT := 30.0
const PRESENTATION_COMMAND_HEIGHT := 24.0
const PRIMARY_COMMAND_COLOR := Color("f0ce59")
const VIEW_COMMAND_COLOR := Color("63d8e7")
const TURN_COMMAND_COLOR := Color("8fe080")
const InitiativePanelBuilder := preload("res://src/ui/combat/battle_initiative_panel_builder.gd")

@export var initiative_entry_scene: PackedScene

@export var targeting_controls_scene: PackedScene

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
var _command_scaling := BattleCommandScaleController.new()
var _compact := false


func configure(combatant_icons: Dictionary, command_scale: float = 1.0, compact: bool = false) -> void:
	_combatant_icons = combatant_icons.duplicate()
	set_command_layout(command_scale, compact)


func set_command_layout(command_scale: float, compact: bool) -> void:
	_compact = compact
	var initiative := find_child("BattleInitiative", true, false)
	if initiative != null:
		(initiative.get_node("%Heading") as Label).visible = not compact
	_command_scaling.set_layout(command_scale, compact)


func build(request: InteractionRequest) -> void:
	var body := request.body as CombatRequestBody
	if body == null: return
	var actor_id := body.actor_id
	_actor_id = actor_id
	_command_scaling.reset()
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
	var target_panel := %BattleTargetPanel as VBoxContainer
	var spell_panel := %BattleSpellPanel as VBoxContainer
	_spell_panel = spell_panel
	var scroll_panel := %BattleScrollPanel as VBoxContainer
	var item_panel := %BattleItemPanel as VBoxContainer
	var bandage_panel := %BattleBandagePanel as VBoxContainer
	var inspection_panel := %BattleCombatantInspection as VBoxContainer
	_inspection_panel = inspection_panel
	var mode_panels: Array[Control] = [target_panel, spell_panel, scroll_panel, item_panel, bandage_panel, inspection_panel]
	_mode_panels.assign(mode_panels)
	_spell_casts = body.spell_casts
	_fast_spells = body.fast_spells
	var overview := %BattleOverview as VBoxContainer
	_overview = overview
	_build_combatant_information(body, targets)
	_build_command_shelf(body, actor_id, action_ids, targets, target_panel, spell_panel, scroll_panel, item_panel, bandage_panel, mode_panels, overview)
	for panel: Control in mode_panels:
		panel.visible = false
		_add_mode_back_button(panel, overview, mode_panels)
	_build_attack_panel(body, actor_id, action_ids, targets, target_panel, weapon_mode)
	_build_spell_panel(body, actor_id, action_ids, spell_panel)
	_build_combatant_inspection()
	_build_scroll_panel(body, actor_id, action_ids, scroll_panel)
	_build_item_panel(body, actor_id, action_ids, item_panel)


func _build_scroll_panel(body: CombatRequestBody, actor_id: String, action_ids: Array[String], scroll_panel: VBoxContainer) -> void:
	var scroll_picker := %CombatScrollPicker as OptionButton
	var use_scroll_button := %ChooseScrollTarget as Button
	var unavailable := %ScrollUnavailable as Button
	if action_ids.has("use_scroll") and not body.scroll_casts.is_empty():
		for option: InteractionRequestValue.CastOption in body.scroll_casts:
			var label := "Slot %d • %s • P%d → %s" % [option.scroll_slot + 1, option.spell_name, option.power, option.target_name]
			if option.target_current_health >= 0: label += " (%d/%d HP)" % [option.target_current_health, option.target_maximum_health]
			scroll_picker.add_item(label)
			scroll_picker.set_item_metadata(scroll_picker.item_count - 1, option)
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
		refresh_scroll_button.call(scroll_picker.selected)
	else:
		scroll_picker.visible = false
		use_scroll_button.visible = false
		unavailable.visible = not body.scroll_cast_reason.is_empty()
		unavailable.tooltip_text = body.scroll_cast_reason


func _build_item_panel(body: CombatRequestBody, actor_id: String, action_ids: Array[String], item_panel: VBoxContainer) -> void:
	var item_row := %CombatItemPicker as OptionButton
	var item_picker := item_row
	var use_button := %ChooseItemTarget as Button
	var unavailable := %ItemUnavailable as Button
	if action_ids.has("use_item") and not body.item_casts.is_empty():
		for option: InteractionRequestValue.CastOption in body.item_casts:
			var charge_label := "∞" if option.charges < 0 else str(option.charges)
			var power_label := "Random power" if option.target_mode == &"random_power" else "Rolled P%d" % option.power if option.power_staged else "P%d" % option.power
			var label := "%s (%s) • %s %s → %s" % [option.item_name, charge_label, option.spell_name, power_label, option.target_name]
			if option.target_current_health >= 0: label += " (%d/%d HP)" % [option.target_current_health, option.target_maximum_health]
			item_picker.add_item(label)
			item_picker.set_item_metadata(item_picker.item_count - 1, option)
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
		var refresh_item_button := func(_index: int) -> void:
			var option := item_picker.get_selected_metadata() as InteractionRequestValue.CastOption
			use_button.text = "Roll item power" if option != null and option.target_mode == &"random_power" else "Choose item target" if option != null and option.target_mode != &"automatic" else "Use selected item"
		item_picker.item_selected.connect(refresh_item_button)
		refresh_item_button.call(item_picker.selected)
	else:
		(item_picker.get_parent() as Control).visible = false
		unavailable.visible = not body.item_cast_reason.is_empty()
		unavailable.tooltip_text = body.item_cast_reason


func _build_attack_panel(body: CombatRequestBody, actor_id: String, action_ids: Array[String], targets: Array[InteractionRequestValue.CombatTarget], target_panel: VBoxContainer, weapon_mode: String) -> void:
	var status := %AttackStatus as Label
	var button := %ChooseAttackTarget as Button
	if action_ids.has("attack"):
		var candidate_ids: Array[String] = []
		for target: InteractionRequestValue.CombatTarget in targets:
			if not target.id.is_empty(): candidate_ids.append(target.id)
		var targeting := CombatTargetingRequest.new(&"combatant", InteractionResponse.CombatBody.new(&"attack", actor_id))
		targeting.candidate_ids = candidate_ids
		button.text = "Choose Fire target on battlefield" if weapon_mode == "missile" else "Choose attack target on battlefield"
		button.pressed.connect(func() -> void: _start_targeting(targeting, target_panel))
	elif weapon_mode == "melee" and not body.melee_attack_reason.is_empty():
		button.visible = false
		status.text = body.melee_attack_reason
	if weapon_mode == "missile" and not action_ids.has("attack"):
		button.text = "Fire unavailable"
		button.disabled = true
		button.tooltip_text = body.ranged_attack.reason


func _build_spell_panel(body: CombatRequestBody, actor_id: String, action_ids: Array[String], spell_panel: VBoxContainer) -> void:
	var status := %CombatSpellbookStatus as Label
	var unavailable := %SpellUnavailable as Button
	if not action_ids.has("cast_spell") or body.spell_casts.is_empty():
		status.visible = false
		unavailable.visible = not body.spell_cast_reason.is_empty()
		unavailable.tooltip_text = body.spell_cast_reason
		return


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
	_targeting_controls = targeting_controls_scene.instantiate() as VBoxContainer
	parent.add_child(_targeting_controls)
	_targeting_status_label = _targeting_controls.get_node("%TargetingStatus") as Label
	_targeting_confirm_button = _targeting_controls.get_node("%ConfirmBattleTarget") as Button
	_targeting_confirm_button.text = "Cast spell" if configuration.response_body.action == &"cast_spell" else "Confirm target"
	_targeting_confirm_button.pressed.connect(func() -> void: combat_targeting_confirm_requested.emit())
	var rotate := _targeting_controls.get_node("%RotateBattleTarget") as Button
	rotate.visible = configuration.supports_rotation()
	if rotate.visible:
		rotate.pressed.connect(func() -> void: combat_targeting_rotate_requested.emit())
	var cancel := _targeting_controls.get_node("%CancelBattleTarget") as Button
	cancel.pressed.connect(func() -> void: combat_targeting_cancel_requested.emit())
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


func _build_combatant_information(body: CombatRequestBody, targets: Array[InteractionRequestValue.CombatTarget]) -> void:
	var active_icon := %ActiveCombatantIcon as TextureRect
	active_icon.texture = _combatant_icons.get(_actor_id) as Texture2D
	active_icon.visible = active_icon.texture != null
	var active_label := %ActiveCombatantLabel as Label
	active_label.text = "Active • %s\n%d AT • %d MP • %s • %d enemies" % [_combatant_name(_actor_id), body.attack_units_remaining, body.movement_remaining, String(body.weapon_mode).capitalize(), body.enemies_remaining]
	active_label.tooltip_text = "%s\n%d attack%s • %d movement • %s\nEnemies left • %d" % [_combatant_name(_actor_id), body.attack_units_remaining, "" if body.attack_units_remaining == 1 else "s", body.movement_remaining, String(body.weapon_mode).capitalize(), body.enemies_remaining]
	var initiative_host := %BattleInitiativeHost as MarginContainer
	for child: Node in initiative_host.get_children():
		child.queue_free()
	initiative_host.add_child(_build_initiative_panel(body.round_number))
	_inspected_icon = %InspectedCombatantIcon as TextureRect
	_inspected_label = %InspectedCombatantLabel as Label
	var default_id := _actor_id
	if not targets.is_empty(): default_id = targets[0].id
	inspect_combatant(default_id)
	if _inspected_index < 0 and not _combatants.is_empty():
		_inspected_index = 0
	_refresh_inspected_label()
func _bind_presentation_button(button: Button, text: String, action: StringName) -> void:
	button.name = "CombatPresentation%s" % String(action).to_pascal_case()
	button.text = text
	_command_scaling.register_button(button, Vector2(0.0, PRESENTATION_COMMAND_HEIGHT))
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if action == &"reveal_friends":
		_color_command(button, VIEW_COMMAND_COLOR)
	button.pressed.connect(func() -> void: _perform_presentation_action(action))


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


func _build_combatant_inspection() -> void:
	_inspection_title = %BattleInspectionTitle as Label
	_inspection_buttons.clear()
	var sections: Array[StringName] = [&"items", &"conditions", &"attacks"]
	var buttons: Array[Button] = [%BattleInspectionItems as Button, %BattleInspectionConditions as Button, %BattleInspectionAttacks as Button]
	for index: int in sections.size():
		var section := sections[index]
		var button := buttons[index]
		_command_scaling.register_button(button, Vector2(0.0, PRESENTATION_COMMAND_HEIGHT))
		button.pressed.connect(func() -> void:
			_inspection_section = section
			_refresh_combatant_inspection()
		)
		_inspection_buttons[section] = button
	_inspection_content = %BattleInspectionContent as Label
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


func _combatant_name(combatant_id: String) -> String:
	for combatant: InteractionRequestValue.Combatant in _combatants:
		if combatant.id == combatant_id: return combatant.name
	return combatant_id


func accepts_spatial_input() -> bool:
	for panel: Control in _mode_panels:
		if panel.visible:
			return false
	return true


func _build_command_shelf(body: CombatRequestBody, actor_id: String, action_ids: Array[String], targets: Array[InteractionRequestValue.CombatTarget], target_panel: Control, spell_panel: Control, scroll_panel: Control, item_panel: Control, bandage_panel: Control, mode_panels: Array[Control], overview: Control) -> void:
	var scaled_panels: Array[Control] = [find_child("BattleInspectionCommandsInset", true, false), %BattlePrimaryCommandsInset, find_child("BattleTurnCommandsInset", true, false)]
	var scaled_columns: Array[VBoxContainer] = [find_child("BattleInspectionCommands", true, false), %BattlePrimaryCommands, %BattleTurnCommands]
	var scaled_rows: Array[HBoxContainer] = [%BattleInspectionPrimary, %BattleInspectionSecondary, %BattlePrimaryPrimary, %BattlePrimarySecondary, %BattleTurnPrimary, %BattleTurnSecondary]
	_command_scaling.configure(%BattleCommandShelf as HBoxContainer, scaled_panels, scaled_columns, scaled_rows)
	var inspection_rows: Array[HBoxContainer] = [%BattleInspectionPrimary, %BattleInspectionSecondary]
	_bind_presentation_button(inspection_rows[0].get_node("Previous") as Button, "Previous", &"inspect_previous")
	_bind_presentation_button(inspection_rows[0].get_node("Center") as Button, "Center", &"center_active")
	_bind_presentation_button(inspection_rows[0].get_node("Next") as Button, "Next", &"inspect_next")
	_bind_presentation_button(inspection_rows[1].get_node("RevealFriends") as Button, "Reveal Friends", &"reveal_friends")
	var primary_rows: Array[HBoxContainer] = [%BattlePrimaryPrimary, %BattlePrimarySecondary]
	var can_switch := action_ids.has("switch_weapon") and body.weapon_switch.enabled
	var shown_weapon_mode := String(body.weapon_switch.target_mode) if can_switch else String(body.weapon_mode)
	_bind_fixed_response(primary_rows[0].get_node("Weapon") as Button, "Weapon", "Weapon: %s" % shown_weapon_mode.capitalize(), InteractionResponse.CombatBody.new(&"switch_weapon", actor_id), can_switch, body.weapon_switch.reason)
	var guard := primary_rows[0].get_node("Guard") as Button
	_bind_fixed_response(guard, "Guard", "Guard", InteractionResponse.CombatBody.new(&"defend", actor_id), action_ids.has("defend"), "Guard is unavailable during this activation.")
	_color_command(guard, TURN_COMMAND_COLOR)
	var weapon_mode := String(body.weapon_mode)
	var target_enabled: bool = action_ids.has("attack") and not targets.is_empty()
	var target_reason := body.melee_attack_reason if weapon_mode == "melee" else body.ranged_attack.reason
	var attack_button := primary_rows[0].get_node("Attack") as Button
	_bind_panel_toggle(attack_button, "Fire" if weapon_mode == "missile" else "Attack", target_panel, mode_panels, overview, target_enabled, target_reason)
	_name_command(attack_button, "Attack")
	_accent_command(attack_button)
	var finish_button := primary_rows[0].get_node("Finish") as Button
	_bind_fixed_response(finish_button, "Finish", "Finish", InteractionResponse.CombatBody.new(&"finish", actor_id), action_ids.has("finish"), "Finish is unavailable during this activation.")
	_accent_command(finish_button)
	var spell_button := primary_rows[1].get_node("Spells") as Button
	_bind_panel_toggle(spell_button, "Spells", spell_panel, mode_panels, overview, action_ids.has("cast_spell") and not body.spell_casts.is_empty(), body.spell_cast_reason)
	_name_command(spell_button, "Spells")
	_color_command(spell_button, VIEW_COMMAND_COLOR)
	spell_button.pressed.connect(func() -> void:
		if spell_panel.visible:
			combat_spellbook_requested.emit(actor_id, _spell_casts)
		else:
			combat_spellbook_closed.emit()
	)
	var scroll_button := primary_rows[1].get_node("Scrolls") as Button
	_bind_panel_toggle(scroll_button, "Scrolls", scroll_panel, mode_panels, overview, action_ids.has("use_scroll") and not body.scroll_casts.is_empty(), body.scroll_cast_reason, 647)
	_name_command(scroll_button, "Scrolls")
	_color_command(scroll_button, VIEW_COMMAND_COLOR)
	var item_button := primary_rows[1].get_node("Items") as Button
	_bind_panel_toggle(item_button, "Items", item_panel, mode_panels, overview, action_ids.has("use_item") and not body.item_casts.is_empty(), body.item_cast_reason)
	_name_command(item_button, "Items")
	_color_command(item_button, VIEW_COMMAND_COLOR)
	var turn_rows: Array[HBoxContainer] = [%BattleTurnPrimary, %BattleTurnSecondary]
	_add_classic_turn_commands(turn_rows[0], turn_rows[1], body, actor_id, bandage_panel, mode_panels, overview)
	var retreat_enabled := action_ids.has("retreat") and body.retreat.enabled
	var escape := turn_rows[1].get_node("Escape") as Button
	_bind_fixed_response(escape, "Escape", "Escape", InteractionResponse.CombatBody.new(&"retreat", actor_id), retreat_enabled, body.retreat.reason)
	_accent_command(escape)
	_command_scaling.apply()


func _add_classic_turn_commands(first_row: Container, second_row: Container, body: CombatRequestBody, actor_id: String, bandage_panel: Control, mode_panels: Array[Control], overview: Control) -> void:
	var auto_turn := first_row.get_node("AutoTurn") as Button
	_bind_fixed_response(auto_turn, "AutoTurn", "Auto Turn", InteractionResponse.CombatBody.new(&"auto", actor_id), body.auto_turn.enabled, body.auto_turn.reason)
	_color_command(auto_turn, TURN_COMMAND_COLOR)
	var delay := first_row.get_node("Delay") as Button
	_bind_fixed_response(delay, "Delay", "Delay", InteractionResponse.CombatBody.new(&"delay", actor_id), body.delay.enabled, body.delay.reason)
	_color_command(delay, TURN_COMMAND_COLOR)
	var bandage_enabled := body.bandage.enabled and not body.bandage_targets.is_empty()
	var bandage_reason := body.bandage.reason
	if body.bandage_targets.is_empty() and body.bandage.enabled:
		bandage_reason = "No legal Bandage recipient is available."
	_add_bandage_panel(actor_id, body.bandage_targets)
	var bandage_button := first_row.get_node("Bandage") as Button
	_bind_panel_toggle(bandage_button, "Bandage", bandage_panel, mode_panels, overview, bandage_enabled, bandage_reason)
	_name_command(bandage_button, "Bandage")
	_color_command(bandage_button, VIEW_COMMAND_COLOR)
	var turn_undead := second_row.get_node("TurnUndead") as Button
	_bind_fixed_response(turn_undead, "TurnUndead", "Turn Undead", InteractionResponse.CombatBody.new(&"turn_undead", actor_id), body.turn_undead.enabled, body.turn_undead.reason)
	_accent_command(turn_undead)
	var undo := second_row.get_node("Undo") as Button
	_bind_fixed_response(undo, "Undo", "Undo", InteractionResponse.CombatBody.new(&"undo", actor_id), body.undo.enabled, body.undo.reason)
	_color_command(undo, VIEW_COMMAND_COLOR)


func _build_initiative_panel(round_number: int) -> PanelContainer:
	var panel := InitiativePanelBuilder.build(round_number, _combatants, _actor_id, _combatant_icons, _select_initiative_combatant, MAX_VISIBLE_TURNS, initiative_entry_scene)
	(panel.get_node("%Heading") as Label).visible = not _compact
	return panel


func _select_initiative_combatant(combatant_id: String) -> void:
	inspect_combatant(combatant_id)
	combatant_focus_requested.emit(combatant_id, true)


func _bind_fixed_response(button: Button, command_name: String, label: String, body: InteractionResponse.Body, enabled: bool, reason: String) -> void:
	button.text = label
	button.disabled = not enabled
	button.tooltip_text = reason if not enabled else ""
	button.pressed.connect(func() -> void: response_body_submitted.emit(body))
	_name_command(button, command_name)


func _name_command(button: Button, command_name: String) -> void:
	button.name = "CombatCommand%s" % command_name
	button.theme_type_variation = &"BattleCommandButton"
	_command_scaling.register_button(button, Vector2(0.0, COMMAND_HEIGHT))
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _accent_command(button: Button) -> void:
	_color_command(button, PRIMARY_COMMAND_COLOR)


func _color_command(button: Button, color: Color) -> void:
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color.lightened(0.22))


func _add_bandage_panel(actor_id: String, targets: Array[InteractionRequestValue.CombatTarget]) -> void:
	var picker := %BandageRecipient as OptionButton
	for target: InteractionRequestValue.CombatTarget in targets:
		if not target.id.is_empty():
			picker.add_item("%s • %d HP" % [target.name, target.current_health])
			picker.set_item_metadata(picker.item_count - 1, target.id)
	picker.disabled = picker.item_count == 0
	var submit := %Bandage as Button
	submit.disabled = picker.item_count == 0
	submit.pressed.connect(func() -> void:
		var target_id := String(picker.get_selected_metadata())
		if target_id.is_empty():
			return
		response_body_submitted.emit(InteractionResponse.CombatBody.new(&"bandage", actor_id, target_id))
	)


func _bind_panel_toggle(button: Button, label: String, panel: Control, panels: Array[Control], overview: Control, enabled: bool, reason: String, presentation_sound_id: int = 0) -> void:
	button.text = label
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


func _add_mode_back_button(panel: Container, overview: Control, panels: Array[Control]) -> void:
	var back := panel.get_node("Back") as Button
	back.name = "BattleModeBack"
	_command_scaling.register_button(back, Vector2(180.0, COMMAND_HEIGHT))
	back.pressed.connect(func() -> void:
		if _targeting_active:
			combat_targeting_cancel_requested.emit()
		for candidate: Control in panels:
			candidate.visible = false
		overview.visible = true
		if panel == _spell_panel:
			combat_spellbook_closed.emit()
	)
