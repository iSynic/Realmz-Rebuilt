## Binds party wealth and scenario services to the authored Services workspace.
class_name ServicesScreenController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)
signal route_requested(screen_id: StringName)
signal refresh_requested

const GOLD := Color("d5b45d")
const TEXT := Color("e0e2e5")
const MUTED := Color("9aa0a8")
const WORKSPACE_SCENE_PATH := "res://src/ui/services/services_workspace.tscn"

var _money_character_id: String = ""
var _text_scale: float = 1.0
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _media: ClassicMediaCatalog
var _workspace: ServicesWorkspace


func set_text_scale(scale: float) -> void:
	_text_scale = maxf(scale, 0.1)


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id


func present(target: Control, view: GameView, media: ClassicMediaCatalog = null) -> void:
	if target == null or view == null:
		return
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
	return true


func _bind_pool(view: GameView, money: MoneyWorkspaceView) -> void:
	var root := _workspace.pool_summary()
	_bind_label(root.get_node("Identity/Heading") as Label, "Party Pool", GOLD, 18)
	_bind_label(
		root.get_node("Identity/Banked") as Label,
		"Banked  %d gold  •  %d gems  •  %d jewelry" % [money.banked_gold, money.banked_gems, money.banked_jewelry],
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
	for character: MoneyCharacterView in money.characters:
		var row := _workspace.money_character_row_scene.instantiate() as MoneyCharacterRow
		row.bind(character, character.character_id == _money_character_id, group)
		row.pressed.connect(_select_money_character.bind(character.character_id))
		_workspace.character_rows().add_child(row)


func _bind_exchange(view: GameView, money: MoneyWorkspaceView) -> void:
	var selected := money.character(_money_character_id)
	var pane := _workspace.swap_pane()
	var exchange_body := pane.get_node("Content/MoneyExchangeScroll/MoneyExchangeBody")
	_bind_label(exchange_body.get_node("Header/Heading") as Label, "Exchange", GOLD, 18)
	_bind_label(exchange_body.get_node("Header/SelectedName") as Label, selected.name, MUTED, 13)
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
	for transfer: MoneyTransferView in selected.transfers:
		_bind_transfer(view, selected, transfer)
	_bind_button(pane.get_node("Content/MoneyDone") as Button, func() -> void: route_requested.emit(&"exploration"))


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


func _bind_transfer(view: GameView, selected: MoneyCharacterView, transfer: MoneyTransferView) -> void:
	var row := _workspace.money_transfer_row_scene.instantiate() as MoneyTransferRow
	row.bind(transfer, selected.name, _media)
	_bind_money_action(
		row.to_pool_button(),
		view,
		transfer.to_pool,
		EconomyIntents.money(&"to-pool", selected.character_id, String(transfer.denomination), transfer.amount)
	)
	_bind_money_action(
		row.to_character_button(),
		view,
		transfer.to_character,
		EconomyIntents.money(&"to-character", selected.character_id, String(transfer.denomination), transfer.amount)
	)
	_workspace.transfer_rows().add_child(row)


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


func _bind_money_action(button: Button, view: GameView, local: ActionAvailabilityView, intent: PlayerIntent) -> void:
	_clear_pressed_connections(button)
	var workspace_availability := view.availability(&"money_action")
	button.disabled = not workspace_availability.enabled or local == null or not local.enabled
	if not workspace_availability.enabled:
		button.tooltip_text = workspace_availability.reason
	elif local == null:
		button.tooltip_text = "This money action is unavailable."
	elif not local.enabled:
		button.tooltip_text = local.reason
	else:
		button.tooltip_text = button.text
		button.pressed.connect(func() -> void: intent_submitted.emit(intent))


func _bind_button(button: Button, action: Callable) -> void:
	_clear_pressed_connections(button)
	button.pressed.connect(action)


func _select_money_character(character_id: String) -> void:
	_money_character_id = character_id
	refresh_requested.emit()


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


func _clear_item_selected_connections(picker: OptionButton) -> void:
	for connection: Dictionary in picker.item_selected.get_connections():
		picker.item_selected.disconnect(connection.callable)
