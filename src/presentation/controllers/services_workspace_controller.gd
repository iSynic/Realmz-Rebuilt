class_name ServicesWorkspaceController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)
signal route_requested(screen_id: StringName)

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")

var _money_character_id: String = ""
var _text_scale: float = 1.0


func set_text_scale(scale: float) -> void:
	_text_scale = maxf(scale, 0.1)


func present(parent: VBoxContainer, view: GameView) -> void:
	if parent == null or view == null:
		return
	_render_money_workspace(parent, view)
	_add_section_heading(parent, "Location services", "%d available" % view.services.size())
	if view.services.is_empty():
		_add_empty_state(parent, "No active service", "Shops, temples, banks, storage, and treasure open here only when the session supplies a typed service interaction.")
		for title: String in ["Shop", "Temple", "Bank", "Storage", "Treasure"]:
			_add_card(parent, title, "Unavailable at this location", "No service facts were supplied; Realmz Rebuilt does not infer availability from the map or scenario name.")
		return
	for service: ServiceView in view.services:
		_add_card(parent, service.title, String(service.service_kind).replace("_", " ").capitalize(), "Available actions: %s" % [", ".join(service.actions)])
		for action: StringName in service.actions:
			var button := Button.new()
			button.text = String(action).capitalize()
			var reason := String(service.disabled_reasons.get(action, ""))
			var availability := view.availability(&"service_action")
			button.disabled = not reason.is_empty() or not availability.enabled
			button.tooltip_text = reason if not reason.is_empty() else availability.reason if not availability.enabled else "Enter %s" % service.title
			if not button.disabled:
				button.pressed.connect(_submit_service_action.bind(service.service_id, action))
			parent.add_child(button)


func _render_money_workspace(parent: VBoxContainer, view: GameView) -> void:
	_add_section_heading(parent, "Money", "Classic Pool, Share, and Swap")
	var workspace := view.money_workspace
	if workspace == null:
		_add_empty_state(parent, "Money management unavailable", "Begin the adventure before pooling or transferring wealth.")
		return
	_add_card(parent, "Party pool", "%d gold • %d gems • %d jewelry" % [workspace.pooled_gold, workspace.pooled_gems, workspace.pooled_jewelry], "Banked: %d gold • %d gems • %d jewelry" % [workspace.banked_gold, workspace.banked_gems, workspace.banked_jewelry])
	var party_actions := HFlowContainer.new()
	party_actions.add_theme_constant_override("h_separation", 5)
	party_actions.add_theme_constant_override("v_separation", 5)
	_add_money_intent_action(party_actions, view, "Pool party wealth", workspace.pool, PlayerIntent.money_action(&"pool"))
	_add_money_intent_action(party_actions, view, "Share pooled wealth", workspace.share, PlayerIntent.money_action(&"share"))
	parent.add_child(party_actions)
	if workspace.characters.is_empty():
		_add_empty_state(parent, "No adventurers", "A party member is required for Classic Swap.")
		return
	if workspace.character(_money_character_id) == null:
		_money_character_id = workspace.characters[0].character_id
	var selector := OptionButton.new()
	selector.tooltip_text = "Choose the adventurer whose carried wealth will be exchanged with the party pool."
	for character: MoneyCharacterView in workspace.characters:
		selector.add_item("%s • Load %d/%d" % [character.name, character.carried_load, character.maximum_load])
		selector.set_item_metadata(selector.item_count - 1, character.character_id)
		if character.character_id == _money_character_id:
			selector.select(selector.item_count - 1)
	selector.item_selected.connect(func(index: int) -> void:
		_money_character_id = String(selector.get_item_metadata(index))
		_present_again(parent, view)
	)
	parent.add_child(selector)
	var selected := workspace.character(_money_character_id)
	_add_card(parent, selected.name, "%d gold • %d gems • %d jewelry" % [selected.gold, selected.gems, selected.jewelry], "Carried load %d/%d" % [selected.carried_load, selected.maximum_load])
	for transfer: MoneyTransferView in selected.transfers:
		var denomination_label := String(transfer.denomination).capitalize()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var label := _label("%s • %d per step" % [denomination_label, transfer.amount], MUTED, 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_add_money_intent_action(row, view, "To pool", transfer.to_pool, PlayerIntent.money_action(&"to-pool", selected.character_id, String(transfer.denomination), transfer.amount))
		_add_money_intent_action(row, view, "To %s" % selected.name, transfer.to_character, PlayerIntent.money_action(&"to-character", selected.character_id, String(transfer.denomination), transfer.amount))
		parent.add_child(row)
	var done := Button.new()
	done.text = "Done"
	done.tooltip_text = "Return to exploration without another money mutation."
	done.pressed.connect(func() -> void: route_requested.emit(&"exploration"))
	parent.add_child(done)


func _present_again(parent: VBoxContainer, view: GameView) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	present(parent, view)


func _add_money_intent_action(parent: Container, view: GameView, label: String, local_availability: ActionAvailabilityView, intent: PlayerIntent) -> Button:
	var button := Button.new()
	button.text = label
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
	_add_card(parent, title, detail, "Realmz Rebuilt shows only facts supplied by the detached session view.")


func _add_card(parent: Container, title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 280.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	column.add_child(_label(title, GOLD, 16))
	if not subtitle.is_empty():
		column.add_child(_label(subtitle, MUTED, 13))
	if not detail.is_empty():
		var body := _label(detail, Color.WHITE, 14)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(body)
	parent.add_child(panel)


func _label(text: String, color: Color, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", int(round(float(size) * _text_scale)))
	return result
