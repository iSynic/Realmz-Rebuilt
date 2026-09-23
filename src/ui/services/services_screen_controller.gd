## Binds party wealth and scenario services to the authored Services workspace.
class_name ServicesScreenController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)
signal route_requested(screen_id: StringName)
signal refresh_requested
signal back_requested

const GOLD := Color("d5b45d")
const TEXT := Color("e0e2e5")
const MUTED := Color("9aa0a8")
const WORKSPACE_SCENE_PATH := "res://src/ui/services/services_workspace.tscn"
const MONEY_REPEAT_DELAY := 0.35
const MONEY_REPEAT_INTERVAL := 0.09

var _money_character_id: String = ""
var _text_scale: float = 1.0
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _media: ClassicMediaCatalog
var _workspace: ServicesWorkspace
var _browse_only_reason: String = ""
var _return_to_shop := false
var _held_button: Button
var _held_intent: PlayerIntent


func set_text_scale(scale: float) -> void:
	_text_scale = maxf(scale, 0.1)


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id


func selected_character_id() -> String:
	return _money_character_id


func set_selected_character_id(character_id: String) -> void:
	_money_character_id = character_id


func present(target: Control, view: GameView, media: ClassicMediaCatalog = null) -> void:
	_browse_only_reason = ""
	_return_to_shop = false
	_present(target, view, media, true)


func present_browse(target: Control, view: GameView, media: ClassicMediaCatalog, reason: String) -> void:
	_browse_only_reason = reason
	_return_to_shop = true
	_present(target, view, media, false)


func present_shop(target: Control, view: GameView, media: ClassicMediaCatalog) -> void:
	_browse_only_reason = ""
	_return_to_shop = true
	_present(target, view, media, false)


func _present(target: Control, view: GameView, media: ClassicMediaCatalog, include_location_services: bool) -> void:
	if target == null or view == null:
		return
	if _held_button != null and (target as ServicesScreen == null or (target as ServicesScreen).workspace() != _workspace):
		_stop_repeat()
	_media = media
	var screen := target as ServicesScreen
	if screen != null:
		screen.prepare_for_render(_layout_profile == UiLayoutProfile.COMPACT)
		_workspace = screen.workspace()
	else:
		var parent := target as VBoxContainer
		_clear(parent)
		_workspace = (load(WORKSPACE_SCENE_PATH) as PackedScene).instantiate() as ServicesWorkspace
		parent.add_child(_workspace)
		_workspace.prepare(_layout_profile == UiLayoutProfile.COMPACT)
	if not _bind_money_workspace(view):
		return
	if include_location_services:
		_bind_location_services(view)


func _bind_money_workspace(view: GameView) -> bool:
	var money := view.money_workspace
	if money == null:
		_workspace.show_alternate("Party wealth unavailable", "Begin the adventure before pooling or transferring wealth.")
		return false
	if money.characters.is_empty():
		_workspace.show_alternate("No adventurers", "A party member is required for Pool, Share, or Swap.")
		return false
	if money.character(_money_character_id) == null:
		_money_character_id = money.characters[0].character_id
	_bind_pool(view, money)
	_bind_party(money)
	_bind_exchange(view, money)
	_bind_changing(view, money)
	return true


func _bind_pool(view: GameView, money: MoneyWorkspaceView) -> void:
	var root := _workspace.pool_summary()
	_bind_label(root.get_node("Identity/Heading") as Label, "Party Pool", GOLD, 18)
	_bind_label(
		root.get_node("Identity/Banked") as Label,
		"Banked separately: %d gold  •  %d gems  •  %d jewelry" % [money.banked_gold, money.banked_gems, money.banked_jewelry],
		MUTED,
		12
	)
	_bind_wealth_chips(
		root.get_node("MoneyPoolValues"),
		money.pooled_gold,
		money.pooled_gems,
		money.pooled_jewelry
	)
	_bind_money_action(
		root.get_node("MoneyPoolActions/Pool") as Button,
		view,
		money.pool,
		EconomyIntents.money(&"pool")
	)
	_bind_money_action(
		root.get_node("MoneyPoolActions/Share") as Button,
		view,
		money.share,
		EconomyIntents.money(&"share")
	)


func _bind_party(money: MoneyWorkspaceView) -> void:
	var pane := _workspace.party_pane()
	_bind_label(pane.get_node("Content/Header/Heading") as Label, "Adventurers", GOLD, 18)
	_bind_label(pane.get_node("Content/Header/Count") as Label, str(money.characters.size()), MUTED, 13)
	var group := ButtonGroup.new()
	for index in money.characters.size():
		var character := money.characters[index]
		var row := _workspace.character_rows().get_child(index) as MoneyCharacterRow if index < _workspace.character_rows().get_child_count() else null
		if row == null:
			row = _workspace.money_character_row_scene.instantiate() as MoneyCharacterRow
			_workspace.character_rows().add_child(row)
		row.bind(character, character.character_id == _money_character_id, group, _media)
		_clear_pressed_connections(row)
		row.pressed.connect(_select_money_character.bind(character.character_id))
	while _workspace.character_rows().get_child_count() > money.characters.size():
		var extra := _workspace.character_rows().get_child(_workspace.character_rows().get_child_count() - 1)
		_workspace.character_rows().remove_child(extra)
		extra.queue_free()


