class_name ServicesWorkspaceController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)
signal route_requested(screen_id: StringName)
signal refresh_requested

const GOLD := Color("d5b45d")
const TEXT := Color("e0e2e5")
const MUTED := Color("9aa0a8")

var _money_character_id: String = ""
var _text_scale: float = 1.0
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _media: ClassicMediaCatalog


func set_text_scale(scale: float) -> void:
	_text_scale = maxf(scale, 0.1)


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id


func present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog = null) -> void:
	if parent == null or view == null:
		return
	_media = media
	_render_money_workspace(parent, view)
	if not view.services.is_empty():
		_render_location_services(parent, view)


func _render_money_workspace(parent: VBoxContainer, view: GameView) -> void:
	var workspace := view.money_workspace
	if workspace == null:
		_add_empty_state(parent, "Party wealth unavailable", "Begin the adventure before pooling or transferring wealth.")
		return
	if workspace.characters.is_empty():
		_add_empty_state(parent, "No adventurers", "A party member is required for Pool, Share, or Swap.")
		return
	if workspace.character(_money_character_id) == null:
		_money_character_id = workspace.characters[0].character_id
	var workspace_column := VBoxContainer.new()
	workspace_column.name = "MoneyWorkspaceColumns"
	workspace_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_column.add_theme_constant_override("separation", 8)
	workspace_column.add_child(_build_pool_pane(view, workspace))
	var exchange := BoxContainer.new()
	exchange.name = "MoneyExchangeWorkspace"
	exchange.vertical = _layout_profile == UiLayoutProfile.COMPACT
	exchange.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exchange.size_flags_vertical = Control.SIZE_EXPAND_FILL
	exchange.add_theme_constant_override("separation", 8)
	if _layout_profile != UiLayoutProfile.COMPACT:
		exchange.add_child(_build_party_pane(workspace))
	exchange.add_child(_build_swap_pane(view, workspace))
	workspace_column.add_child(exchange)
	parent.add_child(workspace_column)


func _build_pool_pane(view: GameView, workspace: MoneyWorkspaceView) -> PanelContainer:
	var panel := _pane("MoneyPoolPane", 1.0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var column := _pane_column(panel)
	var summary := BoxContainer.new()
	summary.name = "MoneyPoolSummary"
	summary.vertical = _layout_profile == UiLayoutProfile.COMPACT
	summary.add_theme_constant_override("separation", 8)
	column.add_child(summary)
	var identity := VBoxContainer.new()
	identity.custom_minimum_size.x = 180.0
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_section_heading(identity, "Party Pool")
	var banked := _label("Banked  %d gold  •  %d gems  •  %d jewelry" % [workspace.banked_gold, workspace.banked_gems, workspace.banked_jewelry], MUTED, 12)
	banked.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_child(banked)
	summary.add_child(identity)
	var values := HBoxContainer.new()
	values.name = "MoneyPoolValues"
	values.add_theme_constant_override("separation", 6)
	values.add_child(_wealth_chip(&"gold", workspace.pooled_gold))
	values.add_child(_wealth_chip(&"gems", workspace.pooled_gems))
	values.add_child(_wealth_chip(&"jewelry", workspace.pooled_jewelry))
	summary.add_child(values)
	var actions := HBoxContainer.new()
	actions.name = "MoneyPoolActions"
	actions.size_flags_horizontal = Control.SIZE_SHRINK_END
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 5)
	_add_money_intent_action(actions, view, "Pool", workspace.pool, PlayerIntent.money_action(&"pool"))
	_add_money_intent_action(actions, view, "Share", workspace.share, PlayerIntent.money_action(&"share"))
	summary.add_child(actions)
	return panel


func _build_party_pane(workspace: MoneyWorkspaceView) -> PanelContainer:
	var panel := _pane("MoneyPartyPane", 1.12)
	var column := _pane_column(panel)
	_add_section_heading(column, "Adventurers", "%d" % workspace.characters.size())
	var group := ButtonGroup.new()
	for character: MoneyCharacterView in workspace.characters:
		var button := Button.new()
		button.text = "%s\n%d gold  •  %d gems  •  %d jewelry  •  Load %d/%d" % [character.name, character.gold, character.gems, character.jewelry, character.carried_load, character.maximum_load]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = character.character_id == _money_character_id
		button.theme_type_variation = &"ClassicMoneyLedgerButton"
		button.custom_minimum_size.y = 48.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_money_character.bind(character.character_id))
		column.add_child(button)
	return panel


func _build_swap_pane(view: GameView, workspace: MoneyWorkspaceView) -> PanelContainer:
	var selected := workspace.character(_money_character_id)
	var panel := _pane("MoneySwapPane", 1.0)
	var column := _pane_column(panel)
	_add_section_heading(column, "Exchange", selected.name)
	if _layout_profile == UiLayoutProfile.COMPACT:
		column.add_child(_character_picker(workspace))
	var current := HBoxContainer.new()
	current.name = "MoneySelectedSummary"
	current.add_theme_constant_override("separation", 6)
	current.add_child(_wealth_chip(&"gold", selected.gold))
	current.add_child(_wealth_chip(&"gems", selected.gems))
	current.add_child(_wealth_chip(&"jewelry", selected.jewelry))
	var load := _label("Carried load\n%d / %d" % [selected.carried_load, selected.maximum_load], MUTED, 12)
	load.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	current.add_child(load)
	column.add_child(current)
	var transfers := VBoxContainer.new()
	transfers.name = "MoneyTransferGrid"
	transfers.add_theme_constant_override("separation", 6)
	for transfer: MoneyTransferView in selected.transfers:
		transfers.add_child(_build_transfer_row(view, selected, transfer))
	column.add_child(transfers)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var done := Button.new()
	done.name = "MoneyDone"
	done.text = "Done"
	done.tooltip_text = "Return to exploration without another money mutation."
	done.custom_minimum_size.y = 38.0
	done.pressed.connect(func() -> void: route_requested.emit(&"exploration"))
	column.add_child(done)
	return panel


