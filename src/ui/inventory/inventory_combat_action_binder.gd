## Binds the combat-specific action deck for the shared Inventory workspace.
class_name InventoryCombatActionBinder
extends RefCounted

var _scene_binding := InventorySceneBinding.new()


func bind(panel: InventoryActionPanel, item: ItemView, character: CharacterView, response: Callable, item_use: Callable) -> void:
	panel.show_actions(false)
	var equipped_label := "Unequip" if item.equipped else "Equip"
	_bind_response(panel.action_button("EquippedAction"), &"inventory.action.equipped", equipped_label, item.actions.unequip if item.equipped else item.actions.equip, &"unequip_item" if item.equipped else &"equip_item", item, character, response)
	var use_button := panel.action_button("UseAction")
	_bind_bitmap_button(use_button, &"inventory.action.use", "Use")
	use_button.disabled = item.actions.use == null or not item.actions.use.enabled
	use_button.tooltip_text = "Unavailable" if item.actions.use == null else item.actions.use.reason if not item.actions.use.enabled else "Choose a combat target."
	if not use_button.disabled:
		use_button.command_requested.connect(func(_command_id: StringName) -> void: item_use.call(character.id, item.instance_id))
	var identify := InteractionResponse.CombatBody.new(&"identify_item", item.actions.identify_caster_id, character.id)
	identify.spell_id = item.actions.identify_spell_id
	_bind_body(panel.action_button("IdentifyAction"), &"inventory.action.identify", "Identify All", item.actions.identify, identify, response)
	var trade := panel.action_button("TradeAction")
	_bind_bitmap_button(trade, &"inventory.action.trade", "Trade")
	trade.disabled = true
	trade.tooltip_text = "Trade is unavailable during battle."
	_bind_response(panel.action_button("JoinAction"), &"inventory.action.join", "Join", item.actions.join, &"join_item", item, character, response)
	_bind_response(panel.action_button("SplitAction"), &"inventory.action.split", "Split", item.actions.split, &"split_item", item, character, response)
	_bind_response(panel.action_button("DropAction"), &"inventory.action.drop", "Drop", item.actions.drop, &"drop_item", item, character, response)
	panel.trade_status().visible = false


func _bind_response(button: ClassicBitmapButton, asset_id: StringName, label: String, availability: ActionAvailabilityView, action: StringName, item: ItemView, character: CharacterView, response: Callable) -> void:
	var body := InteractionResponse.CombatBody.new(action, character.id)
	body.item_instance_id = item.instance_id
	_bind_body(button, asset_id, label, availability, body, response)


func _bind_body(button: ClassicBitmapButton, asset_id: StringName, label: String, availability: ActionAvailabilityView, body: InteractionResponse.CombatBody, response: Callable) -> void:
	_bind_bitmap_button(button, asset_id, label)
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else label
	if not button.disabled:
		button.command_requested.connect(func(_command_id: StringName) -> void: response.call(body))


func _bind_bitmap_button(button: ClassicBitmapButton, asset_id: StringName, label: String) -> void:
	_scene_binding.clear_command_connections(button)
	button.configure({"id": asset_id, "asset_id": &"", "label": label, "tooltip": label, "accelerator": ""}, 1)