func _bind_exchange(view: GameView, money: MoneyWorkspaceView) -> void:
	var selected := money.character(_money_character_id)
	var pane := _workspace.swap_pane()
	var exchange_body := pane.get_node("Content/MoneyExchangeScroll/MoneyExchangeBody")
	_bind_label(exchange_body.get_node("Header/Heading") as Label, "Give or take wealth", GOLD, 18)
	_bind_label(exchange_body.get_node("Header/SelectedName") as Label, selected.name, MUTED, 13)
	(exchange_body.get_node("Header/SelectedPortrait") as TextureRect).texture = _media.image_texture(_media.asset_by_id(selected.portrait_id)) if _media != null else null
	_bind_character_picker(money)
	_bind_wealth_chips(
		_workspace.selected_summary(),
		selected.gold,
		selected.gems,
		selected.jewelry
	)
	_bind_label(
		exchange_body.get_node("MoneySelectedSummary/Load") as Label,
		"Carried load\n%d / %d" % [selected.carried_load, selected.maximum_load],
		MUTED,
		12
	)
	for index in selected.transfers.size():
		_bind_transfer(view, money, selected, selected.transfers[index], index)
	var done := _workspace.done_button()
	done.text = "Back to shop" if _return_to_shop else "Done"
	_bind_button(done, func() -> void:
		if _return_to_shop:
			back_requested.emit()
		else:
			route_requested.emit(&"exploration")
	)


func _bind_character_picker(money: MoneyWorkspaceView) -> void:
	var picker := _workspace.character_picker()
	_clear_item_selected_connections(picker)
	picker.clear()
	for character: MoneyCharacterView in money.characters:
		picker.add_item("%s  •  Load %d/%d" % [character.name, character.carried_load, character.maximum_load])
		picker.set_item_metadata(picker.item_count - 1, character.character_id)
		if character.character_id == _money_character_id:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void: _select_money_character(String(picker.get_item_metadata(index))))


func _bind_wealth_chips(root: Node, gold: int, gems: int, jewelry: int) -> void:
	var values := {&"gold": gold, &"gems": gems, &"jewelry": jewelry}
	for denomination: StringName in values:
		var chip := root.get_node(String(denomination).capitalize()) as WealthChip
		chip.bind(denomination, int(values[denomination]), _media)


func _bind_transfer(view: GameView, money: MoneyWorkspaceView, selected: MoneyCharacterView, transfer: MoneyTransferView, index: int) -> void:
	var row := _workspace.transfer_rows().get_child(index) as MoneyTransferRow if index < _workspace.transfer_rows().get_child_count() else null
	if row == null:
		row = _workspace.money_transfer_row_scene.instantiate() as MoneyTransferRow
		_workspace.transfer_rows().add_child(row)
	var carried: int = selected.gold if transfer.denomination == &"gold" else selected.gems if transfer.denomination == &"gems" else selected.jewelry
	row.bind(transfer, money.pooled_amount(transfer.denomination), carried, _media)
	_bind_money_action(
		row.to_pool_button(),
		view,
		transfer.to_pool,
		EconomyIntents.money(&"to-pool", selected.character_id, String(transfer.denomination), transfer.amount),
		true
	)
	_bind_money_action(
		row.to_character_button(),
		view,
		transfer.to_character,
		EconomyIntents.money(&"to-character", selected.character_id, String(transfer.denomination), transfer.amount),
		true
	)


func _bind_changing(view: GameView, money: MoneyWorkspaceView) -> void:
	var status := _workspace.changing_pane().get_node("Content/Header/Status") as Label
	var available := money.changing_available and _browse_only_reason.is_empty()
	_bind_label(status, "Available here · converts pooled wealth" if available and _return_to_shop else "Available here · converts pooled wealth · hold to repeat" if available else _browse_only_reason if not _browse_only_reason.is_empty() else "Money changing is unavailable here", Color("79cfa9") if available else MUTED, 13)
	var buttons := _workspace.changing_buttons()
	for index in mini(buttons.size(), money.changes.size()):
		var rate := money.changes[index]
		var button := buttons[index]
		button.text = "%s → %s\n%d %s → +%d %s\n%s" % [String(rate.source).capitalize(), String(rate.result).capitalize(), rate.source_amount, _unit(rate.source, rate.source_amount), rate.result_amount, _unit(rate.result, rate.result_amount), "Change" if available and _return_to_shop and rate.availability.enabled else "Change · hold to repeat" if available and rate.availability.enabled else "Unavailable here"]
		_bind_money_action(button, view, rate.availability, EconomyIntents.money(rate.action, "", String(rate.source), rate.source_amount), true)