func _character_picker(workspace: MoneyWorkspaceView) -> OptionButton:
	var selector := OptionButton.new()
	selector.tooltip_text = "Choose the adventurer whose carried wealth will be exchanged with the party pool."
	for character: MoneyCharacterView in workspace.characters:
		selector.add_item("%s  •  Load %d/%d" % [character.name, character.carried_load, character.maximum_load])
		selector.set_item_metadata(selector.item_count - 1, character.character_id)
		if character.character_id == _money_character_id:
			selector.select(selector.item_count - 1)
	selector.item_selected.connect(func(index: int) -> void: _select_money_character(String(selector.get_item_metadata(index))))
	return selector


func _add_wealth_record(parent: Container, gold: int, gems: int, jewelry: int) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	for record: Array in [["Gold", gold], ["Gems", gems], ["Jewelry", jewelry]]:
		grid.add_child(_label(String(record[0]), MUTED, 13))
		var value := _label(str(record[1]), TEXT, 15)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
	parent.add_child(grid)


func _wealth_chip(denomination: StringName, value: int) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"ClassicInset"
	chip.custom_minimum_size.x = 104.0
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	chip.add_child(row)
	row.add_child(_wealth_icon(denomination))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	row.add_child(column)
	var heading := _label(String(denomination).capitalize(), MUTED, 11)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var amount := _label(str(value), TEXT, 17)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(amount)
	return chip


func _build_transfer_row(view: GameView, selected: MoneyCharacterView, transfer: MoneyTransferView) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var denomination := String(transfer.denomination).capitalize()
	row.add_child(_wealth_icon(transfer.denomination))
	var label := _label("%s  ×%d" % [denomination, transfer.amount], TEXT, 13)
	label.custom_minimum_size.x = 104.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_add_money_intent_action(row, view, "To pool", transfer.to_pool, PlayerIntent.money_action(&"to-pool", selected.character_id, String(transfer.denomination), transfer.amount))
	_add_money_intent_action(row, view, "To %s" % selected.name, transfer.to_character, PlayerIntent.money_action(&"to-character", selected.character_id, String(transfer.denomination), transfer.amount))
	return panel


func _wealth_icon(denomination: StringName) -> ClassicContentIcon:
	var icon := ClassicContentIcon.new()
	icon.name = "Money%sIcon" % String(denomination).capitalize()
	icon.configure("cicn", wealth_resource_id(denomination), _media, 32.0, String(denomination).capitalize(), "Classic wealth image unavailable")
	return icon


static func wealth_resource_id(denomination: StringName) -> int:
	match denomination:
		&"gold":
			return 2002
		&"gems":
			return 2011
		&"jewelry":
			return 2012
	return 0


func _render_location_services(parent: VBoxContainer, view: GameView) -> void:
	var panel := _pane("LocationServicePane", 1.0)
	var column := _pane_column(panel)
	_add_section_heading(column, "At this location")
	for service: ServiceView in view.services:
		var row := HBoxContainer.new()
		var title := _label(service.title, GOLD, 15)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		for action: StringName in service.actions:
			var button := Button.new()
			button.text = String(action).capitalize()
			var reason := String(service.disabled_reasons.get(action, ""))
			var availability := view.availability(&"service_action")
			button.disabled = not reason.is_empty() or not availability.enabled
			button.tooltip_text = reason if not reason.is_empty() else availability.reason if not availability.enabled else "Enter %s" % service.title
			if not button.disabled:
				button.pressed.connect(_submit_service_action.bind(service.service_id, action))
			row.add_child(button)
		column.add_child(row)
	parent.add_child(panel)


func _select_money_character(character_id: String) -> void:
	_money_character_id = character_id
	refresh_requested.emit()


func _add_money_intent_action(parent: Container, view: GameView, label: String, local_availability: ActionAvailabilityView, intent: PlayerIntent) -> Button:
	var button := Button.new()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var workspace_availability := view.availability(&"money_action")
	button.disabled = not workspace_availability.enabled or local_availability == null or not local_availability.enabled
	if not workspace_availability.enabled:
		button.tooltip_text = workspace_availability.reason
	elif local_availability == null:
		button.tooltip_text = "This money action is unavailable."
	elif not local_availability.enabled:
		button.tooltip_text = local_availability.reason
	else:
		button.pressed.connect(func() -> void: intent_submitted.emit(intent))
	parent.add_child(button)
	return button


func _submit_service_action(service_id: String, action: StringName) -> void:
	intent_submitted.emit(PlayerIntent.service_action(service_id, action))


func _pane(panel_name: String, ratio: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	return panel


func _pane_column(panel: PanelContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	return column


func _add_section_heading(parent: Container, title: String, detail: String = "") -> void:
	var row := HBoxContainer.new()
	var heading := _label(title, GOLD, 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not detail.is_empty():
		var note := _label(detail, MUTED, 13)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(note)
	parent.add_child(row)


func _add_empty_state(parent: Container, title: String, detail: String) -> void:
	var panel := _pane("MoneyEmptyState", 1.0)
	var column := _pane_column(panel)
	column.add_child(_label(title, GOLD, 16))
	var message := _label(detail, MUTED, 13)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	parent.add_child(panel)


func _label(text: String, color: Color, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", int(round(float(size) * _text_scale)))
	return result
