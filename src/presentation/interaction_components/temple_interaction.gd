class_name TempleInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	var characters: Variant = request.payload.get("characters", [])
	if characters is Array:
		for character: Variant in characters:
			if character is Dictionary:
				add_response("Heal %s • HP %d/%d" % [character.get("name", "Character"), int(character.get("currentHealth", 0)), int(character.get("maximumHealth", 0))], {"action": "heal", "characterId": String(character.get("id", ""))})
	add_response("Leave temple", {"action": "leave"})
