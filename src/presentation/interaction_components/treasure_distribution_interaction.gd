class_name TreasureDistributionInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	if request.payload.get("mode") != "fumbled-item-recovery" or not request.payload.get("item") is Dictionary:
		add_hint("The recovery request is malformed.")
		return
	var item: Dictionary = request.payload["item"]
	var instance_id := String(item.get("instanceId", ""))
	var charge_count := int(item.get("charges", 0))
	var charge_text := " • %d charge%s" % [charge_count, "" if charge_count == 1 else "s"] if charge_count > 0 else ""
	var remaining_text := " • %d items remain" % int(request.payload.get("remaining", 1)) if int(request.payload.get("remaining", 1)) > 1 else ""
	add_hint("%s%s%s" % [String(item.get("name", "Fumbled weapon")), charge_text, remaining_text])
	var characters: Variant = request.payload.get("characters", [])
	if characters is Array:
		for value: Variant in characters:
			if not value is Dictionary:
				continue
			var character: Dictionary = value
			add_response(
				"Give to %s" % String(character.get("name", "Character")),
				{"action": "assign", "instanceId": instance_id, "characterId": String(character.get("id", ""))},
				bool(character.get("enabled", false)),
				String(character.get("reason", ""))
			)
	add_response("Leave behind", {"action": "discard", "instanceId": instance_id})