static func _unit(denomination: StringName, amount: int) -> String:
	if denomination == &"gems" and amount == 1:
		return "gem"
	return String(denomination)


func _bind_location_services(view: GameView) -> void:
	if view.services.is_empty():
		return
	_workspace.location_services_pane().visible = true
	for service: ServiceView in view.services:
		var row := _workspace.location_service_row_scene.instantiate() as LocationServiceRow
		row.bind(service.title)
		for action: StringName in service.actions:
			var button := _workspace.service_action_button_scene.instantiate() as Button
			button.text = String(action).capitalize()
			var reason := String(service.disabled_reasons.get(action, ""))
			var availability := view.availability(&"service_action")
			button.disabled = not reason.is_empty() or not availability.enabled
			button.tooltip_text = reason if not reason.is_empty() else availability.reason if not availability.enabled else "Enter %s" % service.title
			if not button.disabled:
				button.pressed.connect(_submit_service_action.bind(service.service_id, action))
			row.action_host().add_child(button)
		_workspace.location_service_rows().add_child(row)


func _bind_money_action(button: Button, view: GameView, local: ActionAvailabilityView, intent: PlayerIntent, repeat_while_held: bool = false) -> void:
	_clear_pressed_connections(button)
	_clear_repeat_connections(button)
	repeat_while_held = repeat_while_held and not _return_to_shop
	if not _browse_only_reason.is_empty():
		button.disabled = true
		button.tooltip_text = _browse_only_reason
		return
	var workspace_availability := view.availability(&"money_action")
	if _return_to_shop and _browse_only_reason.is_empty() and view.pending_interaction != null and view.pending_interaction.kind == InteractionRequest.SHOP:
		workspace_availability = ActionAvailabilityView.new(&"money_action", true)
	button.disabled = not workspace_availability.enabled or local == null or not local.enabled
	if not workspace_availability.enabled:
		button.tooltip_text = workspace_availability.reason
	elif local == null:
		button.tooltip_text = "This money action is unavailable."
	elif not local.enabled:
		button.tooltip_text = local.reason
	else:
		button.tooltip_text = "%s · Hold to repeat" % button.text if repeat_while_held else button.text
		if repeat_while_held:
			button.button_down.connect(_start_repeat.bind(button, intent))
			button.button_up.connect(_stop_repeat)
		else:
			button.pressed.connect(func() -> void: intent_submitted.emit(intent))
	if button == _held_button and button.disabled:
		_stop_repeat()


func _bind_button(button: Button, action: Callable) -> void:
	_clear_pressed_connections(button)
	button.pressed.connect(action)


func _select_money_character(character_id: String) -> void:
	_stop_repeat()
	_money_character_id = character_id
	refresh_requested.emit()


func _start_repeat(button: Button, intent: PlayerIntent) -> void:
	_stop_repeat()
	_held_button = button
	_held_intent = intent
	var timer := _workspace.repeat_timer()
	if not timer.timeout.is_connected(_repeat_step):
		timer.timeout.connect(_repeat_step)
	intent_submitted.emit(intent)
	if _held_button == button and not button.disabled and timer.is_inside_tree():
		timer.start(MONEY_REPEAT_DELAY)


func _repeat_step() -> void:
	if not is_instance_valid(_held_button) or _held_button.disabled or not _held_button.is_visible_in_tree():
		_stop_repeat()
		return
	intent_submitted.emit(_held_intent)
	if is_instance_valid(_held_button) and not _held_button.disabled and _workspace.repeat_timer().is_inside_tree():
		_workspace.repeat_timer().start(MONEY_REPEAT_INTERVAL)


func _stop_repeat() -> void:
	if _workspace != null and is_instance_valid(_workspace):
		_workspace.repeat_timer().stop()
	_held_button = null
	_held_intent = null


func _submit_service_action(service_id: String, action: StringName) -> void:
	intent_submitted.emit(EconomyIntents.service(service_id, action))


static func wealth_resource_id(denomination: StringName) -> int:
	match denomination:
		&"gold":
			return 2002
		&"gems":
			return 2011
		&"jewelry":
			return 2012
	return 0


func _bind_label(label: Label, text: String, color: Color, base_size: int) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(base_size) * _text_scale)))


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _clear_pressed_connections(button: BaseButton) -> void:
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection.callable)


func _clear_repeat_connections(button: BaseButton) -> void:
	for connection: Dictionary in button.button_down.get_connections():
		button.button_down.disconnect(connection.callable)
	for connection: Dictionary in button.button_up.get_connections():
		button.button_up.disconnect(connection.callable)


func _clear_item_selected_connections(picker: OptionButton) -> void:
	for connection: Dictionary in picker.item_selected.get_connections():
		picker.item_selected.disconnect(connection.callable)
