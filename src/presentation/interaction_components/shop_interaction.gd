class_name ShopInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	add_hint("Inflation %d%%" % int(request.payload.get("inflationPercent", 100)))
	var picker := character_option(request.payload.get("characters", []))
	add_child(picker)
	add_hint("Buy")
	var stock: Variant = request.payload.get("stock", [])
	if stock is Array:
		for entry: Variant in stock:
			if not entry is Dictionary:
				continue
			var available := int(entry.get("quantity", 0)) > 0 and picker.item_count > 0
			var payload := {"action": "buy", "stockIndex": int(entry.get("index", -1))}
			var button := Button.new()
			button.text = "%s • %d gold • %d left" % [entry.get("name", "Item"), int(entry.get("buyPrice", 0)), int(entry.get("quantity", 0))]
			button.disabled = not available
			button.tooltip_text = "No stock or eligible buyer." if not available else ""
			button.pressed.connect(func() -> void:
				if picker.item_count > 0:
					payload["characterId"] = String(picker.get_selected_metadata())
					payload_submitted.emit(payload)
			)
			add_child(button)
	add_hint("Sell")
	var characters: Variant = request.payload.get("characters", [])
	if characters is Array:
		for character: Variant in characters:
			if not character is Dictionary or not character.get("inventory", []) is Array:
				continue
			for item: Variant in character.get("inventory", []):
				if item is Dictionary:
					add_response("Sell %s (%s) • %d gold" % [item.get("name", "Item"), character.get("name", "Character"), int(item.get("sellPrice", 0))], {"action": "sell", "characterId": String(character.get("id", "")), "instanceId": String(item.get("instanceId", ""))})
	add_response("Leave shop", {"action": "leave"})
