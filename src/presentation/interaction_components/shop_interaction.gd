class_name ShopInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.ShopRequestBody
	if body == null: return
	add_hint("Party gold: %d • Shop rate: %d%%" % [body.party_gold, body.inflation_percent])
	var picker := character_option(body.characters)
	add_child(picker)
	add_hint("Buy")
	for entry: InteractionRequestValue.ShopStock in body.stock:
		var available := entry.can_buy and picker.item_count > 0
		var payload := {"action": "buy", "stockKey": entry.stock_key, "stockIndex": entry.index}
		var button := Button.new()
		button.text = "%s • %d gold • %d left" % [entry.name, entry.buy_price, entry.quantity]
		button.disabled = not available
		button.tooltip_text = entry.buy_reason if not available else ""
		button.pressed.connect(func() -> void:
			if picker.item_count > 0:
				payload["characterId"] = String(picker.get_selected_metadata())
				payload_submitted.emit(payload)
		)
		add_child(button)
	add_hint("Sell")
	for character: InteractionRequestValue.ServiceCharacter in body.characters:
		for item: InteractionRequestValue.InventoryItem in character.inventory:
			add_response("Sell %s (%s) • %d gold" % [item.name, character.name, item.sell_price], {"action": "sell", "characterId": character.id, "instanceId": item.instance_id}, item.can_sell, item.sell_reason)
			if not item.identified:
				add_response("Identify %s (%s) • %d gold" % [item.name, character.name, body.identify_price], {"action": "identify", "characterId": character.id, "instanceId": item.instance_id}, item.can_identify, item.identify_reason)
	add_response("Leave shop", {"action": "leave"})
